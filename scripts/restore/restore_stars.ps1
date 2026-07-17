# GitHub Stars 一键恢复脚本
# 用法: powershell -ExecutionPolicy Bypass -File restore_stars.ps1 "ghp_xxx"
# 只需传 Token，全自动：识别账号 -> 找 JSON -> 开始恢复

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [int]$DelayMs = 500     # 每次请求间隔ms，默认500ms（约7200 stars/h，安全阈值）
)

$ErrorActionPreference = "Continue"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "GitHub-Stars-Restore/1.0"
}

function Log($msg, $color) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    $line | Out-File $LogFile -Append -Encoding UTF8
    if ($color) { Write-Host $line -ForegroundColor $color }
    else { Write-Host $line }
}

# ====== 1. 自动识别账号 ======
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Stars Restorer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
$username = $me.login
$projectDir = Split-Path (Split-Path $PSScriptRoot)
$LogFile = Join-Path $projectDir "restore_stars_${username}.log"

Log "Account: $username" "Green"
Log "Token: $($Token.Substring(0,4))..." "Gray"
Log "BaseDelay: ${DelayMs}ms" "Gray"

# ====== 2. 自动找 JSON ======
$safeName = $username -replace '[^a-zA-Z0-9]', '_'
$dataDir = Join-Path (Split-Path (Split-Path $PSScriptRoot)) "data"
$jsonPatterns = @(
    (Join-Path $dataDir "starred_repos.json"),
    (Join-Path $dataDir "stars_${username}.json"),
    (Join-Path $dataDir "stars_${safeName}.json"),
    (Join-Path $PSScriptRoot "stars_${username}.json"),
    (Join-Path $PSScriptRoot "stars_${safeName}.json"),
    (Join-Path $PSScriptRoot "starred_repos.json"),
    (Join-Path $PSScriptRoot "stars.json")
)

$foundJson = $null
foreach ($path in $jsonPatterns) {
    if (Test-Path $path) { $foundJson = $path; break }
}

if (-not $foundJson) {
    Log "[ERROR] No JSON found." "Red"
    exit 1
}

Log "JSON: $(Split-Path $foundJson -Leaf)" "Gray"

$repos = Get-Content $foundJson -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
Log "Total to star: $total" "Cyan"
Log "Log: $LogFile" "Gray"
Log "Starting..." "Gray"
Log ""

# ====== 3. 恢复循环 ======
$done = $fail = $already = 0
$startTime = Get-Date
$abuse403Count = 0

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    # 节奏控制
    Start-Sleep -Milliseconds $DelayMs

    $starred = $false

    # ---- 第一次请求 ----
    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
        $starred = $true
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode

        if ($statusCode -eq 304) {
            $already++; $starred = $true

        } elseif ($statusCode -eq 403) {
            # Secondary Rate Limit: 等60秒，重试
            $abuse403Count++
            Log "[WARN] 403 Secondary Limit hit #${abuse403Count} - pausing 60s..." "Yellow"
            Log "[WARN] $fullName" "Yellow"
            Start-Sleep -Seconds 61
            try {
                Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
                    -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
                $starred = $true
            } catch {
                $statusCode2 = [int]$_.Exception.Response.StatusCode
                if ($statusCode2 -eq 304) {
                    $already++; $starred = $true
                } else {
                    Log "[FAIL] $fullName (HTTP $statusCode2)" "Red"
                }
            }

        } elseif ($statusCode -eq 429) {
            # Primary Rate Limit: 等 Retry-After 秒，重试
            $retryAfter = 60
            try { $retryAfter = [int]$_.Exception.Response.Headers["Retry-After"][0] } catch {}
            Log "[RATE LIMIT] sleeping ${retryAfter}s..." "Yellow"
            Start-Sleep -Seconds ($retryAfter + 1)
            try {
                Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
                    -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
                $starred = $true
            } catch {
                $statusCode2 = [int]$_.Exception.Response.StatusCode
                if ($statusCode2 -eq 304) {
                    $already++; $starred = $true
                } else {
                    Log "[FAIL] $fullName (HTTP $statusCode2)" "Red"
                }
            }

        } else {
            Log "[FAIL] $fullName (HTTP $statusCode)" "Red"
        }
    }

    if ($starred) { $done++ }

    if ($done % 10 -eq 0) {
        $elapsed = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("mm\:ss")
        $rate = [math]::Round($done / [math]::Max(1, (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds))
        Log "[$done / $total] Done:$done  Already:$already  Fail:$fail  ${elapsed}s  ${rate}/s" "Gray"
    }
}

$totalTime = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("mm\:ss")
Log ""
Log "========================================" "Green"
Log "DONE! Time: $totalTime" "Green"
Log " Done: $done  Already: $already  Failed: $fail  403-hits: $abuse403Count" "Green"
Log "========================================" "Green"
