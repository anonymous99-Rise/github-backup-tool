# GitHub 仓库批量恢复脚本
# 用途: 从本地备份镜像批量恢复到新账号，支持断点续传、大仓库超时重试
#
# 用法:
#   # 只传 Token，自动从 data/repo_list.txt 恢复
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx"
#
#   # 指定备份目录
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx" -BackupDir "D:\backup"
#
#   # 指定仓库列表
#   powershell -ExecutionPolicy Bypass -File restore_repos.ps1 "ghp_xxx" -Repos "repo1","repo2"

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [string]$BackupDir = "",
    [string]$RepoList = "",
    [string[]]$Repos = @(),
    [int]$PushTimeoutSec = 600,
    [int]$RetryCount = 3,
    [int]$RetryDelaySec = 10
)

$ErrorActionPreference = "Continue"

# ====== 自动路径 ======
$scriptDir = Split-Path $PSScriptRoot          # scripts/restore
$projectDir = Split-Path $scriptDir             # github-backup-tool 根目录
$dataDir = Join-Path $projectDir "data"

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

# ====== 日志 ======
$LogFile = Join-Path $projectDir "restore_repos_${targetUser}.log"
$StateFile = Join-Path $projectDir "restore_repos_${targetUser}.state"
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
Log "Push Timeout: ${PushTimeoutSec}s / Retry: $RetryCount times"

# ====== 找备份目录 ======
if (-not $BackupDir) {
    $candidates = @(
        $dataDir,
        (Join-Path $projectDir "github_backup"),
        $projectDir,
        "D:\github_backup",
        "$env:USERPROFILE\github_backup"
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { $BackupDir = $c; break }
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
        $candidates = @(
            (Join-Path $dataDir "repo_list.txt"),
            (Join-Path $projectDir "repo_list.txt"),
            (Join-Path $scriptDir "repo_list.txt")
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $RepoList = $c; break }
        }
    }

    if ($RepoList -and (Test-Path $RepoList)) {
        $Repos = Get-Content $RepoList -Encoding UTF8 | Where-Object { $_ -and $_ -notmatch "^#" }
        Log "Loaded $($Repos.Count) repos from: $RepoList" "Cyan"
    } else {
        $Repos = Get-ChildItem $BackupDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name.EndsWith(".git") } |
            ForEach-Object { $_.Name -replace "\.git$","" }
        Log "Scanned $($Repos.Count) repos from backup dir" "Cyan"
    }
}

if ($Repos.Count -eq 0) {
    Log "[ERROR] No repos found to restore." "Red"
    exit 1
}

Log "Total repos to restore: $($Repos.Count)" "Cyan"

# ====== 断点续传 ======
$doneRepos = @{}
if (Test-Path $StateFile) {
    Get-Content $StateFile -Encoding UTF8 | ForEach-Object { if ($_) { $doneRepos[$_] = $true } }
    $remaining = $Repos.Count - $doneRepos.Count
    if ($remaining -lt $Repos.Count) {
        Log "Resume: $remaining repos remaining (already done: $($doneRepos.Count))" "Yellow"
    }
}

Log "Starting..." "Gray"
Log ""

$success = $fail = $skip = 0
$startTime = Get-Date

foreach ($repo in $Repos) {
    if ($doneRepos[$repo]) {
        $skip++; continue
    }

    $gitDir = Join-Path $BackupDir "${repo}.git"
    if (-not (Test-Path $gitDir)) {
        Log "[SKIP] Not found: $repo" "Gray"
        $repo | Out-File $StateFile -Append -Encoding UTF8
        $fail++; continue
    }

    # 1. 创建空仓库
    $httpCode = $null
    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/repos" `
            -Headers $headers -Method POST `
            -Body (ConvertTo-Json -Compress @{name=$repo; description="Restored from backup"; private=$false}) `
            -TimeoutSec 30 | Out-Null
        $httpCode = 201
    } catch {
        $httpCode = [int]$_.Exception.Response.StatusCode
    }

    if ($httpCode -eq 422) {
        Log "[SKIP] Already exists: $repo" "Gray"
    } elseif ($httpCode -ne 201) {
        Log "[FAIL] Create failed (HTTP $httpCode): $repo" "Yellow"
        $repo | Out-File $StateFile -Append -Encoding UTF8
        $fail++; continue
    }

    # 2. Push 镜像
    $pushUrl = "https://$Token@github.com/$targetUser/${repo}.git"
    $pushOk = $false

    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        Push-Location $gitDir -ErrorAction SilentlyContinue
        if (-not $?) { Pop-Location; continue }

        git remote set-url origin $pushUrl 2>$null
        $env:GIT_SSH_COMMAND = "ssh -o ConnectTimeout=30"

        $pushResult = git push --mirror origin 2>&1
        if ($LASTEXITCODE -eq 0) {
            $pushOk = $true
            Pop-Location
            break
        } else {
            $err = ($pushResult | Out-String).Trim()
            if ($attempt -lt $RetryCount) {
                Log "  [RETRY $attempt] $repo : $err" "Gray"
                Start-Sleep -Seconds $RetryDelaySec
            } else {
                Log "  [FAIL] $repo : $err" "Yellow"
            }
        }
        Pop-Location
    }

    if ($pushOk) {
        $success++
        $sizeKB = [math]::Round((Get-ChildItem $gitDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1KB)
        Log "[$success] $repo (${sizeKB}KB)" "Green"
    } else {
        $fail++
    }

    # 3. 记录状态
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
