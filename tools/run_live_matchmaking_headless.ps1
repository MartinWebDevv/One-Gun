param(
    [string]$CoordinatorUrl = "https://one-gun-match-coordinator-dev.one-gun-dev.workers.dev",
    [int]$TimeoutMilliseconds = 260000
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}
if ($CoordinatorUrl -notmatch "^https://[A-Za-z0-9.-]+$") {
    throw "CoordinatorUrl must be an HTTPS origin without a path."
}

$logs = @{}
$processes = @{}
function Start-LiveClient([string]$role) {
    $stdout = Join-Path $env:TEMP "one_gun_live_matchmaking_${role}.out.log"
    $stderr = Join-Path $env:TEMP "one_gun_live_matchmaking_${role}.err.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $script:logs[$role] = @($stdout, $stderr)
    $arguments = "--headless --path `"$project`" res://tools/live_matchmaking_headless.tscn -- --role=$role --url=$CoordinatorUrl"
    $script:processes[$role] = Start-Process -FilePath $godot -ArgumentList $arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -PassThru
}

try {
    Start-LiveClient "controller"
    Start-Sleep -Milliseconds 500
    Start-LiveClient "guest"
    foreach ($role in @("controller", "guest")) {
        $processes[$role].WaitForExit($TimeoutMilliseconds) | Out-Null
        if (-not $processes[$role].HasExited) {
            throw "$role timed out after $TimeoutMilliseconds ms"
        }
    }
}
finally {
    foreach ($process in $processes.Values) {
        if ($null -ne $process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
    }
}

$combined = @{}
foreach ($role in @("controller", "guest")) {
    $combined[$role] = (Get-Content -Raw $logs[$role][0] -ErrorAction SilentlyContinue), `
        (Get-Content -Raw $logs[$role][1] -ErrorAction SilentlyContinue) -join "`n"
    $combined[$role] | Write-Output
    Write-Output "Headless $role process exit code: $($processes[$role].ExitCode)"
    if ($combined[$role] -notmatch "LIVE_MATCHMAKING_HEADLESS_PASS $role" -or
            $combined[$role] -match "LIVE_MATCHMAKING_HEADLESS_FAIL $role") {
        exit 1
    }
    if ($processes[$role].ExitCode -ne 0) {
        Write-Warning "$role returned a nonzero code after its live success marker; inspect its shutdown diagnostics above."
    }
}

$endpointPattern = "endpoint=([A-Za-z0-9.-]+:[0-9]+)"
$controllerEndpoint = [regex]::Match($combined["controller"], $endpointPattern).Groups[1].Value
$guestEndpoint = [regex]::Match($combined["guest"], $endpointPattern).Groups[1].Value
if ([string]::IsNullOrWhiteSpace($controllerEndpoint) -or
        $controllerEndpoint -ne $guestEndpoint) {
    throw "Headless clients did not verify the same public endpoint."
}

Write-Output "LIVE MATCHMAKING GODOT SMOKE: PASS"
Write-Output "Assigned deployment endpoint: $controllerEndpoint"
exit 0
