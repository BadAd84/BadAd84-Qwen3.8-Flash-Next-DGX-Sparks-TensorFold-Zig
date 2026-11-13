#!/usr/bin/env python3
"""fp8vis.py OUT.json: one image request to the local serve, a 64x64 PNG (left half red, right half blue), temperature 0."""
import base64
import json
import struct
import sys
import urllib.request
import zlib

BASE = "http://127.0.0.1:8888/v1"


def png(w, h):
    row = b"\x00" + b"".join(b"\xff\x00\x00" if x < w // 2 else b"\x00\x00\xff" for x in range(w))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(row * h)) + chunk(b"IEND", b"")


try:
    model = json.load(urllib.request.urlopen(BASE + "/models", timeout=30))["data"][0]["id"]
    image = "data:image/png;base64," + base64.b64encode(png(64, 64)).decode()
    body = {"model": model, "temperature": 0, "max_tokens": 96, "chat_template_kwargs": {"enable_thinking": False},
            "messages": [{"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": image}},
                {"type": "text", "text": "Which two colours fill this image, and which side is each on?"}]}]}
    req = urllib.request.Request(BASE + "/chat/completions", json.dumps(body).encode(), {"Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=600))
    out = {"content": r["choices"][0]["message"].get("content"), "usage": r.get("usage")}
except Exception as e:  # the failure is the result: it goes in the file and the log
    out = {"error": repr(e)[:400]}
with open(sys.argv[1], "w") as f:
    json.dump(out, f)
print("IMAGE", sys.argv[1], json.dumps(out)[:500])
