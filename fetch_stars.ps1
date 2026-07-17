# GitHub Stars 获取脚本
# 用途: 动态抓取任意 GitHub 账号的 Stars 列表，输出为 JSON
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File fetch_stars.ps1 "adminlove520"
#   powershell -ExecutionPolicy Bypass -File fetch_stars.ps1 "adminlove520" -Token "ghp_xxx" -OutputFile "my_stars.json"
#
# 无 Token: 只能获取 public stars (有 rate limit)
# 有 Token:  可以获取 private stars + 更快

param(
    [Parameter(Mandatory=$true)]
    [string]$Username,
    [string]$Token = "",
    [string]$OutputFile = ""
)

# 默认输出到当前目录
if (-not $OutputFile) {
    $safeName = $Username -replace '[^a-zA-Z0-9]', '_'
    $OutputFile = Join-Path $PSScriptRoot "stars_${safeName}.json"
}

$headers = @{
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "GitHub-Stars-Fetch"
}
if ($Token) {
    $headers["Authorization"] = "token $Token"
}

Write-Host "========================================"
Write-Host " GitHub Stars Fetcher"
Write-Host "========================================"
Write-Host "Username: $Username"
Write-Host "Output:   $OutputFile"
if ($Token) { Write-Host "Token:    $($Token.Substring(0,4))..." -ForegroundColor Gray }

Write-Host ""
Write-Host "Fetching page 1..."

$allRepos = @()
$page = 1
$maxPages = 300

while ($page -le $maxPages) {
    $uri = "https://api.github.com/users/$Username/starred?per_page=100&page=$page"

    try {
        $repos = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET -TimeoutSec 30
    } catch {
        Write-Host "[ERROR] Page $page failed: $($_.Exception.Message)" -ForegroundColor Red
        break
    }

    if ($repos.Count -eq 0) {
        Write-Host "Page $page empty, done." -ForegroundColor Gray
        break
    }

    foreach ($repo in $repos) {
        $allRepos += @{
            full_name = $repo.full_name
            html_url  = $repo.html_url
            updated_at = $repo.updated_at
        }
    }

    Write-Host "  Page $page: +$($repos.Count) repos (total: $($allRepos.Count))" -ForegroundColor Gray
    $page++

    # 无 Token 时每页间隔一下
    if (-not $Token) { Start-Sleep -Milliseconds 200 }
}

# 写入 JSON 文件
$allRepos | ConvertTo-Json -Depth 10 | Out-File $OutputFile -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Done! Total: $($allRepos.Count) stars" -ForegroundColor Green
Write-Host " Saved: $OutputFile" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
