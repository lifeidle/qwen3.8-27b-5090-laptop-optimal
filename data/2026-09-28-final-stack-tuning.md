# Round 9–10 (2026-09-28): Final stack tuning — engine refresh, MTP re-validation, DFlash2 evaluation, concurrency, context cliff

All measurements: **server-side timings** (llama-server `timings` / slot `print_timing`), 384-token generations, single stream unless noted. Machine: RTX 5090 Laptop 24GB, TWIN-TURBO MID-HIGH (15.75 GB NVFP4), vision ON, MTP `draft-n-max 3`, KV q8_0, `-c 163840`, `-np 1` unless stated.

**Methodology notes learned the hard way (apply to every future sweep):**
1. Read the server's own timings, never client-side wall-clock deltas.
2. A single reading is noise (±10%, 50.6–79.4 tok/s observed for identical configs). Conclusions require **re-test consistency**.
3. Sweep order confounds: ascending sweeps let thermal drift masquerade as a trend. Always **re-run endpoints in reverse order** before believing a curve.
4. Watch for "knife-edge" configs: same command, different runs, bimodal results (see §5).

---

## 1. Engine upgrade (Round 9)

| Build | Identity | Result |
|---|---|---|
| `llama-custom13` (old daily) | 0.4.0-dev **b10914**, self-built 2026-09-12, fork | 4 shots across the day: 74.1 / 68.5 / 58.2 / 75.6 — wide spread |
| **b11146** (v0.5.0 nightly) | 0.5.0-dev, official CUDA 13.4, Clang 20.1.8 | 4 shots: 74.7 / 77.6 / 76.2 / 76.5 — **tight** |
| **b11223** (latest nightly, 77 commits later) | 0.5.0-dev | confirmed equal to b11146 |

Why it matters: **PR [#28549](https://github.com/ggml-org/llama.cpp/pull/28549) "Enable CUDA graph for MTP draft" merged 2026-09-16** — four days after our old build. Log evidence on b11146/b11223: slot timing shows `graphs reused` climbing (110 → 438+). Peak speed unchanged (~76), but the **floor rose** — no more mystery dips to 58–68. For interactive use the floor matters more than the peak.

Upgrade method: official prebuilt `llama-b11146-bin-win-cuda-13.4-x64.zip` (+cudart zip) dropped into a fresh folder — zero risk to the existing build. Windows release zips now bundle the CUDA runtime DLLs.

## 2. MTP draft depth re-sweep (Round 10)

| config | steady tok/s | verdict |
|---|---|---|
| spec off (reference) | 37.9 | MTP delivers ~1.8× |
| draft-n-max 2 | 69.7 | tie with 3 |
| **draft-n-max 3 (champion)** | **68.5–77.6 across the day** | ✅ keep |
| draft-n-max 5 | 23.1 | ❌ collapse (−66%) |

Deep drafting collapses because Qwen3.8's MTP is a single prediction head: drafting 5 tokens = 5 sequential head applications with compounding error. **Context was NOT retuned for MTP — MTP parameters do not consume KV.**

## 3. DFlash2 evaluation — rejected

DFlash2 (block-diffusion drafter, NVIDIA-backed) exists for Qwen3.8-27B: [incoai/Qwen3.8-27B-DFlash2-GGUF](https://huggingface.co/incoai/Qwen3.8-27B-DFlash2-GGUF) (Q4_K_M 1.1 GB; official acceptance-length 5.39 vs built-in MTP's ~4-5 on SGLang/H200). llama.cpp support merged via PR [#27342](https://github.com/ggml-org/llama.cpp/pull/27342) (2026-08-27); our b11223 binary contains `dflash2`.

**Our test** (Q4_K_M draft, `--spec-draft-n-max 7`, 160K ctx, fits in 24 GB):

| metric | value |
|---|---|
| decode speed | **25.2 tok/s** (vs 76.3 with MTP — **−67%**) |
| **draft acceptance** | **4%** (86 accepted / 2,059 drafted) |

Root cause: the drafter was trained against **official** Qwen3.8-27B; TWIN-TURBO is a heavily re-tuned finetune whose output distribution the drafter cannot predict. Built-in MTP works because its `nextn` heads ship **inside** the finetune and evolve with it. Verdict: DFlash2 is only worth testing against the official model.

## 4. Dual-slot concurrency (`-np 2`)

| stream | speed | vs single |
|---|---|---|
| stream A | 59.2–59.8 tok/s | ≈ lossless |
| stream B | 47.7–50.4 tok/s | −17~20% |
| **aggregate** | **86–95 tok/s** | **+45~58%** |

Cost: each slot's context ceiling halves (160K → 80K per slot). KV total and VRAM unchanged. Speculative MTP survives `-np 2` (verified). Two same-time requests finish in ~8–9 s vs ~13 s serialized.

## 5. Context cliff mapping (the round's main result)

Coarse sweep (96/128/160/192/224K) + fine sweep (152/160/168/176/184K @ 8K steps) + **reverse-order re-runs** to separate real cliffs from thermal drift.

| ctx (K tokens) | VRAM after load | steady tok/s | verdict |
|---|---|---|---|
| 96 | 21.3 GiB | 74.4–77.3 | fast, small cap |
| 128 | 22.7 GiB | 77.6 | fastest+headroom |
| 152 | 23.7 GiB | 75.0 / 73.2 (re-run) | clean |
| **160** | **23.96 GiB (98%)** | **74–78 typical** | ⭐ **recommended — max stable** |
| 168 | 24.0 GiB | 76.7 | unconfirmed single reading |
| 176 | 24.0 GiB | 74.7 … then 58.8/55.3/55.9 | ❌ **knife-edge (bimodal)** |
| 184 | 24.0 GiB | 65.6 / 66.3 (re-run) | ❌ −12% consistent |
| 192 | 24.0 GiB | 54.2 | ❌ −25% (VRAM spill) |
| 224 | 24.0 GiB | 57.8 | ❌ −25% |

Two key findings:

1. **Inside the non-spill zone, ctx size does not affect speed.** An earlier "96K is fastest (84)" reading was pure thermal drift — exposed by reverse-order re-runs.
2. **Knife-edge zone (168–176K)**: same command, different launches → bimodal 74.7 vs 55–59. VRAM sits at 98%; whether the instance spills depends on per-launch fragmentation luck. Unpredictable is worse than uniformly slow.

**VRAM ledger at 160K** (KV measured at **43.97 KiB/token** from clean deltas): weights 15.75 GB + KV ≈ 6.9 GiB + mmproj 0.6 GB + buffers ≈ 23.96 / 24.46 GiB. Every +32K tokens ≈ +1.4 GiB KV → the cliff.

**Final call: keep `-c 163840`.** It is the maximum context with proven stability. If you never fill it, 128K buys 2.4 GiB of headroom at zero speed cost.

## 6. Version audit (same day)

| tool | local | latest | note |
|---|---|---|---|
| llama.cpp | **b11223** | b11223 | upgraded from b10914 fork |
| NVIDIA driver | 616.56 | 616.92 (2026-09-09 WHQL) | compatible; update optional |
| gh CLI | 2.100.0 | 2.101.0 | cosmetic |
| curl / Python | 8.21.0 / 3.13.14 | — | fine |
