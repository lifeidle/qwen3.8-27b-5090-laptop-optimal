# -*- coding: utf-8 -*-
# Concurrency benchmark for llama-server.
# Usage: python bench_parallel.py <port> <single|dual> <n_predict> [runs]
# Reads SERVER-side timings from response (authoritative), wall clock as backup.

import json, sys, time, threading, urllib.request

PORT   = int(sys.argv[1]) if len(sys.argv) > 1 else 8082
MODE   = sys.argv[2] if len(sys.argv) > 2 else "single"
NPRED  = int(sys.argv[3]) if len(sys.argv) > 3 else 384
RUNS   = int(sys.argv[4]) if len(sys.argv) > 4 else 1
URL    = f"http://127.0.0.1:{PORT}/v1/chat/completions"

PROMPTS = [
    "Write a Python function that computes the longest common subsequence of two strings "
    "using dynamic programming. Include a short explanation and two test cases.",
    "Explain how attention works in a transformer, in plain language, with a small worked "
    "numeric example.",
]

def one(idx, results, barrier=None):
    if barrier:
        barrier.wait()
    t0 = time.perf_counter()
    body = json.dumps({
        "messages": [{"role": "user", "content": PROMPTS[idx % len(PROMPTS)]}],
        "max_tokens": NPRED,
        "stream": False,
    }).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            resp = json.loads(r.read())
        wall = time.perf_counter() - t0
        u = resp.get("usage", {}) or {}
        t = resp.get("timings", {}) or {}
        rec = {
            "idx": idx,
            "wall_s": round(wall, 2),
            "completion_tokens": u.get("completion_tokens"),
            "server_tok_s": None,
        }
        # llama.cpp timings fields (authoritative server-side decode time)
        ms  = t.get("predicted_ms") or t.get("eval_ms")
        nt  = t.get("predicted_n") or t.get("eval_tokens")
        if t.get("predicted_per_second"):
            rec["server_tok_s"] = round(t["predicted_per_second"], 1)
        elif ms and nt:
            rec["server_tok_s"] = round(nt / ms * 1000, 1)
        if rec["completion_tokens"] and wall > 0:
            rec["client_tok_s"] = round(rec["completion_tokens"] / wall, 1)
        results[idx] = rec
    except Exception as e:
        results[idx] = {"idx": idx, "error": repr(e),
                        "wall_s": round(time.perf_counter() - t0, 2)}

for run in range(RUNS):
    results = {}
    if MODE == "single":
        one(0, results)
        payload = {"run": run, "requests": [results[0]]}
    else:
        b = threading.Barrier(2)
        ths = [threading.Thread(target=one, args=(i, results, b)) for i in range(2)]
        t0 = time.perf_counter()
        for t in ths: t.start()
        for t in ths: t.join()
        wall_total = time.perf_counter() - t0
        payload = {"run": run, "wall_total_s": round(wall_total, 2),
                   "requests": [results[i] for i in range(2)]}
        ok = [r for r in payload["requests"] if "error" not in r]
        if len(ok) == 2 and all(r.get("completion_tokens") for r in ok):
            toks = sum(r["completion_tokens"] for r in ok)
            payload["aggregate_client_tok_s"] = round(toks / wall_total, 1)
    print("RESULT|" + json.dumps(payload, ensure_ascii=False), flush=True)
