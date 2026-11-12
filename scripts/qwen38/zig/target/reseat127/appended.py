"""A conflict whose only cause is that the new base APPENDED to a file our patch also changes at its end.

keep_appended(tree, path, marker) writes our side (the conflict's stage 3) followed by what the new base added
after the common ancestor (stage 2 minus stage 1), and refuses anything else: the new base's file must be the
ancestor plus a tail, and the tail must hold `marker`.
"""
import subprocess


def keep_appended(tree: str, path: str, marker: bytes) -> int:
    def stage(n: int) -> bytes:
        return subprocess.run(["git", "show", f":{n}:{path}"], cwd=tree, capture_output=True, check=True).stdout

    base, ours, theirs = stage(1), stage(2), stage(3)
    assert ours.startswith(base), f"{path}: the new base changed more than the file's end"
    tail = ours[len(base):]
    assert marker in tail and marker not in theirs, f"{path}: the appended block is not the one expected"
    sep = b"\r\n" if b"\r\n" in theirs else b"\n"
    with open(f"{tree}/{path}", "wb") as f:
        f.write(theirs + (b"" if tail.startswith((b"\n", b"\r\n")) else sep) + tail)
    return tail.count(sep)
