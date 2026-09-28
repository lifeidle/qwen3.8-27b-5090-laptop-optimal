# ============================================================
#  MTP draft-n-max sweep (single stream, np=1)
#  Configs: d3 (baseline) -> d5 -> d2 -> nospec (-> d7 if d5 wins)
#  Each config: restart server, 2 shots x 384 tok, server timings.
#  Results appended to D:\llama-build\logs\mtp-sweep-results.txt
# ============================================================

$LLAMA  = "D:\llama-custom13"
$MODEL  = "D:\models\esatapedico\Qwen3.8-27B-TWIN-TURBO-Fable-Cold-Fusion-709-L-Uncensored-NVFP4-MID-HIGH.gguf"
$MMPROJ = "D:\models\Qwen3.8-27B-quant-test\mmproj-Q8_0.gguf"
$CTX    = 163840
$PY     = "C:\Users\chenhua\.workbuddy\binaries\python\versions\3.13.12\python.exe"
$BENCH  = "C:\Users\chenhua\Desktop\1\bench_parallel.py"
$RES    = "D:\llama-build\logs\mtp-sweep-results.txt"
$PORT   = 8082

function Kill-Server {
    Stop-Process -Name llama-server -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
}

function Start-Server([string]$SpecType, [int]$DraftMax, [string]$Tag) {
    # Start-Job avoids the PS 5.1 Start-Process bug (duplicate PATH/Path env keys)
    $script:job = Start-Job -ScriptBlock {
        param($spec, $dmax, $tag)
        & "D:\llama-build\repo\scripts\start-tt-bench.ps1" $spec $dmax $tag
    } -ArgumentList $SpecType, $DraftMax, $Tag
    return $script:job
}

function Stop-ServerJob {
    if ($script:job) {
        Stop-Job $script:job -ErrorAction SilentlyContinue
        Remove-Job $script:job -Force -ErrorAction SilentlyContinue
        $script:job = $null
    }
}

function Wait-Healthy([int]$TimeoutSec = 240) {
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

function Run-Bench {
    # returns array of hashtables with server_tok_s per shot
    $shots = @()
    $out = & $PY $BENCH $PORT single 384 2 2>&1
    foreach ($line in $out) {
        if ($line -like "RESULT|*") {
            $j = ($line -replace "^RESULT\|", "") | ConvertFrom-Json
            foreach ($r in $j.requests) {
                $shots += [ordered]@{
                    wall = $r.wall_s
                    toks = $r.completion_tokens
                    stps = $r.server_tok_s
                    ctps = $r.client_tok_s
                }
            }
        }
    }
    return $shots
}

function Test-Config([string]$Tag, [string]$SpecType, [int]$DraftMax) {
    Add-Content $RES "=== CFG $Tag spec=$SpecType draft_n_max=$DraftMax started $(Get-Date -Format HH:mm:ss) ==="
    Kill-Server
    Start-Server $SpecType $DraftMax $Tag | Out-Null
    $ok = Wait-Healthy 240
    if (-not $ok) {
        Add-Content $RES "=== CFG $Tag FAILED (server not healthy) ==="
        Kill-Server
        Stop-ServerJob
        return $null
    }
    $shots = Run-Bench
    $st = $shots | ForEach-Object { $_.stps }
    Add-Content $RES ("CFG {0} shots: {1}" -f $Tag, (($shots | ConvertTo-Json -Compress)))
    Kill-Server
    Stop-ServerJob
    if ($st.Count -ge 2) {
        $steady = [double]$st[1]
        Add-Content $RES ("SUMMARY {0} steady(2nd shot) = {1} tok/s" -f $Tag, $steady)
        return $steady
    } else {
        Add-Content $RES "SUMMARY $Tag insufficient shots"
        return $null
    }
}

# ---- main ----
New-Item -ItemType Directory -Force -Path (Split-Path $RES) | Out-Null
Add-Content $RES "########## MTP sweep started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ##########"

$r3  = Test-Config "d3" "draft-mtp" 3
$r5  = Test-Config "d5" "draft-mtp" 5
$r2  = Test-Config "d2" "draft-mtp" 2
$r0  = Test-Config "nospec" "none" 0

$r7 = $null
if ($r5 -and $r3 -and ($r5 -gt $r3 * 1.03)) {
    Add-Content $RES ">>> d5 beat d3 by >3% - running d7"
    $r7 = Test-Config "d7" "draft-mtp" 7
}

Add-Content $RES "########## MTP sweep done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ##########"
Add-Content $RES ("FINAL d3={0} d5={1} d2={2} nospec={3} d7={4}" -f $r3, $r5, $r2, $r0, $r7)
