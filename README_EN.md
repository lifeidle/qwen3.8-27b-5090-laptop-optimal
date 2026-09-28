# Qwen3.8-27B · Single-card 24GB Limit Tuning Log

**Pushing TWIN-TURBO to the practical limits of an RTX 5090 Laptop 24GB — every number is a controlled measurement**

[中文版 →](./README.md) ｜ [Scripts →](./scripts) ｜ [Raw data →](./data)

[![Model](https://img.shields.io/badge/model-Qwen3.8--27B%20TWIN--TURBO-7c3aed)](https://huggingface.co/Qwen/Qwen3.8-27B)
[![Platform](https://img.shields.io/badge/platform-RTX%205090%20Laptop%2024GB-76b900)]()
[![Throughput](https://img.shields.io/badge/decode-74~78%20tok%2Fs-d97706)]()
[![Context](https://img.shields.io/badge/context-160K%20max%20stable-2563eb)]()
[![Engine](https://img.shields.io/badge/llama.cpp-b11223%20CUDA%2013.4-0ea5e9)]()
[![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0-059669)](#license)

---

## 🏆 Current Champion (copy-paste ready)

![current champion](assets/chart12-champion-stack.svg)

**One-line launch** (PowerShell; close the window to stop):

```powershell
& "D:\llama-upstream-b11223\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --ctx-checkpoints 4 --load-mode none --jinja --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082
```

### What this stack solves

| problem | status |
|---|---|
| **Overthinking** | ✅ **fixed in model weights, −93%** (runaway prompt: 19,859 → 1,318 thinking chars; 31.7 s to a full 6,034-char answer). No runtime patches needed. |
| **Precision** | ✅ **all-Q8_0 chain** (output heads + MTP heads + KV cache) — near-lossless, stable across long multi-turn sessions |
| **Long tasks** | ✅ 12-min full-load, 100 rounds, **zero decay** (78.7 → 83.7 tok/s) |
| **Vision** | ✅ ON, **3.9 s/image** (self-quantized q8_0 mmproj) |
| **Speed** | ✅ **74–78 tok/s** decode (vision loaded), ~1.8× from MTP |
| **The one trade-off: context** | ⚠️ **capped at 160K** — measured VRAM cliff at ~180K (192K = −25%). This is the maximum that runs *stably* on this card. |

> ⚠️ **Deliberately NOT used**: `--reasoning-budget` and `--chat-template-file` — the model ships its own 10-mode system (einstein/spoon/xhigh…); old runtime patches conflict with it.
>
> 📦 **Three downloads**: [esatapedico / TWIN-TURBO-NVFP4-GGUF](https://huggingface.co/esatapedico/Qwen3.8-27B-TWIN-TURBO-NVFP4-GGUF) → **MID-HIGH** tier (15.75 GB) · [mmproj](https://huggingface.co/Qwen/Qwen3.8-27B) (~0.9 GB, self-quantize to Q8_0 = 600 MB) · [llama.cpp b11223+ Windows CUDA](https://github.com/ggml-org/llama.cpp/releases) (main + cudart zips).

---

## 📈 Two key charts

**① MTP draft depth: 3 is the sweet spot** (re-validated on b11223)

![mtp depth](assets/chart13-mtp-depth.svg)

**② Context cliff: 160K is the max that runs stably**

![context cliff](assets/chart14-ctx-cliff.svg)

- Inside the non-spill zone, ctx size **does not affect speed** (152–176K all 74–77 tok/s)
- **168–176K is a knife edge**: same command, different launches → bimodal 74.7 ↔ 55–59 (VRAM 98% full; spilling depends on fragmentation luck)
- **184K+ consistently slower** (−12%), **192K+ −25%** (KV spills to system RAM)
- KV cost measured at **43.97 KiB/token**; 160K KV ≈ 6.9 GiB; whole-card ledger 23.96/24.46 GiB

---

## 🎯 10-second decision

| scenario | pick |
|---|---|
| daily chat / coding / agents (vision) | **the one-liner above** ✅ |
| ingesting 200K+ token documents | fallback: NVFP4-MTP-LOW + q4_0 KV + 262K ([data/context-scaling-history.md](data/context-scaling-history.md)) |
| two clients at once | `-np 2`: stream A lossless, stream B −17%, **aggregate +50%**, each slot 80K ([data/2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) §4) |
| true 1M-token sessions | 32GB+ VRAM (vLLM route) |
| can't stop thinking | **already fixed at model level** (−93%) |

---

## 🔁 Reproduce

```powershell
# 1. engine: official llama.cpp Windows CUDA package (main + cudart zips into one folder), b11223+
# 2. model: the three downloads above (hf-mirror.com for CN)
# 3. launch
.\scripts\start-twin-turbo-daily.ps1
# 4. verify
curl http://127.0.0.1:8082/health     # {"status":"ok"}
```

**Acceptance baseline**: 384-token generation at **74–78 tok/s** (server-timed; ±10% from MTP acceptance randomness).

**Measurement discipline** (how every number here was produced):
1. Read **server-side timings** only — never client-side deltas
2. A single reading is noise (50.6–79.4 seen for identical configs) → conclusions require **re-test consistency**
3. Sweeps must **re-run endpoints in reverse order** (thermal drift faked a "96K fastest" curve once)
4. Beware **knife-edge configs**: bimodal results across launches = unusable

**Tooling**: [`scripts/bench-parallel.py`](scripts/bench-parallel.py) · [`scripts/bench-mtp-sweep.ps1`](scripts/bench-mtp-sweep.ps1) · [`scripts/bench-ctx-fine.ps1`](scripts/bench-ctx-fine.ps1) · [`scripts/start-tt-bench.ps1`](scripts/start-tt-bench.ps1)

---

## 🗄️ Archive: rejected approaches (each with data)

<details>
<summary><b>❌ DFlash2 drafter (2026-09-28) — 4% acceptance on the finetune</b></summary>
Official DFlash2 for Qwen3.8-27B exists ([z-lab GGUF](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF); llama.cpp PR [#27342](https://github.com/ggml-org/llama.cpp/pull/27342)). Tested: Q4_K_M draft, n-max 7, 160K → **25.2 tok/s (−67%), draft acceptance 4%** (86/2,059). The drafter was trained on official Qwen3.8-27B and cannot predict this heavily re-tuned finetune; built-in MTP uses the finetune's own nextn heads. Worth testing only against the official model.
</details>

<details>
<summary><b>❌ NVFP4-MTP-LOW (rounds 1–8 daily driver) — superseded by TWIN-TURBO</b></summary>
Speed dual-winner of the 3-way quant duel (79.6 tok/s / 200K) but lower head precision (Q5_0/IQ4_XS vs all-Q8_0) and no model-level thinking fix. Decision record: [data/tturbo-adoption.md](data/tturbo-adoption.md). The 262K + q4_0 KV fallback config survives (see decision table).
</details>

<details>
<summary><b>❌ 192K+ context — VRAM spill, −25%</b></summary>
184K −12%, 192K −25%, 224K same. 168–176K is bimodal. (Under the smaller NVFP4-LOW weights, 192K used to work — the 15.75 GB TWIN-TURBO weights move the cliff.)
</details>

<details>
<summary><b>❌ Runtime thinking patches — conflict with the model's own mode system</b></summary>
TWIN-TURBO trains overthinking away (−93%); stacking budget+template patches made it slower. Historical fixes (still valid for un-finetuned models): [docs/xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md), [docs/reasoning-guide.md](docs/reasoning-guide.md)
</details>

<details>
<summary><b>❌ Rejected during the 53→1 quant funnel (IQ3_S / UD-Q4_K_S / SSMFIX / iMatrix …)</b></summary>
Funnel: <a href="#-10-round-log">round log below</a> · iMatrix hybrid (−27% speed): [data/round2-new-results.md](data/round2-new-results.md) · YaRN 1M (4–5 tok/s) and the 262K hard cap: [docs/context-limits-and-yarn.md](docs/context-limits-and-yarn.md)
</details>

## 📜 10-round log

| round | theme | takeaway |
|---|---|---|
| 1 | quant selection (53 → 1) | NVFP4-LOW wins (speed dual-crown) |
| 2 | KV + MTP tuning | MTP n-max 3 (+40%) |
| 3 | thinking control | xhigh fix: budget + template injection |
| 4 | self-built engine | CUDA 13.3 pairing: prefill +13%, upstream bug fixed ([#28790](https://github.com/ggml-org/llama.cpp/issues/28790)) |
| 5 | context correction | `-np 1` frees VRAM, 150K → 180K |
| 6 | exhaustive re-check | 40+ params swept |
| 7 | context truth | q4_0 KV unlocks 256K · silent cap & YaRN reality |
| 8 | model switch | **TWIN-TURBO MID-HIGH promoted**: −93% thinking, all-Q8_0, patches retired |
| 9 | engine refresh (09-28) | **official b11146/b11223 CUDA 13.4**: CUDA graphs for MTP draft — same peak, **higher floor** |
| 10 | final tuning (09-28) | MTP depth re-validated · **DFlash2 rejected** (4% acceptance) · dual-slot +50% · **context cliff mapped**: 160K final |

---

## ❓ FAQ

**Q: Why not 256K (the model's native max)?**
A: The 24GB card cannot hold 256K KV at speed — 192K already spills (−25%). 160K is the max stable value. For 260K-token ingest, use the fallback config (NVFP4-MTP-LOW + q4_0 KV).

**Q: Does q8_0 KV lose quality?**
A: Near-lossless; long-recall tests (12K/70% and 150K/80% depth) all pass.

**Q: Why not vLLM / SGLang?**
A: On Blackwell laptops their VRAM management and GGUF ecosystem are less flexible; NVFP4 weights ship as GGUF. SGLang/vLLM is the home of "official model + server stack" combos like DFlash2.

**Q: How much faster on a desktop 5090?**
A: prefill 2–3×, decode 1.5–2× (575W vs 145W). Capacity conclusions transfer as a method — re-measure for your weights' size.

**Q: 16GB card?**
A: smaller tier + q8_0 KV + ~96K ctx; or IQ3_S (11.3 GB) for capacity.

**Q: Multiple instances?**
A: Two 27B instances don't fit. Use in-instance `-np 2` (aggregate +50%).

**Q: Image input?**
A: Native VLM. `--mmproj` (self-quantized Q8_0 = 600 MB), ~1GB extra VRAM — part of the ctx cliff math.

---

## 🔧 Troubleshooting

| symptom | cause & fix |
|---|---|
| exits at start, empty log | arg incompatibility. `--no-mmap` was removed; use `--load-mode none` |
| `failed to allocate buffer for kv cache` | ctx beyond VRAM. lower `-c` |
| starts but stutters | VRAM on the edge (<200 MiB free). drop 8–16K ctx |
| same config, 20%+ speed swings | knife-edge VRAM saturation. drop to a ctx tier with headroom |
| all thinking, no answer | missing `reasoning_effort`; default xhigh burns the budget |
| garbled output | request body not UTF-8 (write JSON file + `curl --data-binary @file`) |

---

## 📚 Full data & docs index (archive)

### history (`data/`)

| file | content |
|---|---|
| [2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) | **rounds 9–10**: engine refresh / MTP re-validation / DFlash2 / dual-slot / context cliff |
| [tturbo-adoption.md](data/tturbo-adoption.md) | **round 8**: model-switch decision record |
| [nmax-3-vs-4-comparison.md](data/nmax-3-vs-4-comparison.md) | strict MTP depth comparison |
| [context-scaling-history.md](data/context-scaling-history.md) | full context exploration: 88K → 256K |
| [final-benchmark.md](data/final-benchmark.md) | champion baseline (stability / TTFT / vision) |
| [speed-results.md](data/speed-results.md) ｜ [round2-new-results.md](data/round2-new-results.md) ｜ [round3-6-latest.md](data/round3-6-latest.md) | rounds 1–6 raw data |
| [thermal-stress-12min-100rounds.txt](data/thermal-stress-12min-100rounds.txt) | 12-min thermal raw log |

### docs (`docs/`)

[context-limits-and-yarn.md](docs/context-limits-and-yarn.md) · [windows-self-build-recipe.md](docs/windows-self-build-recipe.md) · [custom-build-and-mtp-bug.md](docs/custom-build-and-mtp-bug.md) · [reasoning-guide.md](docs/reasoning-guide.md) · [xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md) · [vision-setup.md](docs/vision-setup.md) · [ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md)

Historical charts live in [assets/](./assets) (chart1–chart11), generated by [tools/](./tools).

---

## License

| content | license |
|---|---|
| code (`scripts/`, `tools/`) | **MIT** |
| docs & data (README, `docs/`, `data/`, charts) | **CC BY 4.0** |

Third-party: Qwen3.8-27B weights **Apache 2.0** ([Qwen](https://huggingface.co/Qwen/Qwen3.8-27B)) · TWIN-TURBO GGUF per its model card ([esatapedico](https://huggingface.co/esatapedico)) · llama.cpp **MIT** · CUDA under NVIDIA EULA. **No model weights are included in this repo.** Full terms: [LICENSE](LICENSE), [docs/ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md).

## Acknowledgments

**Alibaba / Qwen team** (base model) · **DavidAU** (TWIN-TURBO thinking fix) · **esatapedico** (NVFP4 GGUF family) · **unsloth / DASLab** (quant methods) · **llama.cpp community** (engine, MTP, CUDA graphs) · **z-lab / NVIDIA** (DFlash2 — rejected here, respected everywhere)
