# GitHub Stars Restorer
# Usage: powershell -ExecutionPolicy Bypass -File restore_stars.ps1 -Token "ghp_xxx"

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

Write-Host "Total to star: $total`n"

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 15
        $done++
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 304) {
            $already++
        } else {
            $fail++
            Write-Host "  [FAIL] $fullName (HTTP $statusCode)"
        }
    }

    if ($done % 100 -eq 0 -and $done -gt 0) {
        Write-Host "Progress: $done / $total  done:$done  already:$already  fail:$fail" -ForegroundColor Yellow
    }

    Start-Sleep -Milliseconds 120
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " DONE!" -ForegroundColor Green
Write-Host " Done: $done  Already starred: $already  Failed: $fail"
Write-Host "========================================" -ForegroundColor Green