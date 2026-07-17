param(
    [string]$Token = "",
    [string]$RepoListFile = "$PSScriptRoot\starred_list.txt",
    [string]$BackupBaseDir = "D:\github_repos\github_backup",
    [int]$CloneDelayMs = 800
)

$BackupDir = "$BackupBaseDir\starred_backup_$(Get-Date -Format 'yyyyMMdd')"
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
    param([string]$fullName)

    $parts = $fullName -split '/'
    if ($parts.Count -ne 2) {
        Write-Log "[SKIP-Invalid] $fullName"
        return $true
    }
    $owner = $parts[0]
    $repo  = $parts[1]
    $target = Join-Path $BackupDir "${owner}_${repo}.git"
    $log    = Join-Path $BackupDir "repo_log_${owner}_${repo}.txt"

    if (Test-Path $target) {
        Write-Log "[Skip-Exists] $fullName"
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        $url = "https://github.com/$owner/$repo.git"
    } else {
        $url = "https://$Token@github.com/$owner/$repo.git"
    }

    Write-Log "[Clone] $fullName"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    git clone --mirror $url $target 2>&1 | Out-File $log -Encoding UTF8
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    if ($exitCode -eq 0) {
        $size = (Get-ChildItem $target -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($size -gt 1GB) { "{0:N1} GB" -f ($size/1GB) } elseif ($size -gt 1MB) { "{0:N1} MB" -f ($size/1MB) } else { "{0:N1} KB" -f ($size/1KB) }
        Write-Log "[OK] $fullName (${sizeStr}, $($sw.ElapsedSeconds)s)"
        $fullName | Out-File -FilePath $DONE_FILE -Append -Encoding UTF8
        return $true
    } else {
        Write-Log "[FAIL] $fullName (exit:$exitCode, $($sw.ElapsedSeconds)s)"
        $fullName | Out-File -FilePath $FAIL_FILE -Append -Encoding UTF8
        return $false
    }
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] git not found." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $RepoListFile)) {
    Write-Host "[ERROR] Starred list not found: $RepoListFile" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}
"" | Out-File -FilePath $LOG_FILE -Encoding UTF8
"" | Out-File -FilePath $DONE_FILE -Encoding UTF8
"" | Out-File -FilePath $FAIL_FILE -Encoding UTF8

$repos = Get-Content $RepoListFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" -and $_ -match '/' }
$total = $repos.Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Starred Repos Backup" -ForegroundColor Cyan
Write-Host " Total: $total starred repos"
Write-Host " Backup dir: $BackupDir"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$doneCount = 0
$skipCount = 0

foreach ($repo in $repos) {
    $repo = $repo.Trim()
    if ([string]::IsNullOrWhiteSpace($repo)) { continue }

    $parts = $repo -split '/'
    $targetName = if ($parts.Count -eq 2) { "$($parts[0])_$($parts[1])" } else { $repo }
    if (Test-Path (Join-Path $BackupDir "${targetName}.git")) {
        $skipCount++
        continue
    }

    Clone-One -fullName $repo
    $doneCount++

    if ($doneCount % 30 -eq 0) {
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
