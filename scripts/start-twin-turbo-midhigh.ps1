# ============================================================
#  TWIN-TURBO MID-HIGH - Daily Driver (multi-round dev, vision ON)
#  Model: esatapedico NVFP4 MID-HIGH tier (heads all Q8_0)
#  KV: q8_0 | Context: 160K (q8_0 crash point is 224K-256K, 10% margin)
#  Measured: decode 74.2 tok/s (vision loaded) | overthinking -93%
#  NOTE: NO --reasoning-budget, NO --chat-template-file.
#        The model ships DavidAU's own mode system (einstein/spoon/xhigh...)
#        and our old runtime patches CONFLICT with it. Let it breathe.
# ============================================================

$LLAMA  = "D:\llama-custom13"
$MODEL  = "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf"
$MMPROJ = "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf"   # original Qwen3.8 projector
$CTX    = 163840    # 160K - the q8_0 sweet spot (256K+ collapses to ~9 tok/s)

Write-Host ""
Write-Host "=== TWIN-TURBO MID-HIGH (daily driver) ===" -ForegroundColor Green
Write-Host "  ctx : $CTX  |  KV: q8_0  |  vision: ON  |  MTP: n-max 3"
Write-Host "  measured: 74.2 tok/s decode | 3.9 s/image | overthinking -93%"
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
