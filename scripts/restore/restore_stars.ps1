# GitHub Stars 恢复脚本 - 完整性优先版
# 用法: powershell -ExecutionPolicy Bypass -File restore_stars.ps1 "ghp_xxx"
# 原则: 完整性 > 速度，慢但必须全部完成，中途断开可续传

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [int]$DelayMs = 3000    # 每次请求间隔3秒，保守策略
)

$ErrorActionPreference = "Continue"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "GitHub-Stars-Restore/1.0 (completeness-first)"
}

# ====== 路径 ======
$scriptDir = Split-Path $PSScriptRoot            # scripts/restore
$projectDir = Split-Path $scriptDir               # github-backup-tool 根目录
$dataDir = Join-Path $projectDir "data"

# ====== 日志 ======
function Log($msg, $color) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $msg"
    $line | Out-File $LogFile -Append -Encoding UTF8
    if ($color) { Write-Host $line -ForegroundColor $color }
    else { Write-Host $line }
}

# ====== 识别账号 ======
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Stars Restorer (完整性优先)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
$username = $me.login

$LogFile = Join-Path $projectDir "restore_stars_${username}.log"
$StateFile = Join-Path $projectDir "restore_stars_${username}.state"

Log "========================================" "Cyan"
Log "Account: $username" "Green"
Log "Token: $($Token.Substring(0,4))..." "Gray"
Log "Delay: ${DelayMs}ms per request" "Gray"
Log "Log: $LogFile" "Gray"
Log "State: $StateFile" "Gray"
Log "========================================" "Cyan"

# ====== 找 JSON ======
$safeName = $username -replace '[^a-zA-Z0-9]', '_'
$jsonPatterns = @(
    (Join-Path $dataDir "starred_repos.json"),
    (Join-Path $dataDir "stars_${username}.json"),
    (Join-Path $dataDir "stars_${safeName}.json"),
    (Join-Path $scriptDir "stars_${username}.json"),
    (Join-Path $scriptDir "stars_${safeName}.json"),
    (Join-Path $scriptDir "starred_repos.json"),
    (Join-Path $scriptDir "stars.json")
)

$foundJson = $null
foreach ($path in $jsonPatterns) {
    if (Test-Path $path) { $foundJson = $path; break }
}

if (-not $foundJson) {
    Log "[ERROR] JSON not found." "Red"
    Write-Host "[ERROR] JSON not found. Looking for:" -ForegroundColor Red
    foreach ($p in $jsonPatterns) { Write-Host "  $p" -ForegroundColor Gray }
    exit 1
}

$allRepos = Get-Content $foundJson -Encoding UTF8 | ConvertFrom-Json
$total = $allRepos.Count
Log "JSON: $(Split-Path $foundJson -Leaf)" "Gray"
Log "Total stars: $total" "Cyan"
Log "Starting... (will retry forever until done)" "Gray"
Log ""

# ====== 读取断点状态 ======
$doneMap = @{}
if (Test-Path $StateFile) {
    Get-Content $StateFile -Encoding UTF8 | ForEach-Object {
        if ($_) {
            $parts = $_ -split '\|', 2
            $doneMap[$parts[0]] = $parts[1]
        }
    }
    $doneCount = $doneMap.Count
    if ($doneCount -gt 0) {
        Log "Resuming: $doneCount already done, $($total - $doneCount) remaining" "Yellow"
    }
}

# ====== 核心请求函数 ======
function Invoke-Star($owner, $name, $retryCount) {
    $attempt = 0
    $waitSec = 0

    while ($true) {
        $attempt++
        try {
            Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
                -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
            return "success"
        } catch {
            $statusCode = [int]$_.Exception.Response.StatusCode

            if ($statusCode -eq 304) {
                return "already"

            } elseif ($statusCode -eq 403) {
                # Secondary Rate Limit - 等5分钟
                $waitSec = 300
                if ($attempt -gt 1) {
                    Log "  [403 #${attempt}] $owner/$name - waiting ${waitSec}s..." "Yellow"
                }
                Start-Sleep -Seconds $waitSec

            } elseif ($statusCode -eq 429) {
                # Primary Rate Limit - 等 Retry-After 或 5分钟
                $waitSec = 300
                try {
                    $waitSec = [int]$_.Exception.Response.Headers["Retry-After"][0]
                    if ($waitSec -lt 60) { $waitSec = 60 }
                } catch {}
                if ($attempt -gt 1) {
                    Log "  [429 #${attempt}] $owner/$name - waiting ${waitSec}s..." "Yellow"
                }
                Start-Sleep -Seconds ($waitSec + 5)

            } elseif ($statusCode -eq 500 -or $statusCode -eq 502 -or $statusCode -eq 503) {
                # GitHub 临时错误 - 等30秒重试
                $waitSec = 30
                if ($attempt -gt 1) {
                    Log "  [${statusCode} #${attempt}] $owner/$name - waiting ${waitSec}s..." "Yellow"
                }
                Start-Sleep -Seconds $waitSec

            } else {
                # 其他错误（网络等）- 等10秒重试
                $waitSec = 10
                if ($attempt -gt 1) {
                    Log "  [ERR #${attempt}] $owner/$name (HTTP $statusCode) - waiting ${waitSec}s..." "Yellow"
                }
                Start-Sleep -Seconds $waitSec
            }

            # 超过最大单次重试次数后，等更长时间再试
            if ($attempt -gt $retryCount) {
                Log "  [MAX RETRY $retryCount] $owner/$name - pausing 10min..." "Red"
                Start-Sleep -Seconds 600
            }
        }
    }
}

# ====== 主循环 ======
$done = $doneMap.Count
$already = 0
$startTime = Get-Date
$logInterval = 50   # 每50个输出进度

foreach ($repo in $allRepos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    # 跳过已完成的
    if ($doneMap.ContainsKey($fullName)) {
        $done++
        continue
    }

    # 节奏控制
    if ($done -gt 0) {
        Start-Sleep -Milliseconds $DelayMs
    }

    # 请求
    $result = Invoke-Star $owner $name 10

    if ($result -eq "success") {
        $doneMap[$fullName] = "success"
        $done++
    } elseif ($result -eq "already") {
        $doneMap[$fullName] = "already"
        $already++
        $done++
    } else {
        # 理论上不会走到这里
        $doneMap[$fullName] = "unknown"
        $done++
    }

    # 保存断点
    "$fullName|$($doneMap[$fullName])" | Out-File $StateFile -Append -Encoding UTF8

    # 进度输出
    if ($done % $logInterval -eq 0) {
        $elapsed = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("hh\:mm\:ss")
        $rate = [math]::Round($done / [math]::Max(1, (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds))
        $remaining = $total - $done
        $etaSec = if ($rate -gt 0) { [math]::Round($remaining / $rate) } else { 0 }
        $etaStr = if ($etaSec -gt 3599) { "$([math]::Round($etaSec/3600))h" } elseif ($etaSec -gt 59) { "$([math]::Round($etaSec/60))m" } else { "${etaSec}s" }
        Log "[$done / $total] Done:$done  Already:$already  Remaining:$remaining  Elapsed:$elapsed  Rate:${rate}/s  ETA:$etaStr" "Gray"
    }
}

$totalTime = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("hh\:mm\:ss")
Log ""
Log "========================================" "Green"
Log "DONE! Time: $totalTime" "Green"
Log " Done: $($done - $already)  Already starred: $already  Total processed: $done / $total" "Green"
Log "Log: $LogFile" "Gray"
Log "========================================" "Green"
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "DONE! Time: $totalTime" -ForegroundColor Green
Write-Host " Done: $($done - $already)  Already: $already  Total: $done / $total" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
