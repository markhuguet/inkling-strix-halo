#!/usr/bin/env python3
"""Collect a results directory into flat metrics and compare with the reference run.

  compare.py RESULTS_DIR                      print a markdown summary vs reference/reference-results.json
  compare.py RESULTS_DIR --write-reference    (maintainers) make this run the reference
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "reference", "reference-results.json")
TOL = 0.10  # speed within ±10% of the reference counts as reproduced


def collect(d):
    m = {}
    for f in sorted(glob.glob(os.path.join(d, "llama-bench-*.jsonl"))):
        for line in open(f):
            r = json.loads(line)
            kind = f"pp{r['n_prompt']}" if r["n_prompt"] else f"tg{r['n_gen']}"
            m[f"llama-bench {kind} @{r['n_depth']}"] = round(r["avg_ts"], 2)
    for f in sorted(glob.glob(os.path.join(d, "server-*.json"))):
        p = os.path.basename(f)[len("server-"):-len(".json")]
        s = json.load(open(f))
        for k in ("prefill_2k", "prefill_10k", "decode_256", "story_400", "code_edit"):
            if k in s:
                m[f"server[{p}] {k} tok/s"] = s[k]["tps"]
                if "acceptance" in s[k]:
                    m[f"server[{p}] {k} draft acceptance"] = s[k]["acceptance"]
        if "followup" in s:
            m[f"server[{p}] follow-up TTFT s"] = s["followup"]["turn2_ttft_s"]
        if "story_400" in s:
            m[f"server[{p}] story_400 sha256"] = s["story_400"]["sha256"]
        if "code_edit" in s:
            m[f"server[{p}] code_edit exact"] = s["code_edit"]["exact"]
    f = os.path.join(d, "mtp-check.txt")
    if os.path.exists(f):
        for line in open(f):
            r = re.match(r"depth (\d+): argmax == target greedy ([\d.]+)", line)
            if r:
                m[f"mtp depth {r.group(1)} == target greedy"] = float(r.group(2))
    for f in sorted(glob.glob(os.path.join(d, "test-ops-*.log"))):
        op = os.path.basename(f)[len("test-ops-"):-len(".log")]
        r = re.findall(r"(\d+)/(\d+) tests passed", open(f).read())
        if r:
            m[f"test-backend-ops {op}"] = f"{r[-1][0]}/{r[-1][1]}"
    return m


def verdict(k, ref, cur):
    if cur is None:
        return "missing"
    if isinstance(ref, (bool, str)):
        return "same" if ref == cur else "**DIFFERS**"
    if "acceptance" in k or "mtp depth" in k:
        return "same" if abs(cur - ref) <= 0.05 else "**DIFFERS**"
    ratio = (ref / cur if cur else 0) if "TTFT" in k else (cur / ref if ref else 0)  # TTFT: lower is better
    return "ok" if ratio >= 1 - TOL else "**slower**"


def main():
    d = sys.argv[1]
    cur = collect(d)
    if "--write-reference" in sys.argv:
        env = open(os.path.join(d, "environment.txt")).read() if os.path.exists(os.path.join(d, "environment.txt")) else ""
        json.dump({"metrics": cur, "environment": env}, open(REF, "w"), indent=1)
        print(f"wrote {REF} ({len(cur)} metrics)")
        return
    if not os.path.exists(REF):
        sys.exit(f"no reference at {REF}")
    ref = json.load(open(REF))["metrics"]
    print(f"# Results: {os.path.basename(os.path.normpath(d))}\n")
    print("| metric | reference | this run | Δ | verdict |\n|---|---|---|---|---|")
    bad = 0
    for k in sorted(set(ref) | set(cur), key=lambda k: (k.split()[0], k)):
        r, c = ref.get(k), cur.get(k)
        delta = f"{(c - r) / r * 100:+.1f}%" if isinstance(r, (int, float)) and not isinstance(r, bool) \
            and isinstance(c, (int, float)) and r else ""
        v = verdict(k, r, c) if r is not None else "new"
        bad += v.startswith("**") or v in ("missing", "new")
        print(f"| {k} | {r if r is not None else ''} | {c if c is not None else ''} | {delta} | {v} |")
    print(f"\n{'All metrics reproduced' if not bad else f'{bad} metric(s) outside tolerance'} "
          f"(speed: within {TOL:.0%} or faster; acceptance/MTP accuracy: within 0.05; hashes/exactness: identical).")
    print("A differing story sha256 with the same tree, image and GPU usually means a different ROCm/kernel driver "
          "or GPU firmware: this model is numerically sensitive, so greedy text can change while quality does not.")


if __name__ == "__main__":
    main()
