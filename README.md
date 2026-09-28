# Qwen3.8-27B · 单卡 24GB 极限调优实录

**把 TWIN-TURBO 调到 RTX 5090 Laptop 24GB 上的实际极限 —— 每一个数字都有对照组实测**

[English →](./README_EN.md) ｜ [工具脚本 →](./scripts) ｜ [原始数据 →](./data)

[![Model](https://img.shields.io/badge/model-Qwen3.8--27B%20TWIN--TURBO-7c3aed)](https://huggingface.co/Qwen/Qwen3.8-27B)
[![Platform](https://img.shields.io/badge/platform-RTX%205090%20Laptop%2024GB-76b900)]()
[![Throughput](https://img.shields.io/badge/decode-74~78%20tok%2Fs-d97706)]()
[![Context](https://img.shields.io/badge/context-160K%20max%20stable-2563eb)]()
[![Engine](https://img.shields.io/badge/llama.cpp-b11223%20CUDA%2013.4-0ea5e9)]()
[![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0-059669)](#许可与法律)

---

## 🏆 当前主力（Current Champion — 直接照抄）

![当前主力配置](assets/chart12-champion-stack.svg)

**一行命令启动**（PowerShell 粘贴回车；关闭窗口即停止）：

```powershell
& "D:\llama-upstream-b11223\llama-server.exe" -m "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf" --mmproj "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf" -ngl 99 -fa on -fit off -c 163840 -np 1 --ctx-checkpoints 4 --load-mode none --jinja --cache-type-k q8_0 --cache-type-v q8_0 --spec-type draft-mtp --spec-draft-n-max 3 --reasoning-effort xhigh --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 --host 127.0.0.1 --port 8082
```

### 这套方案解决了什么

| 问题 | 状态 |
|---|---|
| **思考失控 / 过度思考** | ✅ **模型层修复 −93%**（失控 prompt：19,859 → 1,318 字符，31.7 秒给出 6,034 字符正文）——权重里直接训练掉了，不需要任何运行时补丁 |
| **精度** | ✅ **全 Q8_0 链路**（输出头 + MTP 头 + KV cache 全部近无损量化），多轮长对话累积最稳 |
| **长任务续航** | ✅ 12 分钟满载 100 轮**零衰减**（78.7 → 83.7 tok/s，笔记本散热完全扛得住 agent 负载）|
| **视觉** | ✅ 开启，**3.9 秒/张**（自量化的 q8_0 mmproj，质量与 BF16 无差）|
| **速度** | ✅ **74–78 tok/s** 解码（含视觉），MTP 草稿带来 ~1.8× |
| **唯一牺牲：上下文** | ⚠️ **封顶 160K** —— 显存悬崖实测在 ~180K（192K 直接 −25%），这是这台卡上"稳定跑"能换到的最大值 |

> ⚠️ **刻意不用** `--reasoning-budget` 和 `--chat-template-file`：模型自带 10 种模式系统（5 reasoning + 5 instruct，einstein/spoon/xhigh…，聊天中实时切换），旧运行时补丁与它**冲突**（叠加后更慢、思考更多）。
>
> 📦 **需要下载的三件套**：① [esatapedico / TWIN-TURBO-NVFP4-GGUF](https://huggingface.co/esatapedico/Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-GGUF) 选 **MID-HIGH** 档（15.75 GB）· ② [mmproj](https://huggingface.co/Qwen/Qwen3.8-27B)（~0.9 GB，建议自量化成 Q8_0 = 600 MB）· ③ [llama.cpp b11223+ Windows CUDA 包](https://github.com/ggml-org/llama.cpp/releases)（主程序 + cudart 两个 zip）。国内把 `huggingface.co` 换成 `hf-mirror.com`。

---

## 📈 两组关键实测图

**① MTP 草稿深度：3 就是甜点**（2026-09-28 在 b11223 上复验）

![MTP草稿深度](assets/chart13-mtp-depth.svg)

**② 上下文悬崖：160K 是"稳定跑"的最大值**

![上下文悬崖](assets/chart14-ctx-cliff.svg)

- 非溢出区间内 ctx 大小**不影响速度**（152K-176K 全是 74-77 tok/s）
- **168-176K 是"刀锋边缘"**：同一命令不同启动，双峰 74.7 ↔ 55-59（显存 98% 满，是否溢出看碎片运气）——比匀速慢更糟的不可预测
- **184K 起真实掉速**（−12%，复测一致），**192K 起 −25%**（KV 溢出到内存）
- KV 成本实测 **43.97 KiB/token**；160K 的 KV ≈ 6.9 GiB，整卡账本 23.96/24.46 GiB

---

## 🎯 10 秒决策

| 你的场景 | 选择 |
|---|---|
| 日常对话 / 编码 / agent（要视觉） | **上面的一行命令** ✅ |
| 需要灌 20 万+ tokens 大材料 | 备用配置：NVFP4-MTP-LOW + q4_0 KV + 262K（见 [data/context-scaling-history.md](data/context-scaling-history.md)）|
| 两个客户端同时用 | `-np 2`：第一条流无损、第二条 −17%、**总吞吐 +50%**，代价是每槽 80K（见 [data/2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) §4）|
| 真正的 1M 交互 | 32GB+ 显存（vLLM 路线）|
| 思考停不下来 | **TWIN-TURBO 已在模型层修复**（−93%），无需补丁 |

---

## 🔁 复现

```powershell
# 1. 引擎：llama.cpp 官方 Windows CUDA 包（主程序 + cudart 两个 zip 解压到同一目录），b11223 或更新
# 2. 模型：上方三件套（国内 hf-mirror.com 镜像）
# 3. 启动
.\scripts\start-twin-turbo-daily.ps1     # 或 README 顶部的一行命令
# 4. 验证
curl http://127.0.0.1:8082/health        # 期望 {"status":"ok"}
```

**验收基线**：384-token 生成 **74–78 tok/s**（服务端计时；±10% 波动来自 MTP 接受率的内容随机性）；prompt cache 命中后长输入秒级。

**测量纪律**（本项目所有数字的来源规则）：
1. 只读**服务端计时**（response `timings` / slot `print_timing`），不用客户端耗时差
2. 单发是噪声（同配置实测 50.6–79.4 都出现过）→ 结论必须**复测一致**
3. 扫参数必须**倒序复测端点**，排除热漂移假象（本轮"96K 最快 84"即被证伪）
4. 警惕"刀锋边缘"配置：同一配置多次启动出现双峰 → 不可预测 = 不可用

**测速与扫描脚本**：[`scripts/bench-parallel.py`](scripts/bench-parallel.py)（并发基准，读服务端 timings）· [`scripts/bench-mtp-sweep.ps1`](scripts/bench-mtp-sweep.ps1)（自适应扫参）· [`scripts/bench-ctx-fine.ps1`](scripts/bench-ctx-fine.ps1)（带倒序复测的 ctx 扫描）· [`scripts/start-tt-bench.ps1`](scripts/start-tt-bench.ps1)（参数化启动器）

---

## 🗄️ 归档：被否掉的方案（都有实测数据，点开看为什么）

<details>
<summary><b>❌ DFlash2 草稿（2026-09-28 测试）—— 微调模型上接受率仅 4%</b></summary>

官方有 Qwen3.8-27B 配套 DFlash2 草稿（[z-lab GGUF](https://huggingface.co/z-lab/Qwen3.8-27B-DFlash2-GGUF)，llama.cpp 支持 PR [#27342](https://github.com/ggml-org/llama.cpp/pull/27342) 已合并）。实测：Q4_K_M 草稿 + n-max 7 + 160K，**25.2 tok/s（比 MTP 慢 67%），草稿接受率 4%**（2,059 个草稿只中 86）——草稿按官方原版训练，预测不了 TWIN-TURBO 大改微调的分布。MTP 快是因为用微调自带的 nextn 头。**跑官方原版时值得开，微调上别碰。**
</details>

<details>
<summary><b>❌ NVFP4-MTP-LOW（第 1–8 轮旧主力）—— 被 TWIN-TURBO 取代</b></summary>
三方量化对决的速度双冠（79.6 tok/s / 200K），但输出头 Q5_0 + IQ4_XS 精度低于 MID-HIGH 的全 Q8_0，且不带 TWIN-TURBO 的模型层思考修复。完整决策：[data/tturbo-adoption.md](data/tturbo-adoption.md)。262K + q4_0 KV 备用配置保留（见 10 秒决策表）。
</details>

<details>
<summary><b>❌ 192K+ 上下文 —— VRAM 溢出 −25%</b></summary>
184K 起掉 12%、192K 起 −25%、224K 一样。显存 98% 满后 KV 页被换出到内存。168-176K 刀锋双峰。唯一例外：旧 NVFP4-LOW 配置下 192K 曾可用（权重更小），TWIN-TURBO 的 15.75GB 权重让悬崖前移。
</details>

<details>
<summary><b>❌ 运行时思考补丁（reasoning-budget + 模板注入）—— 与模型自带模式系统冲突</b></summary>
TWIN-TURBO 在权重层把过度思考训练掉了（−93%），旧双保险叠加后反而更慢、思考更多 → 退役。历史修复思路（对未微调模型仍有效）：[docs/xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md)、[docs/reasoning-guide.md](docs/reasoning-guide.md)
</details>

<details>
<summary><b>❌ 53 → 1 量化筛选中被排除的（IQ3_S / UD-Q4_K_S / SSMFIX / iMatrix 等）</b></summary>
筛选漏斗与排除理由：<a href="#-筛选过程-53--1">原第 8 轮前记录</a> · iMatrix 混合量化（−27% 速度）：[data/round2-new-results.md](data/round2-new-results.md) · YaRN 1M（4-5 tok/s）与 262K 硬上限：[docs/context-limits-and-yarn.md](docs/context-limits-and-yarn.md)
</details>

## 📜 十轮调优历程

| 轮次 | 主题 | 关键收获 |
|---|---|---|
| 1 | **量化选型**（53 → 1）| NVFP4-LOW 胜出（速度双冠、质量打平）|
| 2 | **KV + MTP 调优** | MTP n-max 3（生成 +40%）|
| 3 | **思考控制** | xhigh 修复：`--reasoning-budget` + 模板注入 |
| 4 | **自编译引擎** | CUDA 13.3 官方配对：prefill +13% · 修复上游 bug（[#28790](https://github.com/ggml-org/llama.cpp/issues/28790)）|
| 5 | **上下文修正** | `-np 1` 释放显存，150K → 180K |
| 6 | **穷尽复查** | 40+ 参数全排查 |
| 7 | **上下文真相** | q4_0 KV 让 256K 可用 · 静默封顶与 YaRN 真相 |
| 8 | **模型换代** | **TWIN-TURBO MID-HIGH 转正**：思考 −93%、全 Q8_0、补丁退役 |
| 9 | **引擎刷新（09-28）** | **官方 b11146/b11223 CUDA 13.4**：MTP 草稿启用 CUDA 图（PR #28790 后又一白捡）——峰值持平、**下限抬升**（不再有 58-68 的谜之低谷）|
| 10 | **终局微调（09-28）** | MTP 深度复验（3 仍最优）· **DFlash2 否决**（接受率 4%）· 双流 +50% · **上下文悬崖测绘**：160K 定稿 |

---

## ❓ FAQ

**Q：为什么不直接开 256K（模型原生最大）？**
A：这台卡上 24GB 装不下 256K 的 KV 还保持速度——192K 就开始溢出（−25%）。160K 是"稳定跑"能换到的最大值。要灌 26 万 token 大材料用备用配置（q4_0 KV 的 NVFP4-MTP-LOW，见 10 秒决策）。

**Q：q8_0 KV 损失质量吗？**
A：近无损。长文召回测试（12K/70% 与 150K/80% 深度）全部通过。

**Q：为什么不用 vLLM / SGLang？**
A：Blackwell Laptop 上它们的显存管理与 GGUF 生态不如 llama.cpp 灵活，NVFP4 权重主要以 GGUF 分发。SGLang/vLLM 是 DFlash2 等"官方模型 + 服务端栈"组合的主场。

**Q：桌面版 5090 会快多少？**
A：prefill 快 2–3 倍、decode 快 1.5–2 倍（575W vs 145W）。**容量结论（KV 量化、悬崖位置随权重体积平移）可参考方法自行复测。**

**Q：16GB 卡怎么办？**
A：小档模型 + q8_0 KV + ~96K 上下文；或 IQ3_S（11.3GB）换容量。

**Q：可以同时跑多个实例吗？**
A：装不下两个 27B。同实例内 `-np 2` 是正解（总吞吐 +50%）。

**Q：模型支持图像吗？**
A：原生 VLM。`--mmproj` 加载（建议自量化 Q8_0 = 600 MB），额外 ~1GB 显存。**注意：视觉组件也占显存，是 ctx 悬崖的一部分。**

---

## 🔧 故障排查

| 症状 | 原因与解法 |
|---|---|
| 启动即退出、日志无内容 | 参数不兼容。新版引擎已移除 `--no-mmap`，用 `--load-mode none` |
| `failed to allocate buffer for kv cache` | 上下文超出显存。降 `-c` |
| 启动成功但推理卡死 | 显存贴边（余量 <200 MiB）。降 8–16K 上下文 |
| 同配置忽快忽慢（差 20%+） | 显存 98% 满的刀锋边缘。降 ctx 到有余量的档位 |
| 生成全是思考、没有正文 | 未传 `reasoning_effort`；默认 xhigh 会烧光 token |
| 输出乱码 | 请求体未按 UTF-8 编码（写 JSON 文件 + `curl --data-binary @file`）|

---

## 📚 完整数据与文档索引（归档区）

### 历史记录（`data/`）

| 文件 | 内容 |
|---|---|
| [2026-09-28-final-stack-tuning.md](data/2026-09-28-final-stack-tuning.md) | **第 9-10 轮**：引擎刷新 / MTP 复验 / DFlash2 / 双流 / 上下文悬崖 |
| [tturbo-adoption.md](data/tturbo-adoption.md) | **第 8 轮**：换模决策（NInfer / Bonsai 为什么落选）|
| [nmax-3-vs-4-comparison.md](data/nmax-3-vs-4-comparison.md) | MTP 深度严格对比（交叉设计）|
| [context-scaling-history.md](data/context-scaling-history.md) | 上下文探索全史：88K → 256K |
| [final-benchmark.md](data/final-benchmark.md) | 最终配置基准（8 轮稳定性 / TTFT / 视觉）|
| [speed-results.md](data/speed-results.md) ｜ [round2-new-results.md](data/round2-new-results.md) ｜ [round3-6-latest.md](data/round3-6-latest.md) | 第 1–6 轮原始数据 |
| [thermal-stress-12min-100rounds.txt](data/thermal-stress-12min-100rounds.txt) | 12 分钟满载散热原始日志 |

### 技术文档（`docs/`）

| 文件 | 内容 |
|---|---|
| [context-limits-and-yarn.md](docs/context-limits-and-yarn.md) | 262K 硬上限 / q4_0 / YaRN 真相 |
| [windows-self-build-recipe.md](docs/windows-self-build-recipe.md)（[EN](docs/windows-self-build-recipe.en.md)）| 自编译配方（现用官方预编译，此配方保留备用）|
| [custom-build-and-mtp-bug.md](docs/custom-build-and-mtp-bug.md) | 自编译四坑 + MTP prefill bug 定位 |
| [reasoning-guide.md](docs/reasoning-guide.md) ｜ [xhigh-overthinking-fix.md](docs/xhigh-overthinking-fix.md) | 思考控制（对未微调模型仍有效）|
| [vision-setup.md](docs/vision-setup.md) | 视觉配置与 mmproj 自量化 |
| [ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md) | 致谢与引用来源 |

### 历史图表（`assets/`）

chart1-chart11（速度对决 / 上下文容量 / 散热 / 筛选漏斗 / 构建对比 / 参数红黑榜等）保留在 [assets/](./assets)，生成脚本在 [tools/](./tools)。

---

## 许可与法律

| 内容 | 许可 |
|---|---|
| 脚本代码（`scripts/`、`tools/`）| **MIT License** |
| 文档与数据（README、`docs/`、`data/`、图表）| **CC BY 4.0** |

第三方：Qwen3.8-27B 权重 **Apache 2.0**（[Qwen 官方](https://huggingface.co/Qwen/Qwen3.8-27B)）· TWIN-TURBO GGUF 见其模型卡（[esatapedico](https://huggingface.co/esatapedico)）· llama.cpp **MIT** · CUDA 按 NVIDIA 许可。**本仓库不含任何模型权重**，使用者自行从原始来源获取。免责与商标声明见 [LICENSE](LICENSE) 与 [docs/ACKNOWLEDGMENTS.md](docs/ACKNOWLEDGMENTS.md)。

## 致谢

**Alibaba / Qwen 团队**（基座）· **DavidAU**（TWIN-TURBO 思考修复调教）· **esatapedico**（NVFP4 GGUF 家族）· **unsloth / DASLab**（量化方法）· **llama.cpp 社区**（引擎、MTP、CUDA graphs）· **z-lab / NVIDIA**（DFlash2 —— 虽然在本项目被否，但方法本身值得尊敬）
