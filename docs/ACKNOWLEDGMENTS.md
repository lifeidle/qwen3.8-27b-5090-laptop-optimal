# Acknowledgments & Sources

> This project stands on other people's work. Every third-party data point, tool and technique we
> relied on is credited here. If you believe something is missing or misattributed, please open an issue.

---

## Models & weights

| Item | Author | Link |
|---|---|---|
| Qwen3.8-27B (base model, Apache 2.0) | Qwen team, Alibaba Group | https://huggingface.co/Qwen/Qwen3.8-27B |
| Qwen3.8-27B-TWIN-TURBO GGUF (current weights, rounds 8-10) | **esatapedico** | https://huggingface.co/esatapedico/Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-GGUF |
| Qwen3.8-27B-NVFP4-MTP-GGUF (rounds 1-8 benchmark family) | **esatapedico** | https://huggingface.co/esatapedico/Qwen3.8-27B-NVFP4-MTP-GGUF |
| Qwen3.8-27B-GSQ-RCO-GGUF (compared in round 1) | ISTA-DASLab | https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF |
| Unsloth Dynamic GGUF family (compared in round 1) | Unsloth | https://huggingface.co/unsloth/Qwen3.8-27B-GGUF |

**This repository contains no model weights.** The GGUF files must be obtained from their original
sources under their own licenses.

## Engine & tooling

| Item | License | Link |
|---|---|---|
| llama.cpp | MIT | https://github.com/ggml-org/llama.cpp |
| NVIDIA CUDA Toolkit | NVIDIA Software License Agreement | https://developer.nvidia.com/cuda-toolkit |
| NVIDIA TensorRT Model Optimizer (NVFP4 recipe) | Apache 2.0 | https://github.com/NVIDIA/TensorRT-Model-Optimizer |

## Techniques and parameters borrowed from the community

| What we used | Source |
|---|---|
| `--override-kv qwen35.context_length=int:N` + `--yarn-orig-ctx` for exceeding 256K | *Qwen3.8-27B-Thor-llama.cpp deployment guide* (CSDN, community write-up) |
| Official YaRN parameter set (`rope_type=yarn, factor=4.0, rope_theta=10000000, partial_rotary_factor=0.25, mrope_*`) | **Qwen / Alibaba Cloud official guide** — *Qwen3.8-27B Practical Guide: Control Reasoning Depth and Extend Context to 1M Tokens* |
| The `-np 1` insight (single slot frees ~1.15 GB → more context) | **PierpaoloPernici**'s public benchmark gist for the same `esatapedico` NVFP4-MTP model |
| Community NVFP4 tier analysis (LOW vs MEDIUM vs VERY-HIGH; "LOW is the throughput winner") | Same gist, plus the `esatapedico` model-card sweep |
| MTP draft-depth guidance ("n-max 3 is optimal for this model") | Libertai Labs release notes (independent NVFP4 quantizer) |
| Unsloth tokenizer `truncation` pitfall (silent 2048-token prompt cut in vLLM) | **NVIDIA Developer Forums** — *Qwen3.8-27B-NVFP4 on a single DGX Spark* thread |
| KV cost reference point (37,169 bytes/token with FP16 KV in vLLM) | Same NVIDIA forum thread (used as a comparison baseline) |

## Upstream issues referenced

| Issue | Subject |
|---|---|
| [ggml-org/llama.cpp #28790](https://github.com/ggml-org/llama.cpp/issues/28790) | MTP prefill 57× slowdown with an nvcc 12.8 + MSVC 19.44 build — **found and reported by us** |
| [ggml-org/llama.cpp #23577](https://github.com/ggml-org/llama.cpp/issues/23577) | Qwen3.x MTP repetitive-output loop in long sessions |
| [Qwen/Qwen3.8-27B discussion #76](https://huggingface.co/Qwen/Qwen3.8-27B/discussions/76) | Community analysis identifying an SSM-layer scale defect behind "reasoning that never stops" |

## Tools used for measurement

- **llama.cpp** `/completion` timings (`prompt_ms`, `predicted_per_second`, `draft_n_accepted`) — all
  numbers in `data/` come from the engine's own instrumentation, not from wall-clock estimates
- **nvidia-smi** for VRAM headroom
- Custom Python harnesses (released under `tools/` and described in each `data/` file)

---

## Disclaimer on third-party data

Numbers quoted from external sources (forums, blog posts, vendor documentation) are **reproduced as
reported by their authors** and were not independently verified by us unless a `data/` file in this
repository shows our own measurement. Where our results contradict an external claim, we say so
explicitly and show our raw runs.

**Trademarks**: NVIDIA, GeForce, RTX and CUDA are trademarks of NVIDIA Corporation. Qwen is a
trademark of Alibaba Group. llama.cpp belongs to its respective contributors. This project is an
independent community effort, **not affiliated with, endorsed by, or sponsored by** any of them.

**License of this repository**: code under MIT, documentation and data under CC BY 4.0 —
see [../LICENSE](../LICENSE).
