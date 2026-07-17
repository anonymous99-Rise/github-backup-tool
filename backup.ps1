# ============================================================
# GitHub 仓库批量备份脚本 - PowerShell 版
# adminlove520 全量备份 | 2025-07-17
#
# 使用方法（Windows PowerShell）:
#   powershell -ExecutionPolicy Bypass -File backup.ps1
#
# 或者直接双击运行 build.bat
# ============================================================

param(
    [string]$GitHubUser = "adminlove520",
    [string]$Token = "",               # GitHub Token（可选，不填则用公共clone地址）
    [string]$RepoListFile = "$PSScriptRoot\repo_list.txt",
    [string]$BackupBaseDir = "D:\github_repos\github_backup",
    [int]$MaxParallel = 3,            # 并行克隆数量（建议不超过3）
    [int]$CloneDelayMs = 1500         # 每次克隆间隔（毫秒），避免GitHub限速
)

# -------- 配置 --------
$BackupDir = "$BackupBaseDir\github_backup_$(Get-Date -Format 'yyyyMMdd')"
$DONE_FILE = Join-Path $BackupDir ".done.txt"
$FAIL_FILE = Join-Path $BackupDir ".fail.txt"
$LOG_FILE  = Join-Path $BackupDir "backup.log"
# --------------------

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
        Write-Log "[跳过-已存在] $repo"
        return $true
    }

    # 构建 clone URL（有token用token，无token用公共地址）
    if ([string]::IsNullOrWhiteSpace($Token)) {
        $url = "https://github.com/$GitHubUser/${repo}.git"
    } else {
        $url = "https://$Token@github.com/$GitHubUser/${repo}.git"
    }

    Write-Log "[克隆中] $repo"

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = git clone --mirror $url $target 2>&1 | Out-File $log -Encoding UTF8
    $exitCode = $LASTEXITCODE
    $stopwatch.Stop()

    if ($exitCode -eq 0) {
        $size = (Get-ChildItem $target -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($size -gt 1GB) { "{0:N1} GB" -f ($size/1GB) } elseif ($size -gt 1MB) { "{0:N1} MB" -f ($size/1MB) } else { "{0:N1} KB" -f ($size/1KB) }
        Write-Log "[成功] $repo (${sizeStr}, $($stopwatch.ElapsedSeconds)s)"
        $repo | Out-File -FilePath $DONE_FILE -Append -Encoding UTF8
        return $true
    } else {
        Write-Log "[失败] $repo (退出码:$exitCode, $($stopwatch.ElapsedSeconds)s) → 日志: $log"
        $repo | Out-File -FilePath $FAIL_FILE -Append -Encoding UTF8
        return $false
    }
}

# ===================== 主程序 =====================

# 检查依赖
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "[错误] 未安装 git，请先安装 Git for Windows" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $RepoListFile)) {
    Write-Host "[错误] 找不到仓库列表: $RepoListFile" -ForegroundColor Red
    exit 1
}

# 初始化
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}
"" | Out-File -FilePath $LOG_FILE -Encoding UTF8
"" | Out-File -FilePath $DONE_FILE -Encoding UTF8
"" | Out-File -FilePath $FAIL_FILE -Encoding UTF8

# 读取仓库列表
$repos = Get-Content $RepoListFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }
$total = $repos.Count

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub 仓库批量备份" -ForegroundColor Cyan
Write-Host " 用户: $GitHubUser"
Write-Host " 仓库数: $total"
Write-Host " 备份目录: $BackupDir"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$doneCount = 0
$failCount = 0
$skipCount = 0

foreach ($repo in $repos) {
    $repo = $repo.Trim()

    # 跳过已存在的
    if (Test-Path (Join-Path $BackupDir "${repo}.git")) {
        Write-Log "[跳过-已存在] $repo"
        $skipCount++
        continue
    }

    $ok = Clone-One -repo $repo
    $doneCount++

    if ($ok) { $failCount = $failCount } else { $failCount++ }

    # 每20个显示进度
    if ($doneCount % 20 -eq 0) {
        $failNow = (Get-Content $FAIL_FILE -Encoding UTF8 | Measure-Object -Line).Lines
        Write-Host ""
        Write-Host ">>> 进度: $doneCount/$total | 失败: $failNow | 跳过: $skipCount <<<" -ForegroundColor Yellow
        Write-Host ""
    }

    # 避免触发 GitHub 限速
    Start-Sleep -Milliseconds $CloneDelayMs
}

# ---- 最终报告 ----
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " 备份完成 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$failFinal = (Get-Content $FAIL_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }).Count
$doneFinal = (Get-Content $DONE_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" }).Count

Write-Host "成功: $doneFinal 个"
Write-Host "失败: $failFinal 个"
Write-Host "跳过: $skipCount 个"
Write-Host ""
Write-Host "备份目录: $BackupDir"

# 计算总大小
$totalSize = Get-ChildItem $BackupDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum
if ($totalSize.Sum -gt 1GB) {
    Write-Host "备份总大小: {0:N2} GB" -f ($totalSize.Sum / 1GB)
} elseif ($totalSize.Sum -gt 1MB) {
    Write-Host "备份总大小: {0:N2} MB" -f ($totalSize.Sum / 1MB)
}

Write-Host ""

if ($failFinal -gt 0) {
    Write-Host "失败仓库列表:" -ForegroundColor Red
    Get-Content $FAIL_FILE -Encoding UTF8 | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "重新克隆失败的仓库:" -ForegroundColor Yellow
    Write-Host '  cd $BackupDir'
    Write-Host '  Get-Content .fail.txt | ForEach-Object { git clone --mirror "https://github.com/$GitHubUser/${_}.git" "${_}.git"; Start-Sleep -Milliseconds 2000 }'
}

Write-Host ""
Write-Host "按任意键退出..."
[void][System.Console]::ReadKey($true)
