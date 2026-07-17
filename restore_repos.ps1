# GitHub 仓库批量恢复脚本
# 用途: 从本地备份镜像批量恢复到新账号，支持断点续传、大仓库超时重试
#
# 用法:
#   # 方式1: 只传 Token，自动从 repo_list.txt 恢复
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx"
#
#   # 方式2: 指定备份目录和仓库列表
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx" -BackupDir "D:\backup" -RepoList "repo_list.txt"
#
#   # 方式3: 从 repo_list.txt 读取，手动指定恢复哪些
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx" -Repos "repo1","repo2","repo3"
#
# 日志文件: restore_repos_<账号>.log

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [string]$BackupDir = "",
    [string]$RepoList = "",
    [string[]]$Repos = @(),
    [int]$PushTimeoutSec = 600,      # git push 超时(大仓库调大)
    [int]$RetryCount = 3,           # 失败重试次数
    [int]$RetryDelaySec = 10        # 重试间隔
)

$ErrorActionPreference = "Continue"

# ====== 自动识别账号 ======
$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "GitHub-Repo-Restore"
}

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
$targetUser = $me.login

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Repo Batch Restorer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Account: $targetUser" -ForegroundColor Green

# ====== 日志设置 ======
$LogFile = Join-Path $PSScriptRoot "restore_repos_${targetUser}.log"
$StateFile = Join-Path $PSScriptRoot "restore_repos_${targetUser}.state"  # 断点续传用
"" | Out-File $LogFile -Encoding UTF8
"" | Out-File $StateFile -Encoding UTF8

function Log($msg, $color) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    $line | Out-File $LogFile -Append -Encoding UTF8
    if ($color) { Write-Host $line -ForegroundColor $color }
    else { Write-Host $line }
}

Log "Account: $targetUser"
Log "Push Timeout: ${PushTimeoutSec}s"
Log "Retry: $RetryCount times"

# ====== 找备份目录 ======
if (-not $BackupDir) {
    # 自动找本地备份
    $candidates = @(
        (Join-Path $PSScriptRoot ".."),
        (Join-Path $PSScriptRoot "github_backup"),
        "D:\github_backup",
        "$env:USERPROFILE\github_backup"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $BackupDir = $c; break }
    }
}

if (-not $BackupDir -or -not (Test-Path $BackupDir)) {
    Log "[ERROR] Backup dir not found. Use -BackupDir to specify." "Red"
    exit 1
}

Log "BackupDir: $BackupDir" "Gray"

# ====== 获取待恢复仓库列表 ======
if ($Repos.Count -eq 0) {
    if (-not $RepoList) {
        $RepoList = Join-Path $BackupDir "repo_list.txt"
        if (-not (Test-Path $RepoList)) {
            $RepoList = Join-Path $PSScriptRoot "repo_list.txt"
        }
    }

    if (Test-Path $RepoList) {
        $Repos = Get-Content $RepoList -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch "^#" }
        Log "Loaded $($Repos.Count) repos from: $RepoList" "Cyan"
    } else {
        # 从备份目录扫描 .git 文件夹
        $Repos = Get-ChildItem $BackupDir -Directory | Where-Object { $_.Name.EndsWith(".git") } | ForEach-Object { $_.Name -replace "\.git$","" }
        Log "Scanned $($Repos.Count) repos from backup dir" "Cyan"
    }
}

if ($Repos.Count -eq 0) {
    Log "[ERROR] No repos found to restore." "Red"
    exit 1
}

Log "Total repos to restore: $($Repos.Count)" "Cyan"

# ====== 读取断点状态 ======
$doneRepos = @{}
if (Test-Path $StateFile) {
    Get-Content $StateFile -Encoding UTF8 | ForEach-Object {
        if ($_) { $doneRepos[$_] = $true }
    }
    $remaining = $Repos.Count - $doneRepos.Count
    Log "Resume: $remaining repos remaining (already done: $($doneRepos.Count))" "Yellow"
}

Log "Starting..." "Gray"
Log ""

$success = $fail = $skip = 0
$startTime = Get-Date

foreach ($repo in $Repos) {
    if ($doneRepos[$repo]) {
        $skip++
        continue
    }

    $gitDir = Join-Path $BackupDir "${repo}.git"
    if (-not (Test-Path $gitDir)) {
        Log "[SKIP] Not found in backup: $repo" "Gray"
        $fail++
        $repo | Out-File $StateFile -Append -Encoding UTF8
        continue
    }

    # ===== 1. 创建空仓库 =====
    $httpCode = $null
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/user/repos" `
            -Headers $headers -Method POST `
            -Body (ConvertTo-Json -Compress @{name=$repo; description="Restored from backup"; private=$false}) `
            -TimeoutSec 30
        $httpCode = 201
    } catch {
        $httpCode = [int]$_.Exception.Response.StatusCode
    }

    if ($httpCode -eq 422) {
        Log "[SKIP] Already exists: $repo" "Gray"
    } elseif ($httpCode -ne 201) {
        Log "[FAIL] Create repo failed (HTTP $httpCode): $repo" "Yellow"
        $fail++
        $repo | Out-File $StateFile -Append -Encoding UTF8
        continue
    }

    # ===== 2. Push 镜像 ======
    $pushUrl = "https://$Token@github.com/$targetUser/${repo}.git"
    $pushOk = $false

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        Push-Location $gitDir
        try {
            # 设置 push remote
            git remote set-url origin $pushUrl 2>$null
            # 超时大仓库保护
            $env:GIT_SSH_COMMAND = "ssh -o ConnectTimeout=30"
            $pushResult = git push --mirror origin 2>&1

            if ($LASTEXITCODE -eq 0) {
                $pushOk = $true
                Pop-Location
                break
            } else {
                $err = $pushResult -join " "
                if ($attempt -lt $RetryCount) {
                    Log "  [RETRY $attempt] push failed: $err" "Gray"
                    Start-Sleep -Seconds $RetryDelaySec
                } else {
                    Log "  [FAIL] push failed after $RetryCount attempts: $err" "Yellow"
                }
            }
        } catch {
            $err = $_.Exception.Message
            if ($attempt -lt $RetryCount) {
                Log "  [RETRY $attempt] error: $err" "Gray"
                Start-Sleep -Seconds $RetryDelaySec
            } else {
                Log "  [FAIL] $err" "Yellow"
            }
        }
        Pop-Location
    }

    if ($pushOk) {
        $success++
        $sizeKB = [math]::Round((Get-ChildItem $gitDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB)
        Log "[$success] $repo (${sizeKB}KB)" "Green"
    } else {
        $fail++
    }

    # ===== 3. 记录状态 + 进度 ======
    $repo | Out-File $StateFile -Append -Encoding UTF8

    $totalDone = $success + $fail + $skip
    if ($totalDone % 10 -eq 0 -and $totalDone -gt 0) {
        $elapsed = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("mm\:ss")
        $rate = [math]::Round($totalDone / [math]::Max(1, (New-TimeSpan -Start $startTime -End (Get-Date)).TotalSeconds))
        $etaSec = [math]::Round(($Repos.Count - $totalDone) / $rate)
        Log "[${totalDone}/${Repos.Count}] Done:$success  Fail:$fail  Skip:$skip  ${elapsed}s  ETA:${etaSec}s  ${rate}/s" "Gray"
    }

    Start-Sleep -Milliseconds 300
}

$totalTime = (New-TimeSpan -Start $startTime -End (Get-Date)).ToString("mm\:ss")
Log ""
Log "========================================" "Green"
Log "DONE! Time: $totalTime" "Green"
Log " Success: $success  Failed: $fail  Skipped: $skip" "Green"
Log "Log: $LogFile" "Gray"
Log "========================================" "Green"
