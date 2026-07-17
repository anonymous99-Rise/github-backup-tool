# GitHub Stars 恢复脚本
# 用法: powershell -ExecutionPolicy Bypass -File restore_stars.ps1 -Token "ghp_xxx"
# 或: .\restore_stars.ps1 "ghp_xxx"

param(
    [Parameter(Mandatory=$true)]
    [string]$Token,
    [string]$JsonFile = "$PSScriptRoot\starred_repos.json"
)

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
    "User-Agent" = "Tresh-King-StarRestore"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " GitHub Star Restorer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
Write-Host "Account: $($me.login)" -ForegroundColor Green
Write-Host ""

$repos = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
$done = $fail = $already = 0

Write-Host "待恢复: $total 个 stars`n"

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 15
        $done++
        $mark = "✅"
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 304) {
            $already++
            $mark = "⏭️"
        } else {
            $fail++
            $mark = "❌"
            Write-Host "  $mark $fullName (HTTP $statusCode)"
        }
    }

    if ($done % 100 -eq 0 -and $done -gt 0) {
        Write-Host "进度: $done / $total  成功:$done  已star:$already  失败:$fail" -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 120
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " 完成!" -ForegroundColor Green
Write-Host " 成功: $done  已star: $already  失败: $fail" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green