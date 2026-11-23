"""compare.py OUT - the arm records probe.py wrote under OUT/<label>/probe.json, one verdict a line.

Required (a failure):
  CROSS    the bf16-head arms' replies equal the default arm's, drafted and plain, on every prompt: the fix.
  DRAFTER  the bf16 arm's drafted requests still drafted (mtp_drafted_total grew), so an equality that held
           because the drafter had stopped cannot pass.
  PRE      the unfixed series image's bf16 arm reports the format refusal instead of serving (label `pre`).

Reported (never a failure): WITHIN, an arm's drafted reply against its own plain one. The series has a recorded
drafted-versus-plain difference on long prompts that is not this change's subject; it is measured per arm here so a
reader can see whether the bf16 head moves it.

Prints CMP lines and one SUMMARY line; exit 0 only when every required check holds.
"""
import json
import os
import sys

FIXED_ARMS = ("def", "bf16", "bf16n")
REFERENCE = "def"


def load(out):
    arms = {}
    for name in sorted(os.listdir(out)):
        path = os.path.join(out, name, "probe.json")
        if not os.path.exists(path) or os.path.getsize(path) <= 2:
            continue
        try:
            with open(path) as f:
                arms[name] = json.load(f)
        except Exception as exc:  # a record cut short is reported, never guessed
            print(f"CMP {name} unreadable {exc}")
    return arms


def run(rec, key, arm):
    return (rec.get("runs") or {}).get(f"{key}/{arm}") or {}


def sha(rec, key, arm):
    """The reply's engine-side token hash, else its text's own sha256 (a record whose block carried no hash)."""
    got = run(rec, key, arm)
    return (got.get("shas") or {}).get("token_sha256") or got.get("text_sha256")


def error(rec, key, arm):
    return run(rec, key, arm).get("error")


def main():
    out = sys.argv[1]
    arms = load(out)
    bad = 0
    if REFERENCE not in arms:
        print(f"CMP missing the reference arm {REFERENCE}")
        print("SUMMARY FAIL missing-reference")
        return 1
    keys = [p["key"] for p in arms[REFERENCE]["prompts"]]
    within_eq = within_differ = 0
    for key in keys:
        for arm in FIXED_ARMS:
            if arm not in arms:
                continue
            d, q = sha(arms[arm], key, "drafted"), sha(arms[arm], key, "plain")
            if d is None or q is None:
                print(f"CMP {key} {arm} within UNVERIFIED drafted={d} plain={q}")
                bad = 1
            elif d != q:
                within_differ += 1
                print(f"CMP {key} {arm} within DIFFER")
            else:
                within_eq += 1
                print(f"CMP {key} {arm} within EQ")
        for arm in FIXED_ARMS:
            if arm == REFERENCE or arm not in arms:
                continue
            for kind in ("drafted", "plain"):
                got = sha(arms[arm], key, kind)
                want = sha(arms[REFERENCE], key, kind)
                if got is None or want is None:
                    print(f"CMP {key} {arm} {kind} cross UNVERIFIED got={got} want={want}")
                    bad = 1
                elif got != want:
                    print(f"CMP {key} {arm} {kind} cross DIFFER got={got[:16]} want={want[:16]}")
                    bad = 1
                else:
                    print(f"CMP {key} {arm} {kind} cross EQ")
    if "bf16" in arms:
        drafted = sum(run(arms["bf16"], key, "drafted").get("counters", {}).get("mtp_drafted_total", 0) for key in keys)
        rounds = sum(run(arms["bf16"], key, "drafted").get("counters", {}).get("decode_rounds_total", 0) for key in keys)
        print(f"CMP bf16 drafter drafted {drafted:.0f} rounds {rounds:.0f}")
        if drafted <= 0:
            print("CMP bf16 drafter DID-NOT-DRAFT")
            bad = 1
    if "pre" in arms:
        errors = [error(arms["pre"], key, kind) for key in keys for kind in ("drafted", "plain")]
        named = [e for e in errors if e]
        if named:
            text = json.dumps(named[0])
            name = "FormatMismatch" if "FormatMismatch" in text else ("DraftHeadFormat" if "DraftHeadFormat" in text else text[:120])
            print(f"CMP pre refused {len(named)} of {len(errors)} requests name {name}")
            if name not in ("FormatMismatch", "DraftHeadFormat"):
                print("CMP pre refusal does not name the format check")
                bad = 1
        else:
            print("CMP pre SERVED (the unfixed series image did not refuse)")
            bad = 1
    print(f"CMP within eq {within_eq} differ {within_differ}")
    print("SUMMARY " + ("FAIL" if bad else "PASS"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
