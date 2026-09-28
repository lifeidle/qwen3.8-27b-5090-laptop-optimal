# ============================================================
#  FINE ctx sweep around 160K (b11223 + MTP d3, np=1)
#  Pass 1 (ascending): 152K / 160K / 168K / 176K / 184K
#  Pass 2 (drift check, descending): 184K / 152K
#  Results: D:\llama-build\logs\ctx-fine-results.txt
# ============================================================

$PY     = "C:\Users\chenhua\.workbuddy\binaries\python\versions\3.13.12\python.exe"
$BENCH  = "C:\Users\chenhua\Desktop\1\bench_parallel.py"
$RES    = "D:\llama-build\logs\ctx-fine-results.txt"
$PORT   = 8082
$BINDIR = "D:\llama-upstream-b11223"

function Kill-Server {
    Stop-Process -Name llama-server -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

function Start-Server([int]$CtxSize, [string]$Tag) {
    $script:job = Start-Job -ScriptBlock {
        param($c, $t, $b)
        & "D:\llama-build\repo\scripts\start-tt-bench.ps1" -SpecType draft-mtp -DraftMax 3 -Tag $t -Ctx $c -BinDir $b
    } -ArgumentList $CtxSize, $Tag, $BINDIR
}

function Stop-ServerJob {
    if ($script:job) {
        Stop-Job $script:job -ErrorAction SilentlyContinue
        Remove-Job $script:job -Force -ErrorAction SilentlyContinue
        $script:job = $null
    }
}

function Wait-Healthy([int]$TimeoutSec = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 4
        try {
            $h = Invoke-RestMethod "http://127.0.0.1:$PORT/health" -TimeoutSec 3
            if ($h.status -eq "ok") { return $true }
        } catch {}
    }
    return $false
}

function Read-VRAM {
    try {
        return (& nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader 2>$null)
    } catch { return "n/a" }
}

function Test-Ctx([int]$CtxSize, [string]$Tag) {
    Add-Content $RES "=== CFG ctx=$CtxSize ($Tag) started $(Get-Date -Format HH:mm:ss) ==="
    Kill-Server
    Start-Server $CtxSize $Tag
    $ok = Wait-Healthy 180
    if (-not $ok) {
        Add-Content $RES "=== CFG ctx=$CtxSize FAILED (not healthy in 180s) ==="
        Kill-Server
        Stop-ServerJob
        return $null
    }
    Add-Content $RES "VRAM after load: $(Read-VRAM)"
    $shots = @()
    $out = & $PY $BENCH $PORT single 384 2 2>&1
    foreach ($line in $out) {
        if ($line -like "RESULT|*") {
            $j = ($line -replace "^RESULT\|", "") | ConvertFrom-Json
            foreach ($rq in $j.requests) {
                $shots += [double]$rq.server_tok_s
            }
        }
    }
    Kill-Server
    Stop-ServerJob
    if ($shots.Count -ge 2) {
        $steady = $shots[1]
        Add-Content $RES ("SUMMARY ctx={0} [{1}] shots=[{2}] steady={3}" -f $CtxSize, $Tag, ($shots -join ","), $steady)
        return $steady
    } else {
        Add-Content $RES "SUMMARY ctx=$CtxSize [$Tag] insufficient shots"
        return $null
    }
}

# ---- main ----
New-Item -ItemType Directory -Force -Path (Split-Path $RES) | Out-Null
Add-Content $RES "########## FINE ctx sweep (b11223 + MTP d3, np=1) started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ##########"

$r152a = Test-Ctx 155648 "p1"
$r160a = Test-Ctx 163840 "p1"
$r168a = Test-Ctx 172032 "p1"
$r176a = Test-Ctx 180224 "p1"
$r184a = Test-Ctx 188416 "p1"
# pass 2: drift check, descending
$r184b = Test-Ctx 188416 "p2"
$r152b = Test-Ctx 155648 "p2"

Add-Content $RES "########## FINE ctx sweep done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ##########"
Add-Content $RES ("FINAL p1: 152k={0} 160k={1} 168k={2} 176k={3} 184k={4}" -f $r152a, $r160a, $r168a, $r176a, $r184a)
Add-Content $RES ("FINAL p2 drift-check: 184k={0} 152k={1}" -f $r184b, $r152b)
