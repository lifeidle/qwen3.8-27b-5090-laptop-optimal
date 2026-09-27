# Model Switch: NVFP4-MTP-LOW → TWIN-TURBO MID-HIGH (2026-09-27)

> The complete decision record: what triggered the switch, what we tested, what the numbers said,
> and why the old default was retired. Everything below is from our own measurements on the same
> RTX 5090 Laptop 24 GB, same self-built CUDA 13.3 engine, same test prompts.

---

## 1. The trigger: overthinking at xhigh

Our long-standing pain point: the official Qwen3.8-27B at `--reasoning-effort xhigh` **routinely fell
into thinking loops** — the same runaway prompt burned 93 s, produced **19,859 chars of reasoning**,
hit the token cap (`finish=length`) and emitted **zero answer**.

We had shipped a runtime double-fuse against it (`--reasoning-budget 12000` + a patched chat
template with a one-line system instruction), which reduced thinking by 46% — a patch, not a cure.

## 2. The candidates we evaluated

| Candidate | Verdict | Reason |
|---|---|---|
| **NInfer** (`neroued/Qwen3.8-27B-nvfp4-NInfer`) | ❌ not now | 1.76–1.8× faster on paper, but **Linux-only**, source-build, proprietary `.ninfer` format |
| **Bonsai 2 27B** (ternary, `prism-ml`) | ❌ not now | Genuine 1.72 bpw at 98.2% quality is impressive, but **needs a llama.cpp fork**, RTX 5090 **desktop** = 129.9 tok/s → our laptop (half the bandwidth) ≈ 65–90 = **no speed gain**, and MTP support unconfirmed |
| **DavidAU TURBO (gen 1)** | superseded | thinking −50~90%; TWIN-TURBO (gen 2) doubles that |
| **DavidAU TWIN-TURBO (gen 2)** ✅ | **ADOPTED** | thinking tokens **−93% measured**, ARC-C 709, 10 switchable modes, same hybrid architecture (our 262K/q4_0/MTP know-how carries over) |

## 3. What we measured (TWIN-TURBO MID-HIGH, NVFP4 tier, 15.75 GB)

### Context sweep with q8_0 KV (the crash point)

| Context | decode | TTFT | VRAM free | Status |
|---|---|---|---|---|
| 128K | 78.1 | 188 ms | 2944 MB | ✅ |
| **160K** | **79.8** | 167–368 ms | 1566 MB | ✅ **sweet spot** |
| 192K | 61.3 | 141–382 ms | 492 MB | ⚠ mid zone |
| 224K | 58.6 | 170–372 ms | 585 MB | ⚠ mid zone |
| 256K | **9.1** | 742–1180 ms | 607 MB | ❌ **collapse** |
| 262K | 5.7 | 1076–1421 ms | 358 MB | ❌ collapse |

**q8_0 KV has a hard cliff between 224K and 256K** (58.6 → 9.1 tok/s, TTFT also degrades).
q4_0 KV does not collapse at 262K (87–91 tok/s) because its footprint is half — that is why the
**262K max-context** role keeps q4_0.

### The overthinking test (same runaway prompt: LRU cache, xhigh, max_tokens 6000)

| Config | Time | finish | Thinking chars | Content |
|---|---|---|---|---|
| official model, no control | 93 s | length ❌ | 19,859 | **0** ❌ |
| official + system prompt (our patch) | 50 s | stop | 10,708 (−46%) | 1,286 |
| official + template injection | 77 s | stop | 18,499 | 1,180 |
| **TWIN-TURBO, own template, no budget** | **31.7 s** | **stop** ✅ | **1,318 (−93%)** 🎉 | **6,034** ✅ |
| TWIN-TURBO + our double fuse | 42.0 s | stop | 4,197 | 3,814 |

**Three findings**:
1. **−93% thinking** (1/15) — inside DavidAU's claimed 1/2~1/20 range, **claim verified**
2. **Output flipped from 0 → 6,034 chars** of a complete LRU implementation, finished naturally, 3× faster
3. **⚠ Our double fuse HURTS this model** (42 s / 4,197 vs 31.7 s / 1,318): DavidAU's template ships
   its own mode system (einstein/spoon/xhigh…) and our runtime patches conflict with it.
   **Model-layer fix > runtime patch — the patch is retired in the new default.**

### Vision on top (mmproj-Q8_0, original projector)

| Metric | Result |
|---|---|
| decode (text) | 74.2 tok/s (−7% vs vision-off) |
| Vision | 3.9 s median (2/3 correct; first-run miss = cold start) |
| VRAM free | 442 MB idle / 403 MB after — tight but stable; fallback: context 160K → 144K |

## 4. Why we retired the old default

| Consideration | NVFP4-MTP-LOW (old) | TWIN-TURBO MID-HIGH (new) |
|---|---|---|
| Overthinking at xhigh | required runtime patches, still −46% only | **−93% at the model level**, patch retired |
| Heads precision | Q5_0 / IQ4_XS | **Q8_0 across all three head groups** — best for multi-round accumulation |
| KV quality | q4_0 (forced: q8_0 collapses at 262K) | **q8_0** (no collapse at 160K) |
| Context | **262K** | 160K (−40%) — the one real cost |
| Decode | 81.8 tok/s | 79.8 (vision off) / 74.2 (vision on) |

The only thing the old config wins is raw context (262K vs 160K) — and it wins it by using a
half-precision KV that collapses q8_0, plus lighter heads. For **multi-round development**
(our primary workload) the new config wins on every quality axis at essentially the same speed.
The old config remains documented as the **max-context fallback** (262K) for "load a huge corpus"
sessions.

## 5. New daily-driver command

```powershell
& "D:\llama-custom13\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --ctx-checkpoints 4 --load-mode none --jinja --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082
```

**Deliberately absent**: `--reasoning-budget` and `--chat-template-file` — the model's own mode
system replaces both. `--mmproj` is optional (text-only saves ~1 GB VRAM).

**Also note**: mid-session mode switching (5 reasoning + 5 instruct modes, incl. zero-thinking
instruct modes) is built into the model's template — switchable per message in chat.

## 6. Retired artifacts

The old launch scripts (`start-nvfp4-low.ps1`, `start-nvfp4-midhigh.ps1`, `start-iq3s.ps1`) were
removed from this repo in the same commit that added `start-twin-turbo-midhigh.ps1`. The historical
data files under `data/` and `docs/` are **retained as the decision record** — they document how the
earlier conclusions were reached and why three of them were later corrected.
