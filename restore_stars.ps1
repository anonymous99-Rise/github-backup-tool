# GitHub Stars Restorer
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
Write-Host " GitHub Star Restorer"
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

$done = $fail = $already = 0

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
        if ($statusCode -eq 304) { $already++ }
        else {
            $fail++
            Write-Host "[FAIL] $fullName (HTTP $statusCode)"
        }
    }

    if ($done % 100 -eq 0) {
        Write-Host "Progress: $done / $total  done:$done  already:$already  fail:$fail"
    }

    Start-Sleep -Milliseconds 120
}

Write-Host ""
Write-Host "DONE! Done:$done  Already:$already  Failed:$fail"
