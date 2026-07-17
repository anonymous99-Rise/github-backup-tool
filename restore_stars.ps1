# GitHub Stars Restorer - Flush版
param(
    [Parameter(Mandatory=$true)]
    [string]$Token
)

$JsonFile = Join-Path $PSScriptRoot "starred_repos.json"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
}

function Write-Flush($msg, $color) {
    if ($color) { Write-Host $msg -ForegroundColor $color }
    else { Write-Host $msg }
    [Console]::Out.Flush()
}

Write-Flush "========================================" "Cyan"
Write-Flush " GitHub Star Restorer" "Cyan"
Write-Flush "========================================" "Cyan"

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
Write-Flush "Account: $($me.login)" "Green"

if (-not (Test-Path $JsonFile)) {
    Write-Flush "[ERROR] JSON not found: $JsonFile" "Red"
    exit 1
}

$repos = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
Write-Flush "Total to star: $total"
Write-Flush "Starting now..."

$done = $fail = $already = 0

foreach ($repo in $repos) {
    $fullName = $repo.full_name
    $parts = $fullName -split '/', 2
    $owner = $parts[0]
    $name = $parts[1]

    try {
        Invoke-RestMethod -Uri "https://api.github.com/user/starred/$owner/$name" `
            -Headers $headers -Method PUT -TimeoutSec 30 | Out-Null
        $done++
    } catch {
        $statusCode = [int]$_.Exception.Response.StatusCode
        if ($statusCode -eq 304) { $already++ }
        else {
            $fail++
            Write-Flush "[FAIL] $fullName (HTTP $statusCode)" "Yellow"
        }
    }

    if ($done % 100 -eq 0) {
        Write-Flush "[$done / $total] Done:$done  Already:$already  Fail:$fail" "Yellow"
    }
}

Write-Flush ""
Write-Flush "========================================" "Green"
Write-Flush "DONE! Done:$done  Already:$already  Fail:$fail" "Green"
Write-Flush "========================================" "Green"
