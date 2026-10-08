#!/usr/bin/env python3
"""Run the mutation corpus. Reports detection rate AND false-positive rate.

Mapping to the p/q/r taxonomy:
  q (SILENT) = said CLEAN on a mutated function - the defect passes review undetected
  r          = said BUG on a clean function - a human checks, finds nothing, loses time
  p          = correct verdict
Line-precision is tracked separately: flagging the right function but the wrong
line still sends a reviewer to the right place, so it is not a silent failure.
"""
import json, os, re, sys, time, urllib.request

ENDPOINT = os.getenv("BENCH_ENDPOINT", "http://127.0.0.1:8731/v1/chat/completions")
MODEL = os.getenv("BENCH_MODEL", "halogen-qwen3.8-flash-next")
CORPUS = "/opt/fixtures/mutations.json"
OUT = os.path.join(os.getenv("FIXTURE_RESULTS_DIR", "/opt/fixtures"), "mutation_results.json")


def ask(prompt):
    req = urllib.request.Request(
        ENDPOINT,
        data=json.dumps({"model": MODEL,
                         "messages": [{"role": "user", "content": prompt}],
                         "max_tokens": int(os.getenv("MUTATION_MAX_TOKENS", "24")), "temperature": 0,
                         "enable_thinking": False,
                         **json.loads(os.getenv("MUTATION_EXTRA_BODY", "{}"))}).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    with urllib.request.urlopen(req, timeout=600) as r:
        d = json.load(r)
    return ((d["choices"][0]["message"].get("content") or "").strip(),
            d.get("usage", {}).get("prompt_tokens"), time.perf_counter() - t0)


def parse(ans):
    if re.search(r"\bCLEAN\b", ans, re.I):
        return ("clean", None)
    m = re.search(r"\bBUG\b\D{0,8}(\d+)", ans, re.I)
    if m:
        return ("bug", int(m.group(1)))
    if re.search(r"\bBUG\b", ans, re.I):
        return ("bug", None)
    return ("unparsed", None)


def main():
    c = json.load(open(CORPUS))
    items = c["items"][:int(sys.argv[1])] if len(sys.argv) > 1 else c["items"]
    print(f"mutations {c['corpus_version']} sha={c['corpus_sha256']}  items={len(items)}\n", flush=True)
    rows = []
    for i, it in enumerate(items, 1):
        try:
            ans, ptok, lat = ask(it["prompt"])
        except Exception as e:
            print(f"  [{i:>2}] {it['id']:<15} ERROR {e!r}"[:100], flush=True)
            continue
        verdict, line = parse(ans)
        if it["mutated"]:
            if verdict == "bug":
                outcome, exact = "p", (line == it["ground_truth_line"])
            elif verdict == "clean":
                outcome, exact = "q", False          # MISSED the injected defect
            else:
                outcome, exact = "r", False
        else:
            if verdict == "clean":
                outcome, exact = "p", None
            elif verdict == "bug":
                outcome, exact = "r", None           # false positive
            else:
                outcome, exact = "r", None
        rows.append({"id": it["id"], "mutated": it["mutated"], "op": it["op"],
                     "truth_line": it["ground_truth_line"], "said": verdict,
                     "said_line": line, "outcome": outcome, "exact_line": exact,
                     "answer": ans[:40], "latency": round(lat, 1)})
        tag = ("MISS" if outcome == "q" else
               "FALSE-POS" if (outcome == "r" and not it["mutated"]) else
               "ok" + ("" if exact is not True else " (exact line)"))
        print(f"  [{i:>2}/{len(items)}] {it['id']:<15} truth={'BUG' if it['mutated'] else 'CLEAN':<5} "
              f"said={verdict:<8} {tag:<18} {lat:>5.1f}s", flush=True)

    mut = [r for r in rows if r["mutated"]]
    cln = [r for r in rows if not r["mutated"]]
    det = sum(1 for r in mut if r["said"] == "bug")
    exact = sum(1 for r in mut if r["exact_line"])
    fp = sum(1 for r in cln if r["said"] == "bug")
    print("\n" + "=" * 62)
    print(f"detection rate      {det}/{len(mut)} = {det/max(1,len(mut)):.0%}"
          f"   (exact line: {exact}/{len(mut)} = {exact/max(1,len(mut)):.0%})")
    print(f"false-positive rate {fp}/{len(cln)} = {fp/max(1,len(cln)):.0%}   <- without this, detection means nothing")
    q = sum(1 for r in rows if r["outcome"] == "q")
    print(f"\nSILENT error rate q = {q}/{len(rows)} = {q/max(1,len(rows)):.0%}  (missed defects)")
    if len(mut) and det / len(mut) >= 0.95 and fp / max(1, len(cln)) <= 0.05:
        print("!! TRIPWIRE: near-perfect on both halves - suspect a non-discriminating fixture set")
    if len(cln) and fp / len(cln) >= 0.95:
        print("!! TRIPWIRE: flags nearly everything - detection rate is meaningless")
    json.dump({"corpus_sha256": c["corpus_sha256"], "model": MODEL, "rows": rows},
              open(OUT, "w"), indent=1)
    print(f"\nwrote {OUT}")


if __name__ == "__main__":
    main()
