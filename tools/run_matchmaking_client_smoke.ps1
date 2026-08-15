param([int]$Port = 24810)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
$fake = Join-Path $PSScriptRoot "fake_match_coordinator.mjs"
if (-not (Test-Path -LiteralPath $godot)) { throw "Godot 4.7.1 executable not found at $godot" }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "Node.js is required for the local fake coordinator" }

$fakeOut = Join-Path $env:TEMP "one_gun_fake_coordinator.out.log"
$fakeErr = Join-Path $env:TEMP "one_gun_fake_coordinator.err.log"
$clientOut = Join-Path $env:TEMP "one_gun_matchmaking_client.out.log"
$clientErr = Join-Path $env:TEMP "one_gun_matchmaking_client.err.log"
Remove-Item -LiteralPath $fakeOut, $fakeErr, $clientOut, $clientErr -Force -ErrorAction SilentlyContinue

$server = $null
try {
    $server = Start-Process -FilePath "node" -ArgumentList "`"$fake`" --port=$Port" `
        -RedirectStandardOutput $fakeOut -RedirectStandardError $fakeErr -WindowStyle Hidden -PassThru
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        if ((Get-Content -LiteralPath $fakeOut -Raw -ErrorAction SilentlyContinue) -match "FAKE_MATCH_COORDINATOR_READY") { break }
        if ($server.HasExited) { throw "Fake coordinator exited before becoming ready" }
        Start-Sleep -Milliseconds 100
    }
    if ((Get-Content -LiteralPath $fakeOut -Raw -ErrorAction SilentlyContinue) -notmatch "FAKE_MATCH_COORDINATOR_READY") {
        throw "Fake coordinator did not become ready"
    }
    $client = Start-Process -FilePath $godot `
        -ArgumentList "--headless --path `"$project`" res://tools/matchmaking_client_smoke.tscn -- --port=$Port" `
        -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru -Wait
    $combined = (Get-Content -LiteralPath $clientOut -Raw -ErrorAction SilentlyContinue), `
        (Get-Content -LiteralPath $clientErr -Raw -ErrorAction SilentlyContinue) -join "`n"
    $combined | Write-Output
    if ($client.ExitCode -ne 0 -or $combined -notmatch "MATCHMAKING CLIENT CONTRACT: PASS") { exit 1 }
    "MATCHMAKING CLIENT SMOKE: PASS"
}
finally {
    if ($null -ne $server -and -not $server.HasExited) {
        $server.Kill()
        $server.WaitForExit(5000) | Out-Null
    }
}
