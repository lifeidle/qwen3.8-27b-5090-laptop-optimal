# Qwen3.8-27B on a Single 24GB GPU — Quantization & Tuning Study

**Selecting the best of 53 community quantization variants, then optimizing layer-by-layer to the hardware limit**

[中文版 →](./README.md) ｜ [Scripts →](./scripts) ｜ [Raw data →](./data)

[![Model](https://img.shields.io/badge/model-Qwen3.8--27B-7c3aed)](https://huggingface.co/Qwen/Qwen3.8-27B)
[![Platform](https://img.shields.io/badge/platform-RTX%205090%20Laptop%2024GB-76b900)]()
[![Throughput](https://img.shields.io/badge/throughput-80~87%20tok%2Fs-d97706)]()
[![Context](https://img.shields.io/badge/context-180K%20vision%20%2F%20190K%20text-2563eb)]()
[![Engine](https://img.shields.io/badge/llama.cpp-self--built%20CUDA%2013.3-0ea5e9)]()
[![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0-059669)](#license)

---

## 🏆 Final Results (TL;DR — copy this config)

| Metric | Result |
|---|---|
| **Generation** | **74.2 tok/s** (vision on) · 79.8 (text-only) |
| **Time to first token** | **0.17 s** (short) · 2.78 s (4K) · 30.97 s (45K) |
| **Context** | **262,144** (model hard ceiling, verified) |
| **Vision** | ✅ on, **2.9 s/image** |
| **At full load** | 29.5 tok/s (after loading 137,944 tokens) |
| **Prefill** | **1992 tok/s** (4K) |

**Vision mode · one-line launch** (paste into PowerShell; close the window to stop):

```powershell
& "D:\llama.cpp\build\bin\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --cache-type-k q8_0 --cache-type-v q8_0 --ctx-checkpoints 4 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --reasoning-budget 12000 --chat-template-file "D:\models\Qwen3.8-27B\custom_template.jinja" --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082 --load-mode none --jinja
```

> Adjust the paths to your setup. **262,144 is the model's hard ceiling** — `-c` values above it are silently capped.

**Common basis**: NVFP4-MTP-LOW (14.47 GiB) · **q4_0 KV** · **self-built CUDA 13.3** · RTX 5090 Laptop 24GB

### 📦 What to download (3 pieces)

| File | Size | Where |
|---|---|---|
| **Qwen3.8-27B-NVFP4-MTP-LOW.gguf** (main model) | 14.47 GiB | [**esatapedico / Qwen3.8-27B-NVFP4-MTP-GGUF**](https://huggingface.co/esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF) → pick the **`LOW`** tier |
| **mmproj-BF16.gguf** (vision component) | 888 MB | [Qwen / Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) official repo (optionally self-quantize to Q8_0 to save 288 MB → [vision setup](docs/vision-setup.md)) |
| **llama.cpp engine** | ~35 MB | [official CUDA release](https://github.com/ggml-org/llama.cpp/releases) (or follow the [self-build recipe](docs/windows-self-build-recipe.en.md) for this repo's performance) |

> 🧩 **Anti-overthinking template** (`custom_template.jinja`) ships with this repo → [scripts/custom_template.jinja](scripts/custom_template.jinja)
> 🌐 **China acceleration**: replace `huggingface.co` with `hf-mirror.com` in the download URLs.

![Final performance](assets/chart11-final-performance.svg)

## 🎯 10-Second Decision

| Your scenario | Choice |
|---|---|
| Daily chat / coding / agents (with vision) | **Vision 180K** (the one-liner above) |
| Very long text-only material (> 180K) | Text 190K (drop the mmproj segment) |
| Multiple clients at once | add `-np 2` (~0.1 GB VRAM cost) |
| Thinking never stops | Already double-fused (budget + template injection) — nothing to do |

**Eight counter-intuitive findings** (all with control-group data):

1. **The hard ceiling is 262,144** — llama.cpp **silently caps** any larger `-c` (short test prompts never expose it)
2. **q4_0 KV is faster than q8_0** — at 256K: q8_0 = **9.1 tok/s**, q4_0 = **87–91**; recall tested lossless
3. **YaRN reaches 1M but only runs at 4–5 tok/s** — the unlock flags work, the performance does not
4. **The context-speed curve is not monotonic** — 182~186K sags (59~62), 188~190K recovers (81~87): never interpolate
5. **One system-prompt line cures overthinking** — thinking −46%, content restored (`presence_penalty` / fixed template / lower context all ineffective)
6. **Toolchain pairing is a hard red line for self-builds** — nvcc 12.8 + MSVC made MTP prefill 57× slower ([#28790](https://github.com/ggml-org/llama.cpp/issues/28790))
7. **Several "community-recommended" flags are regressions here**: `-ub 1024` (−16%), `--spec-default` (−39%), iMatrix mixed quant (−27%)
8. **n-max 3 vs 4 is nearly a tie** — a rigorous interleaved test (15 samples each) shows n-max 4 is 3–4% faster on average but **twice as volatile** (69–101 vs 74–89 tok/s) → **kept n-max 3**. See [comparison report](data/nmax-3-vs-4-comparison.md)

## 📜 Seven Rounds of Tuning

| Round | Theme | Key gain |
|---|---|---|
| 1 | **Quant selection** (53 → 1) | NVFP4-LOW wins (fastest, quality tied) |
| 2 | **KV + MTP tuning** | MTP n-max 3 (+40% generation) |
| 3 | **Thinking control** | xhigh fixed: `--reasoning-budget` + template injection |
| 4 | **Self-built engine** | CUDA 13.3 official pairing: prefill +13% · upstream bug fixed |
| 5 | **Context correction (1)** | 150K → 180K (`-np 1` frees 1.15 GB of VRAM) |
| 6 | **Exhaustive re-check** | 40+ params swept; no stone unturned |
| 7 | **Context truth (this round)** | **q4_0 KV makes 256K truly usable** (+45% context, faster) · silent-cap & YaRN truths uncovered |

## 📊 Scoreboard (final config, measured)

| Dimension | Value |
|---|---|
| Generation | **74.2 tok/s** (vision on) · 79.8 (text-only) |
| Time to first token | **0.17 s** (short) · 2.78 s (4K) · 30.97 s (45K) |
| Long-input | **1992 tok/s** (4K prefill) · 45K in 31 s |
| Vision | **2.9 s/image** (Q8 mmproj, median of 3) |
| Context | **262,144** (hard ceiling; q4_0 makes it usable) |
| At full load | 29.5 tok/s (137,944 tokens loaded) |
| VRAM free | 551 MB @ 256K vision |
| Concurrency | `-np 2` 131K each (113 agg) · `-np 4` 65K each (124 agg) |
| Thermals | 12-minute full load, **zero degradation** |
| Thinking control | xhigh + double fuse (budget 12000 + template injection) |

![Parameter scoreboard](assets/chart8-parameter-scoreboard.svg)

> 📖 Docs: [docs/](./docs) | Raw data: [data/](./data)

---

## 🥇 Model Selection: 53 → 1

**Winner: NVFP4-MTP-LOW + q8_0 KV + MTP n-max 3 + llama.cpp b10889**

```powershell
# One-command launch (edit the two path variables at the top of the script first)
.\scripts\start-nvfp4-low.ps1        # → http://127.0.0.1:8082
```

### Three-Way Final Duel (each model at its own optimum, same machine, same conditions)

| | 🥇 **NVFP4-LOW** | 🥈 IQ3_S | 🥉 UD-Q4_K_S |
|---|---|---|---|
| **Generation speed** | **79.6 tok/s** | 64.4 tok/s | 51.7 tok/s |
| **15.6K-token prompt** | **9.7 s** | 14.9 s | 19.9 s |
| **Max context** | 200K (192K recommended) | **212K** (240K extreme) | 200K |
| **Model size** | 14.47 GiB | **11.29 GiB** | 14.30 GiB |
| **Method** | All-NVFP4 + light heads | GSQ-RCO mixed (~3.5 bpw) | Dynamic Q4_K_S (~4.4 bpw) |
| **Quality** | Tie | Tie (**task-lossless**, academically validated) | Tie (most rigorous details) |
| **Role** | **Daily driver** ✅ | Ultra-long-context backup | Archive |

> **In one line**: NVFP4-LOW wins both speed metrics (+24% generation, −35% prompt latency vs the runner-up), and its quality gap to BF16 is unmeasurable in a community 4,800-task controlled test. IQ3_S is only worth switching to when you need 210K+ tokens of context.

![Speed duel](assets/chart1-speed-duel.svg)

---

## 📌 Three Core Findings (updated 2026-09-15)

1. **q4_0 KV is the key to doubling context** — at the same 256K: q8_0 manages only **9.1 tok/s**, q4_0 reaches **87–91**, with recall tested lossless.
   > *Correction*: an early "q4_0-class KV is 28× slower" result was an artifact of a **mixed type** (`K=q8_0 + V=q4_0`) — **full q4_0 has no such problem**. See [context truth](docs/context-limits-and-yarn.md).
2. **MTP needs no tuning** — n-max 3 is optimal on a 24GB card (2/3/4/5 and p-min all swept). High acceptance ≠ high speed.
3. **Engine gains depend on quantization type** — b10840 → b10889 gave NVFP4 +6.6% speed and +48K capacity, but K-quants −11%. **Always re-measure capacity after an engine upgrade.**

---

## 📊 Full Test Results

> ⚠️ **The sections below are historical measurement records** from each round (kept to show the full process). For the **current optimal config and latest data, see the TL;DR at the top**; newest round data: [data/round3-6-latest.md](data/round3-6-latest.md).

### 1️⃣ Context capacity: KV quantization is the lever

![Context capacity](assets/chart2-context-capacity.svg)

| Model | F16 KV ceiling | **q8_0 KV ceiling** | q4_0-class KV |
|---|---|---|---|
| IQ3_S | 136K | **212K** (240K extreme) | 256K ⚠️ 28× (mixed-type artifact, see notes) |
| NVFP4-LOW | 96K | **200K** | — |
| NVFP4-MID-HIGH | 88K | ~160K (est.) | — |
| UD-Q4_K_S | 96K | 200K | — |

**Slow-path evidence** (same 15.6K-token prompt):

| Config | Latency | Verdict |
|---|---|---|
| 32K + F16 KV | 13.6 s | Baseline |
| 136K + F16 KV | 15.2 s | No penalty |
| 200K + **q8_0** | **15.1 s** | **No penalty** ✅ |
| 256K + **q4_0-class** | **~420 s, never finished** | ❌ Kernel fallback; throughput decays 286 → 29 tok/s |

### 2️⃣ Speed duel (cross-validated on two engine builds)

| Model | Engine b10840 (old) | Engine b10889 (new) | Delta |
|---|---|---|---|
| **NVFP4-LOW** | 74.7 tok/s / 152K / 10.1s | **79.6 / 200K / 9.7s** | **+6.6%, +48K** |
| IQ3_S | 61.9 / 212K / 15.5s | 64.4 / 212K / 14.9s | +4% |
| UD-Q4_K_S | 58.3 / 152K / 15.2s | 51.7 / 200K / 19.9s | **−11%** (no benefit) |

**Why**:
- **Why LOW is fastest** — its light heads (Q5_0 output + IQ4_XS MTP) minimize read cost on every MTP verification/draft pass. The community observed the same pattern on a desktop RTX 5090.
- **Why UD has the highest acceptance (73%) yet is slowest** — K-quant's per-pass verification cost is heaviest (dequant overhead) with no FP4 acceleration.
- **NVFP4's FP4 advantage materializes only in prefill** (10 s vs 15–20 s); decode advantages come from head design, not file size.

### 3️⃣ MTP parameter sweep (cross-validated on all three models)

| Config | NVFP4-LOW | IQ3_S | UD-Q4_K_S | Verdict |
|---|---|---|---|---|
| **n-max 3** | **74.4** | **63.2** | **59.3** | 🏆 Best for all three |
| n-max 2 | 66.7 | 61.0 | 54.7 | 7–10% slower |
| n-max 4 | launch crash (short 594 MiB) | 63.5 (no gain) | untested | Unusable / no gain |
| n-max 3 + p-min 0.75 | 64.6 (acceptance inflated to 85%) | — | — | Throughput −13% |

> Key insight: **n-max 4 needs ~594 MiB extra VRAM** for its verification batch — unusable at the edge of a 24GB card, and useless even when it fits.

### 4️⃣ Quality: a three-way tie

**Same-prompt duel** (single-file Snake game, 5 explicit requirements):

| Dimension | IQ3_S | NVFP4-MID-HIGH | UD-Q4_K_S |
|---|---|---|---|
| Complete / all requirements / anti-reverse / food placement | ✅ | ✅ | ✅ |
| **Tail exclusion** (advanced detail) | ✗ | ✗ | **✅ only one** |
| Output length | 3,985 chars | 5,624 chars | 4,164 chars |
| Long-context recall (12K/70% and 150K/80% depth) | ✅ | ✅ | ✅ |

### 5️⃣ Thermal stress: 12 minutes sustained, zero decay

![Thermal stress](assets/chart3-thermal-stress.svg)

| Metric | Round 1 | Round 100 |
|---|---|---|
| Generation speed | 78.7 tok/s | **83.7 tok/s (no decay)** |
| GPU temp | 55 °C | 77 °C (stable plateau) |
| Power | 132 W | 145 W |
| SM clock | 1830 MHz | 1740 MHz (−5%) |

**Conclusion: laptop thermals easily handle sustained agent workloads.** Speed variance (±10%) tracks MTP acceptance randomness, not temperature.

---

## 👁 Vision Support (added 2026-09-11)

The model is a VLM; the vision component (mmproj) ships separately and can be **quantized to save VRAM**:

| Step | Command / Result |
|---|---|
| Get | `mmproj-BF16.gguf` (888 MB, from the HF Qwen3.8-27B repo) |
| **Self-quantize** | `llama-quantize mmproj-BF16.gguf mmproj-Q8_0.gguf Q8_0` → **600 MB** (recognition quality identical in testing) |

**★ Vision mode speed-vs-context curve** (non-linear cliff — note the last row):

| Context | Generation | Vision latency | Verdict |
|---|---|---|---|
| 192K | 3.9 tok/s | 47 s | ❌ |
| 160K + `--ctx-checkpoints 4` | 37.2 tok/s | — | ❌ |
| 154K | 54.4 tok/s | — | ⚠️ |
| 152K | 63.6 tok/s | — | ⚠️ cliff onset |
| **180K + `--ctx-checkpoints 4` + `-np 1`** | **80~87 tok/s** | **4.2 s** | ✅ **recommended (new ceiling)** |
| 148K | 80.4 tok/s | — | ✅ |

> **Major correction (2026-09-13)**: the earlier "152K/160K collapse" was an artifact of the old config (default -np 4, only 158MB free). Re-measured with the production config (`-np 1`, 1.2GB+ free): **150K~180K is flat** (80~87 tok/s); only 192K collapses (63). **Recommended: 180K with vision** (531MB free, vision 4.2s); 192K for text-only.
> Full guide + API example: [docs/vision-setup.md](docs/vision-setup.md)

## 🧠 Reasoning Effort & Budget (added 2026-09-11)

**The default `xhigh` level is a trap in API usage** (measured: zero content output; 22,021 chars of thinking burned through the 6,000-token cap):

| Config | Time | Thinking | Content | Verdict |
|---|---|---|---|---|
| xhigh, no budget | 114 s | 22,021 chars | **0** | ❌ |
| xhigh + **top-level** budget 3000 | 103 s | 10,059 | 6,386 | ✅ |
| xhigh + budget inside template kwargs | 117 s | 22,207 | 0 | ❌ silently ignored |
| **medium** | **37 s** | 826 | 4,274 | ✅ recommended |
| low | 27 s | 692 | — | ✅ fastest |

**★ Key gotcha**: `reasoning_budget_tokens` must be a **top-level request field** — putting it inside `chat_template_kwargs` is silently ignored.
> Full guide: [docs/reasoning-guide.md](docs/reasoning-guide.md)

## 🔬 Deep Verification: iMatrix & Custom Build (added 2026-09-12)

**① iMatrix mixed quant (15.95 GiB) is not worth switching to** — same-task code duel: quality tied (8/9 vs 8/9), but 27% slower generation, 48K less context, 1.5 GiB larger. **PPL advantage ≠ real-task quality advantage.**

**② Custom build exposed AND fixed an upstream MTP bug** — self-compiled with nvcc 12.8 + MSVC (an unsupported pairing), `--spec-type draft-mtp` made prefill ~57× slower; switching to the officially-supported pairing (**CUDA 13.3.33 + MSVC 19.44**) fixed it completely — now the fastest build of all (prefill **1675.7** / decode **75.3~88.7** / vision **4.5s**). Upstream issue: **[#28790](https://github.com/ggml-org/llama.cpp/issues/28790)** (full DLL-swap bisection included).

![Build comparison](assets/chart7-build-comparison.svg)

**③ Engine upgrade intel** — official b10917 ≈ b10889; the **self-compiled build (CUDA 13.3 official pairing) is fully validated** and now used as the daily driver. Reproducible recipe (toolchain red line + 4 pitfalls): [docs/windows-self-build-recipe.md](docs/windows-self-build-recipe.md).

**④ Parameter scoreboard**: `--ctx-checkpoints 4` ✅ (+79%) | `--spec-default` ❌ (−39%) | `n-max 8` ❌.

**⑤ xhigh overthinking fix (measured)** — one system-prompt line cuts thinking by **46%** and restores normal content output; `presence_penalty` / 148K / froggeric template all measured ineffective. See **[docs/xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md)**.

![Micro tuning](assets/chart6-micro-tuning.svg)

> Full custom-build log: [docs/custom-build-and-mtp-bug.md](docs/custom-build-and-mtp-bug.md) | Reproducible recipe: [docs/windows-self-build-recipe.md](docs/windows-self-build-recipe.md) | Raw data: [data/round2-new-results.md](data/round2-new-results.md)

---

## 🔍 Selection Funnel: 53 → 1

![Selection funnel](assets/chart4-selection-funnel.svg)

| Stage | Count | Notes |
|---|---|---|
| Ecosystem survey | **53** | 8 source families (esatapedico NVFP4 9+2+8+10 tiers, unsloth UD 20, DASLab GSQ-RCO 3, QUASAR, …) |
| Hard-constraint filter | ~15 | Removed: too large (ORIG 33GB / HIGHEST 23GB / Q8), experimental patches (8 SSMFIX), third-party fused weights (10 TURBO-Fable), no MTP head (BUDGET), too low precision (IQ1/IQ2) |
| Benchmarked finalists | 4 | IQ3_S · NVFP4-MID-HIGH · NVFP4-LOW · UD-Q4_K_S |
| Deep duel | 3 | IQ3_S · NVFP4-LOW · UD-Q4_K_S |
| **Winner** | **1** | **NVFP4-MTP-LOW** |

**Two notable exclusions** (they look prominent on HF):
- **SSMFIX series**: a community patch rescaling 8 late-layer SSM conv1d weights (hypothesis: fixing long-context degradation). Mixed evidence (TruthfulQA +6~8 pp but CMMLU −1.8, no long-context validation); the card itself says "EXPERIMENT, NOT AN IMPROVEMENT".
- **TURBO-Fable-Cold-Fusion series**: third-party fused tunes (decensored, thinking-reduced), non-official weights, self-reported benchmarks.

---

## ⚙️ Eight Reusable Lessons

1. **`reasoning_effort` is mandatory** — the default (xhigh) burned 8,000 tokens of pure thinking with zero output. Pass `{"chat_template_kwargs":{"reasoning_effort":"medium"}}`. A community 4,800-task test: xhigh burns 7–11× more tokens than low for 0–4.7 points. **Never disable reasoning** (NVFP4 collapses to 13/30 on HumanEval+ with reasoning off).
2. **q4_0-class KV seemed to have a performance cliff** — *later corrected*: the 28× slowdown was a **mixed-type** (`K=q8_0 + V=q4_0`) artifact. Full q4_0 is the fastest configuration at 256K.
3. **MTP is pure win on dense models** — n-max 3 gives +73~79% (the "MTP slows MoE down" experience doesn't apply).
4. **High acceptance ≠ high speed** — speed = per-pass cost × per-pass yield; light heads beat high acceptance.
5. **NVFP4's FP4 acceleration only shows in prefill** — decode is bandwidth-bound and depends on head design.
6. **Engine gains are quantization-dependent** — re-measure capacity after upgrading (NVFP4 +48K, K-quant degrades).
7. **Large contexts are unfriendly to K-quants** — LOW's prefill stays 9.7 s at 200K; UD degrades 15.2 → 19.9 s.
8. **Prompt cache is the biggest free speedup** — same 15.6K input: 15 s cold → **2.3 s warm (6.5×)**. Keep the agent conversation prefix stable.

---

## 🛠 Toolbox

Three PowerShell launchers in `scripts/` (paths parameterized; **save as UTF-8 with BOM**):

| Script | Purpose | Key flags |
|---|---|---|
| `start-nvfp4-low.ps1` | 🏆 Daily driver | `-c 192000` + q8_0 KV + MTP n-max 3 |
| `start-iq3s.ps1` | Ultra-long-context backup | `-c 212000` (up to 240K) |
| `start-nvfp4-midhigh.ps1` | Comparison group | `-c 84000` |

**Edit the two variables at the top before use**: `$ENGINE_DIR` (llama.cpp folder), `$MODELS_DIR` (model folder).

> ⚠️ Two known pitfalls (already handled in the scripts):
> 1. **Scripts must be UTF-8 with BOM** — otherwise PowerShell 5.1 mis-decodes Chinese comments and throws a "string terminator missing" error.
> 2. **b10889+ removed `--no-mmap`** — use `--load-mode none` instead.

**API requirement (all configs)**:
```json
{ "messages": [], "chat_template_kwargs": { "reasoning_effort": "medium" } }
```
Thinking sampling `temp 1.0 / top_p 0.95 / top_k 20`; instruct sampling `temp 0.7 / top_p 0.80 / top_k 20`.

---

## ❓ FAQ

**Q: Why not the full 256K (the model's native maximum)?**
A: With **q4_0 KV** (full q4_0, not mixed) it is the fastest configuration we measured at 256K — 87–91 tok/s with lossless recall. *Note: an earlier "28× slower" claim came from a mixed `K=q8_0 + V=q4_0` setup and does not apply to full q4_0.*

**Q: Does q8_0 KV hurt quality?**
A: Measured and widely reported as near-lossless. Our long-context recall tests (12K/70% and 150K/80% depth) all passed with q8_0 KV.

**Q: Why not Q6/Q8 quants for higher accuracy?**
A: They don't fit 24GB (Q8_0 is 27 GiB). 4-bit is the quality ceiling for this hardware class — community controlled testing shows 4-bit statistically ties FP8 at task level.

**Q: LOW's heads (Q5_0 / IQ4_XS) are lower precision than MID-HIGH's (all Q8_0). Is quality really equal?**
A: Author's PPL: LOW 3.2761 / MEDIUM 3.2858 / MID-HIGH 3.2903 (within error bars; LOW slightly better). Code duel: three-way tie. Head precision affects PPL far less than the backbone.

**Q: How much faster is a desktop 5090?**
A: The 145 W power ceiling here is laptop-specific; a desktop 5090 (575 W) is typically 2–3× faster at prefill and 1.5–2× at decode. **Capacity conclusions (KV quantization, context ceilings) transfer directly.**

**Q: What about 16GB cards?**
A: Use a smaller tier (e.g. NVFP4 COMPACT-LOW 15.2 GB, or the MTP-less BUDGET/STARVED at 14.6 GB), q8_0 KV, context capped near 96K; or IQ3_S (11.3 GB) with more context.

**Q: Does it support image input?**
A: Yes (native VLM). Download `mmproj-BF16.gguf` (~0.87 GB) and pass `--mmproj`; it costs about 1 GB extra VRAM.

**Q: Can I run multiple instances?**
A: 24GB won't hold two 27B instances. Switch configs instead (~30 s, three launchers provided).

**Q: Why llama.cpp instead of vLLM / SGLang?**
A: On Blackwell laptops, their VRAM management and GGUF quantization ecosystem are less flexible, and community NVFP4 weights ship mainly as GGUF. vLLM suits server-side multi-concurrency.

---

## 📚 References & Further Reading

**Models & quants**
- [Qwen/Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B) — base model (Apache-2.0)
- [esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF](https://huggingface.co/esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF) — the winning model's family (9 tiers)
- [unsloth/Qwen3.8-27B-GGUF](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) — UD dynamic quant family
- DASLab GSQ-RCO — search HuggingFace for `DASLab Qwen3.8-27B GSQ-RCO`

**Engine**
- [llama.cpp releases](https://github.com/ggml-org/llama.cpp/releases) — grab both the Windows CUDA main package and the cudart package, unzip into one folder
- MTP support: add `--spec-type draft-mtp`

**Related project**
- [Qwen3.8-Flash-Next 177B deployment log](https://github.com/lifeidle/qwen3.8-flash-next-5090-laptop-256k) — MoE deployment on the same platform (three-tier memory split, 256K context)

---

## 🔧 Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Exits immediately, empty log | Incompatible flag. Newer builds removed `--no-mmap` — use `--load-mode none` |
| `failed to allocate buffer for kv cache` | Context exceeds VRAM. Lower `-c` or use q8_0 KV |
| Launches but inference hangs | VRAM too tight (<200 MiB free). Reduce context by 8–16K |
| Output is all thinking, no answer | Missing `reasoning_effort`; default xhigh burns the budget |
| Script error "string terminator missing" | Save the script as UTF-8 with BOM |
| Mojibake output | Request body not UTF-8 — write a JSON file and `curl --data-binary @file` |

---

## Reproduction

```powershell
# 1. Engine: download the llama.cpp Windows CUDA packages (main + cudart), unzip into one folder
# 2. Model: download the GGUF from the links above (hf-mirror.com works as a mirror)
# 3. Launch: edit the two path variables, then run
.\scripts\start-nvfp4-low.ps1
# 4. Verify
curl http://127.0.0.1:8082/health     # expect {"status":"ok"}
```

**Acceptance baseline**: 256-token generation should reach **75–85 tok/s** (variance from MTP acceptance); a 15.6K-token prompt prefills in ~10 s.

---

## Data Notes

- All speeds are multi-run samples; ±10% variance is normal (MTP acceptance depends on content)
- Capacity figures are measured extremes with successful inference; "launch OK but inference crash" cases are labeled
- Tested September 2026 · RTX 5090 Laptop 24GB · Windows 11 · llama.cpp b10840 / b10889
- Raw thermal data (100 rounds) and all speed data are in [`data/`](./data)

## License & Legal

### This repository

| Content | License |
|---|---|
| Scripts (`scripts/`, `tools/`) | **MIT License** |
| Documentation & data (READMEs, `docs/`, `data/`, charts) | **CC BY 4.0** |

Full terms in [LICENSE](./LICENSE). Free to use, modify and redistribute; please credit this repository when reusing its data or conclusions.

### Third-party components (this repository contains NO model weights)

| Component | License | Source |
|---|---|---|
| Qwen3.8-27B model weights | **Apache 2.0** (commercial use permitted) | [Qwen official](https://huggingface.co/Qwen/Qwen3.8-27B) |
| NVFP4-MTP GGUF (quantized weights) | See its model card | [esatapedico](https://huggingface.co/esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF) |
| llama.cpp | MIT | [ggml-org](https://github.com/ggml-org/llama.cpp) |
| NVIDIA CUDA Toolkit | NVIDIA Software License Agreement | NVIDIA website |

Users must obtain these components from their original sources and comply with their respective licenses.

### Disclaimer

- All performance numbers were measured on a **single device** (RTX 5090 Laptop 24GB + Ultra 9 275HX). Results vary with hardware, drivers and system state.
- All configurations and scripts are provided **"as is"**, without warranty of any kind. Use at your own risk.
- Model output can be inaccurate and **must not be used for medical, legal or financial decisions without human review**.
- You are responsible for complying with the licenses of the model/engine you use and with your local laws and regulations.

### Trademarks

NVIDIA, GeForce, RTX and CUDA are trademarks of NVIDIA Corporation. Qwen is a trademark of Alibaba Group. This is an independent community project, **not affiliated with, endorsed by, or sponsored by** any of these entities.
- Model weights follow upstream licenses (Qwen3.8-27B family is Apache-2.0)

## Acknowledgements

**Alibaba / Qwen team** (base model) · **unsloth** (NVFP4 quantization method, dynamic quant family) · **DASLab** (GSQ-RCO academic quantization) · **esatapedico** (NVFP4-MTP GGUF packaging and transparent model cards) · **llama.cpp community** (engine and MTP support)


---

## 📚 Complete Data & Docs Index

### Raw measurements (`data/`)

| File | Content |
|---|---|
| [final-benchmark.md](data/final-benchmark.md) | **Final config benchmark**: 8-run stability, TTFT curve, vision latency, loaded-context speed |
| [nmax-3-vs-4-comparison.md](data/nmax-3-vs-4-comparison.md) | **MTP draft-depth rigorous comparison** (interleaved design + acceptance rates + statistics) |
| [context-scaling-history.md](data/context-scaling-history.md) | **Full context-scaling history**: 88K → 256K, including three conclusions we had to retract |
| [speed-results.md](data/speed-results.md) | Rounds 1–2: three-way quant duel, MTP sweep, KV experiments |
| [round2-new-results.md](data/round2-new-results.md) | Round 2 supplementary data |
| [round3-6-latest.md](data/round3-6-latest.md) | Rounds 3–6 (thinking control / self-build / context / exhaustive sweep) |
| [thermal-stress-12min-100rounds.txt](data/thermal-stress-12min-100rounds.txt) | Raw 12-minute thermal stress log |

### Technical docs (`docs/`)

| File | Content |
|---|---|
| [context-limits-and-yarn.md](docs/context-limits-and-yarn.md) | **256K ceiling / q4_0 breakthrough / YaRN truth / engine comparison** |
| [windows-self-build-recipe.en.md](docs/windows-self-build-recipe.en.md) | Windows self-build recipe (English; [中文](docs/windows-self-build-recipe.md)) |
| [custom-build-and-mtp-bug.md](docs/custom-build-and-mtp-bug.md) | Self-build pitfalls + MTP prefill bug root-cause |
| [reasoning-guide.md](docs/reasoning-guide.md) | Reasoning depth control (the xhigh token-burn problem) |
| [xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md) | Overthinking fix (system prompt + template injection) |
| [vision-setup.md](docs/vision-setup.md) | Vision setup (mmproj quantization, measured VRAM cost) |
| [ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md) | **Credits and sources** (third-party data attribution) |

### Tools (`tools/`)

Chart generators and measurement harnesses — every number in this repo is reproducible.

### License & legal

- Code: **MIT** | Documentation & data: **CC BY 4.0** — full text in [LICENSE](LICENSE)
- Third-party components (model / engine / CUDA) keep their own licenses: see [docs/ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md)
- **This repository contains no model weights**
