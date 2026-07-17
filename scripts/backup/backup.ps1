param(
    [string]$GitHubUser = "adminlove520",
    [string]$Token = "",               # GitHub Token (optional)
    [string]$RepoListFile = "$PSScriptRoot\repo_list.txt",
    [string]$BackupBaseDir = "D:\github_repos\github_backup",
    [int]$CloneDelayMs = 1000
)

$BackupDir = "$BackupBaseDir\github_backup_$(Get-Date -Format 'yyyyMMdd')"
$DONE_FILE = Join-Path $BackupDir ".done.txt"
$FAIL_FILE = Join-Path $BackupDir ".fail.txt"
$LOG_FILE  = Join-Path $BackupDir "backup.log"

function Write-Log {
    param([string]$msg)
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    Write-Host $line
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Clone-One {
    param([string]$repo)

    $target = Join-Path $BackupDir "${repo}.git"
    $log    = Join-Path $BackupDir "repo_log_${repo}.txt"

    if (Test-Path $target) {
        Write-Log "[Skip-Exists] $repo"
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        $url = "https://github.com/$GitHubUser/${repo}.git"
    } else {
        $url = "https://$Token@github.com/$GitHubUser/${repo}.git"
    }

    Write-Log "[Clone] $repo"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    git clone --mirror $url $target 2>&1 | Out-File $log -Encoding UTF8
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    if ($exitCode -eq 0) {
        $size = (Get-ChildItem $target -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($size -gt 1GB) { "{0:N1} GB" -f ($size/1GB) } elseif ($size -gt 1MB) { "{0:N1} MB" -f ($size/1MB) } else { "{0:N1} KB" -f ($size/1KB) }
        Write-Log "[OK] $repo (${sizeStr}, $($sw.ElapsedSeconds)s)"
        $repo | Out-File -FilePath $DONE_FILE -Append -Encoding UTF8
        return $true
    } else {
        Write-Log "[FAIL] $repo (exit:$exitCode, $($sw.ElapsedSeconds)s)"
        $repo | Out-File -FilePath $FAIL_FILE -Append -Encoding UTF8
        return $false
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] git not found. Please install Git for Windows first." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $RepoListFile)) {
    Write-Host "[ERROR] Repo list not found: $RepoListFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}
"" | Out-File -FilePath $LOG_FILE -Encoding UTF8
"" | Out-File -FilePath $DONE_FILE -Encoding UTF8
"" | Out-File -FilePath $FAIL_FILE -Encoding UTF8

$repos = Get-Content $RepoListFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
$total = $repos.Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Repo Backup" -ForegroundColor Cyan
Write-Host " User: $GitHubUser"
Write-Host " Total: $total repos"
Write-Host " Backup dir: $BackupDir"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$doneCount = 0
$skipCount = 0

foreach ($repo in $repos) {
    $repo = $repo.Trim()

    if (Test-Path (Join-Path $BackupDir "${repo}.git")) {
        $skipCount++
        continue
    }

    Clone-One -repo $repo
    $doneCount++

    if ($doneCount % 20 -eq 0) {
        $failNow = (Get-Content $FAIL_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }).Count
        Write-Host ""
        Write-Host ">>> Progress: $doneCount/$total | Failed: $failNow | Skipped: $skipCount <<<" -ForegroundColor Yellow
        Write-Host ""
    }

    Start-Sleep -Milliseconds $CloneDelayMs
}

$failFinal = (Get-Content $FAIL_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }).Count
$doneFinal = (Get-Content $DONE_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }).Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Backup Done $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Success: $doneFinal"
Write-Host "Failed: $failFinal"
Write-Host "Skipped: $skipCount"
Write-Host "Backup dir: $BackupDir"

$totalSize = Get-ChildItem $BackupDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
if ($totalSize.Sum -gt 1GB) {
    Write-Host "Total size: {0:N2} GB" -f ($totalSize.Sum / 1GB)
} elseif ($totalSize.Sum -gt 1MB) {
    Write-Host "Total size: {0:N2} MB" -f ($totalSize.Sum / 1MB)
}

if ($failFinal -gt 0) {
    Write-Host ""
    Write-Host "Failed repos:" -ForegroundColor Red
    Get-Content $FAIL_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
Write-Host "Done. Press any key to exit..."
[void][System.Console]::ReadKey($true)
