#!/usr/bin/env python3
"""Server-side speed + determinism suite. Every speed number is llama-server's own timing.

  server_suite.py OUT.json [--endpoint URL] [--skip-prefill]

Tests (all temperature 0, prompt cache off unless stated):
  prefill_2k / prefill_10k  cold prompt processing of ~2.4K / ~9.8K tokens of seeded filler
  decode_256                256 generated tokens (ignore_eos) of a short story
  followup                  turn 2 of a ~9.8K-token conversation (prompt cache on): tokens re-processed and TTFT
  story_400                 400-token greedy story: decode speed, draft acceptance, and the text's sha256
  code_edit                 rename a function in a 103-line Python file and return it whole (copy-heavy: where
                            speculative drafting pays); checks the output is exactly the expected file
"""
import argparse, hashlib, json, os, random, re, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
WORDS = ("the quick brown fox jumps over lazy dog while system memory bandwidth constrains decode "
         "throughput on unified architectures where weights stream from page cache").split()
SEED = 4242  # fixed: same prompts on every machine


def chat(ep, messages, max_tokens, **extra):
    body = {"model": "x", "messages": messages, "max_tokens": max_tokens, "temperature": 0, **extra}
    t0 = time.time()
    req = urllib.request.Request(ep, json.dumps(body).encode(), {"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(req, timeout=7200))
    return d["choices"][0]["message"].get("content") or "", d["timings"], time.time() - t0


def filler(n, seed):
    r = random.Random(seed)
    return f"[{seed}] " + " ".join(r.choice(WORDS) for _ in range(n))


def spec(t):
    out = {}
    if t.get("draft_n"):
        out = {"draft_n": t["draft_n"], "draft_accepted": t["draft_n_accepted"],
               "acceptance": round(t["draft_n_accepted"] / t["draft_n"], 3)}
    return out


def strip_fence(s):
    m = re.search(r"```(?:python)?\n(.*?)```", s, re.S)
    return (m.group(1) if m else s).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--endpoint", default=os.getenv("EP", "http://127.0.0.1:8732/v1/chat/completions"))
    ap.add_argument("--skip-prefill", action="store_true")
    a = ap.parse_args()
    ep, out = a.endpoint, {"time": time.strftime("%F %T")}

    def rec(name, value):
        out[name] = value
        print(f"{name:12} {json.dumps(value)}", flush=True)

    if not a.skip_prefill:
        for name, words in (("prefill_2k", 2300), ("prefill_10k", 9400)):
            _, t, _ = chat(ep, [{"role": "user", "content": filler(words, SEED + words) + "\nReply with one word."}],
                           8, cache_prompt=False)
            rec(name, {"tokens": t["prompt_n"], "tps": round(t["prompt_per_second"], 1)})

    _, t, _ = chat(ep, [{"role": "user", "content": "Write a long story about a lighthouse keeper."}],
                   256, ignore_eos=True, cache_prompt=False)
    rec("decode_256", {"tokens": t["predicted_n"], "tps": round(t["predicted_per_second"], 2), **spec(t)})

    if not a.skip_prefill:
        m1 = [{"role": "user", "content": filler(9400, SEED + 7) + "\nHow many times does the word fox appear? Guess a number."}]
        a1, t1, _ = chat(ep, m1, 16)
        m2 = m1 + [{"role": "assistant", "content": a1}, {"role": "user", "content": "Now guess for the word dog."}]
        _, t2, w2 = chat(ep, m2, 16)
        rec("followup", {"turn1_prompt": t1["prompt_n"], "turn2_processed": t2["prompt_n"],
                         "turn2_ttft_s": round(t2["prompt_ms"] / 1000, 2), "turn2_wall_s": round(w2, 1)})

    story, t, _ = chat(ep, [{"role": "user", "content": "Write a long story about a lighthouse keeper."}],
                       400, cache_prompt=False)
    rec("story_400", {"tokens": t["predicted_n"], "tps": round(t["predicted_per_second"], 2), **spec(t),
                      "sha256": hashlib.sha256(story.encode()).hexdigest()[:16]})
    out["story_400_text"] = story

    code = open(os.path.join(HERE, "data", "code_edit_input.py")).read()
    prompt = ("Return the following Python file in full, unchanged except rename the function `ask` to "
              "`query_model` everywhere. Output only the code.\n\n```python\n" + code + "\n```")
    got, t, _ = chat(ep, [{"role": "user", "content": prompt}], 1800, cache_prompt=False)
    expected = re.sub(r"\bask\(", "query_model(", code).strip()
    rec("code_edit", {"tokens": t["predicted_n"], "tps": round(t["predicted_per_second"], 2), **spec(t),
                      "exact": strip_fence(got) == expected})
    out["code_edit_text"] = got

    with open(a.out, "w") as f:
        json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
