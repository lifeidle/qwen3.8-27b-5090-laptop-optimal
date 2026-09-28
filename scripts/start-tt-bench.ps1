# ============================================================
#  Parametrized TWIN-TURBO launcher for benchmark sweeps
#  Usage: start-tt-bench.ps1 <spec-type> <draft-n-max> [tag]
#  Blocks while server runs; caller kills llama-server to stop it.
# ============================================================

param(
    [string]$SpecType = "draft-mtp",
    [int]$DraftMax = 3,
    [string]$Tag = "bench",
    [int]$Ctx = 163840,
    [string]$BinDir = "D:\llama-upstream-b11223"
)

$LLAMA  = $BinDir
$MODEL  = "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf"
$MMPROJ = "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf"
$LOG    = "D:\llama-build\logs\server-bench-$Tag.log"

Set-Location $LLAMA
& "$LLAMA\llama-server.exe" `
    -m $MODEL `
    --mmproj $MMPROJ `
    -ngl 99 `
    -fa on `
    -fit off `
    -c $Ctx `
    -np 1 `
    --ctx-checkpoints 4 `
    --load-mode none `
    --jinja `
    --cache-type-k q8_0 `
    --cache-type-v q8_0 `
    --spec-type $SpecType `
    --spec-draft-n-max $DraftMax `
    --reasoning-effort xhigh `
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 `
    --host 127.0.0.1 --port 8082 `
    *> $LOG
