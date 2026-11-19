"""Prove how the served endpoint treats thinking, and record the reply evidence.

Runs against the serve on --base and writes JSON to --out:
  models          what /v1/models advertises (id, capabilities)
  chat_off        a chat request with chat_template_kwargs {"enable_thinking": false}: content,
                  reasoning_content, and whether either contains a 'think' block
  completion      the first GSM8K prompt sent to /v1/completions exactly as the benchmark client sends it:
                  the reply prefix, whether it contains '<think>', and its finish_reason

Standard library only, so it runs on the Spark.
"""

import argparse
import json
import time
import urllib.request
from pathlib import Path


def post(base: str, path: str, body: dict, timeout: float) -> tuple[int, str]:
    request = urllib.request.Request(base.rstrip("/") + path, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.status, response.read().decode("utf-8", "replace")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="http://127.0.0.1:8888")
    parser.add_argument("--prompts", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    out = {"base": args.base, "time": time.strftime("%FT%T%z")}
    with urllib.request.urlopen(args.base.rstrip("/") + "/v1/models", timeout=30) as response:
        out["models"] = json.loads(response.read().decode())
    model = out["models"]["data"][0]["id"]

    try:
        status, raw = post(args.base, "/v1/chat/completions", {
            "model": model,
            "messages": [{"role": "user", "content": "What is 2+2? Answer with the number only."}],
            "max_tokens": 128,
            "temperature": 0,
            "chat_template_kwargs": {"enable_thinking": False},
        }, 300)
        message = json.loads(raw)["choices"][0]["message"]
        content = message.get("content") or ""
        reasoning = message.get("reasoning_content") or message.get("reasoning") or ""
        out["chat_off"] = {"http": status, "content": content[:600], "reasoning_content": reasoning[:600],
                           "content_has_think": "<think" in content.lower(),
                           "reasoning_has_think": "<think" in reasoning.lower()}
    except Exception as error:                     # the chat field may not exist here; the benchmark path must still be recorded
        out["chat_off"] = {"error": f"{type(error).__name__}: {error}"[:400]}

    first = json.loads(Path(args.prompts).read_text(encoding="utf-8").splitlines()[0])
    body = {"model": model, "prompt": first["prompt"], "max_tokens": 256, "temperature": 0}
    if first.get("stop"):
        body["stop"] = first["stop"]
    try:
        status, raw = post(args.base, "/v1/completions", body, 600)
        choice = json.loads(raw)["choices"][0]
        text = choice.get("text") or ""
        out["completion"] = {"http": status, "id": first["id"], "prefix": text[:600],
                             "has_think": "<think" in text.lower(), "finish_reason": choice.get("finish_reason"),
                             "chars": len(text)}
    except Exception as error:
        out["completion"] = {"error": f"{type(error).__name__}: {error}"[:400]}
    Path(args.out).write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: out[key] for key in ("chat_off", "completion")})[:400])


if __name__ == "__main__":
    main()
