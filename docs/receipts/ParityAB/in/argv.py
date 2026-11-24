#!/usr/bin/env python3
"""argv.py - the flag/value pairs a serve will be or was started with.

  argv.py line FILE      parse the first "tensorfold-native serve ..." line a DRY_RUN launcher printed
  argv.py cmd FILE.json  parse a `docker inspect --format '{{json .Config.Cmd}}'` array

Both print, one pair a line and tab-separated, every `--flag` and its value (empty for a bare flag), in order, plus
`# model <path>` and `# flagcount <n>` comment lines. Bare flags are those whose next token is another `--flag`;
every value these launchers pass is a single token, so that rule is exact for them and is checked by flagcount
against the raw token count.
"""
from __future__ import annotations
import json
import re
import sys

FLAG = re.compile(r"^--[A-Za-z0-9][A-Za-z0-9-]*$")


def pairs(tokens: list[str]) -> tuple[list[tuple[str, str]], str]:
    try:
        at = tokens.index("serve")
    except ValueError:
        raise SystemExit("no 'serve' token in the argv") from None
    rest = tokens[at + 1:]
    model = rest[0] if rest and not rest[0].startswith("--") else ""
    out: list[tuple[str, str]] = []
    i = 1 if model else 0
    while i < len(rest):
        token = rest[i]
        if not FLAG.match(token):
            raise SystemExit(f"token {token!r} is neither a flag nor a value position")
        if i + 1 < len(rest) and not FLAG.match(rest[i + 1]):
            out.append((token, rest[i + 1]))
            i += 2
        else:
            out.append((token, ""))
            i += 1
    return out, model


def main() -> int:
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "line":
        tokens: list[str] = []
        for raw in open(path, encoding="utf-8", errors="replace"):
            at = raw.find("tensorfold-native serve ")
            if at >= 0:
                tokens = raw[at:].split()
                break
        if not tokens:
            raise SystemExit(f"no 'tensorfold-native serve' line in {path}")
    elif mode == "cmd":
        tokens = json.load(open(path, encoding="utf-8"))
    else:
        raise SystemExit("mode is line or cmd")
    found, model = pairs(tokens)
    print(f"# model {model}")
    print(f"# flagcount {len(found)}")
    for flag, value in found:
        print(f"{flag}\t{value}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
