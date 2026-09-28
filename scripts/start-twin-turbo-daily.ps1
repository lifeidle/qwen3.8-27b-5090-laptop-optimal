# ============================================================
#  TWIN-TURBO MID-HIGH - Daily Driver (FINAL, 2026-09-28)
#  Model: esatapedico NVFP4 MID-HIGH (15.75 GB) + own MTP heads
#  Engine: official llama.cpp b11223 (CUDA 13.4, CUDA-graph MTP)
#  Measured: 74-78 tok/s decode (vision loaded) | overthinking -93%
#  Context: 160K = max STABLE value (VRAM cliff ~180K, 192K = -25%)
#  MTP: draft-n-max 3 (2 ties, 5 collapses - see data/2026-09-28)
#  NOTE: NO --reasoning-budget, NO --chat-template-file.
#        Model's own mode system conflicts with runtime patches.
# ============================================================

$LLAMA  = "D:\llama-upstream-b11223"
$MODEL  = "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf"
$MMPROJ = "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf"
$CTX    = 163840

Write-Host ""
Write-Host "=== TWIN-TURBO MID-HIGH daily (b11223, d3, 160K) ===" -ForegroundColor Green
Write-Host "  ctx : $CTX  |  KV: q8_0  |  vision: ON  |  MTP: n-max 3"
Write-Host "  measured: 74-78 tok/s | 3.9 s/image | overthinking -93%"
Write-Host ""

if (-not (Test-Path "$LLAMA\llama-server.exe")) { throw "llama-server.exe not found: $LLAMA" }
if (-not (Test-Path $MODEL))  { throw "model not found: $MODEL" }
if (-not (Test-Path $MMPROJ)) { throw "mmproj not found: $MMPROJ" }

Set-Location $LLAMA
& "$LLAMA\llama-server.exe" `
    -m $MODEL `
    --mmproj $MMPROJ `
    -ngl 99 `
    -fa on `
    -fit off `
    -c $CTX `
    -np 1 `
    --ctx-checkpoints 4 `
    --load-mode none `
    --jinja `
    --cache-type-k q8_0 `
    --cache-type-v q8_0 `
    --spec-type draft-mtp `
    --spec-draft-n-max 3 `
    --reasoning-effort xhigh `
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 `
    --host 127.0.0.1 --port 8082
