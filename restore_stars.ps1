# GitHub Stars Restorer - 实时日志版
param(
    [Parameter(Mandatory=$true)]
    [string]$Token
)

$JsonFile = Join-Path $PSScriptRoot "starred_repos.json"
$LogFile = Join-Path $PSScriptRoot "restore.log"

$headers = @{
    "Authorization" = "token $Token"
    "Accept" = "application/vnd.github.v3+json"
}

# 清空日志
"" | Out-File $LogFile -Encoding UTF8

function Log($msg, $color) {
    $ts = Get-Date -Format "HH:mm:ss"
    $line = "[$ts] $msg"
    $line | Out-File $LogFile -Append -Encoding UTF8
    if ($color) { Write-Host $line -ForegroundColor $color }
    else { Write-Host $line }
}

Log "========================================" "Cyan"
Log " GitHub Star Restorer" "Cyan"
Log "========================================" "Cyan"

$me = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method GET -TimeoutSec 10
Log "Account: $($me.login)" "Green"

if (-not (Test-Path $JsonFile)) {
    Log "[ERROR] JSON not found: $JsonFile" "Red"
    exit 1
}

$repos = Get-Content $JsonFile -Encoding UTF8 | ConvertFrom-Json
$total = $repos.Count
Log "Total to star: $total"
Log "Log: $LogFile"
Log "Starting..."

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
            Log "[FAIL] $fullName (HTTP $statusCode)" "Yellow"
        }
    }

    if ($done % 10 -eq 0) {
        Log "[$done / $total] Done:$done  Already:$already  Fail:$fail" "Gray"
    }
}

Log ""
Log "========================================" "Green"
Log "DONE! Done:$done  Already:$already  Fail:$fail" "Green"
Log "========================================" "Green"
