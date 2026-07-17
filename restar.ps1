# ============================================================
# GitHub Starred 仓库一键重新 Star 脚本
# 用途: 账号注销前导出 Star 列表，新账号一键恢复 Star
#
# 使用方法:
#   powershell -ExecutionPolicy Bypass -File restar.ps1 -Token "ghp_xxx"
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [string]$JsonFile = "$PSScriptRoot\starred_repos.json",
    [string]$BackupFile = "$PSScriptRoot\starred_restored_list.txt",
    [int]$RateLimitDelayMs = 300
)

if (-not (Test-Path $JsonFile)) {
    Write-Host "[ERROR] JSON file not found: $JsonFile" -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "adminlove520-backup-tool"
}

$repos = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Star Restorer" -ForegroundColor Cyan
Write-Host " Total: $total repos to star"
Write-Host " Token: $($Token.Substring(0, [Math]::Min(4, $Token.Length)))..." -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$doneCount = 0
$failCount = 0
$alreadyCount = 0

# 检查当前用户
$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
Write-Host "Account: $($me.login)" -ForegroundColor Green
Write-Host ""

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $doneCount++

    # 先检查是否已经 star
    $checkUri = "https://api.github.com/user/starred/$fullName"
    try {
        $starred = $false
        $response = Invoke-WebRequest -Uri $checkUri -Headers $headers -Method GET -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            $starred = $true
        }
    } catch {
        # 404 = 没 star，其他错误继续尝试 star
        if ($_.Exception.Response.StatusCode -ne 404) {
            Write-Host "[WARN] Check failed: $fullName" -ForegroundColor Yellow
        }
    }

    if ($starred) {
        Write-Host "[Already] $fullName" -ForegroundColor Gray
        $alreadyCount++
        continue
    }

    # 执行 star
    $starUri = "https://api.github.com/user/starred/$fullName"
    try {
        $null = Invoke-WebRequest -Uri $starUri -Headers $headers -Method PUT -TimeoutSec 10
        Write-Host "[STARRED] $fullName" -ForegroundColor Green
        Add-Content -Path $BackupFile -Value "$fullName" -Encoding UTF8
    } catch {
        $statusCode = $_.Exception.Response.StatusCode
        Write-Host "[FAIL] $fullName (HTTP $statusCode)" -ForegroundColor Red
        $failCount++
    }

    # 每30个显示进度
    if ($doneCount % 30 -eq 0) {
        Write-Host ""
        Write-Host ">>> Progress: $doneCount/$total | Failed: $failCount | Already starred: $alreadyCount <<<" -ForegroundColor Yellow
        Write-Host ""
    }

    # GitHub API 限速: 每小时 5000 次，300ms 间隔足够
    Start-Sleep -Milliseconds $RateLimitDelayMs
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Total: $total"
Write-Host "Already starred: $alreadyCount"
Write-Host "Newly starred: $(Get-Content $BackupFile -Encoding UTF8 | Measure-Object -Line).Lines"
Write-Host "Failed: $failCount"

if ($failCount -gt 0) {
    Write-Host ""
    Write-Host "NOTE: Some stars may have failed due to repo deletion or rename." -ForegroundColor Yellow
    Write-Host "Re-run the script to retry failed ones." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done. Press any key to exit..."
[void][System.Console]::ReadKey($true)
