# GitHub Stars 一键恢复脚本
# 用法: powershell -ExecutionPolicy Bypass -File restore_stars.ps1 "ghp_xxx"
# 只需传 Token，全自动：识别账号 -> 找 JSON -> 开始恢复

param(
    [Parameter(Mandatory=$true)]
    [string]$Token
)

$ErrorActionPreference = "Continue"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "GitHub-Stars-Restore"
}

function Log($msg, $color) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    $line | Out-File $LogFile -Append -Encoding UTF8
    if ($color) { Write-Host $line -ForegroundColor $color }
    else { Write-Host $line }
}

# 1. 自动识别账号
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Stars Restorer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
$username = $me.login
$LogFile = Join-Path $PSScriptRoot "restore_${username}.log"

Log "Account: $username" "Green"
Log "Token: $($Token.Substring(0,4))..." "Gray"

# 2. 自动找 JSON 文件
$safeName = $username -replace '[^a-zA-Z0-9]', '_'
$jsonPatterns = @(
    "stars_${username}.json",
    "stars_${safeName}.json",
    "starred_${username}.json",
    "starred_repos.json",
    "stars.json"
)

$foundJson = $null
foreach ($p in $jsonPatterns) {
    $path = Join-Path $PSScriptRoot $p
    if (Test-Path $path) {
        $foundJson = $path
        break
    }
}

if (-not $foundJson) {
    Log "[ERROR] No JSON found. Put stars_${username}.json in script folder." "Red"
    Write-Host "[ERROR] JSON not found. Looking for:" -ForegroundColor Red
    foreach ($p in $jsonPatterns) { Write-Host "  - $p" -ForegroundColor Gray }
    exit 1
}

Log "JSON: $(Split-Path $foundJson -Leaf)" "Gray"

$repos = Get-Content $foundJson -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
Log "Total to star: $total" "Cyan"
Log "Log: $LogFile" "Gray"
Log "Starting..." "Gray"
Log ""

$done = $fail = $already = 0
$startTime = Get-Date

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
        $done++
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 304) {
            $already++
        } else {
            $fail++
            Log "[FAIL] $fullName (HTTP $statusCode)" "Yellow"
        }
    }

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
Log " Done: $done  Already: $already  Failed: $fail" "Green"
Log "========================================" "Green"
