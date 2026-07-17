# GitHub Stars Restorer - Fast版
param(
    [Parameter(Mandatory=$true)]
    [string]$Token
)

$JsonFile = Join-Path $PSScriptRoot "starred_repos.json"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
}

Write-Host "========================================"
Write-Host " GitHub Star Restorer (Fast)"
Write-Host "========================================"

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
Write-Host "Account: $($me.login)"

if (-not (Test-Path $JsonFile)) {
    Write-Host "[ERROR] JSON not found: $JsonFile" -ForegroundColor Red
    exit 1
}

$repos = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
Write-Host "Total to star: $total"
Write-Host "Starting..." -ForegroundColor Gray

$done = $fail = $already = 0

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 30
        $done++
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 304) { $already++ }
        else {
            $fail++
            Write-Host "[FAIL] $fullName (HTTP $statusCode)"
        }
    }

    if ($done % 100 -eq 0) {
        Write-Host "[$done / $total] Done:$done  Already:$already  Fail:$fail"
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "DONE! Done:$done  Already:$already  Fail:$fail"
Write-Host "========================================"
