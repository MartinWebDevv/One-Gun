param(
    [int]$TimeoutMilliseconds = 20000,
    [int]$Port = 24757
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}

$dataRoot = Join-Path $env:TEMP "one_gun_version_mismatch_smoke_data"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
$env:APPDATA = $dataRoot
$env:LOCALAPPDATA = $dataRoot

$serverOut = Join-Path $env:TEMP "one_gun_version_mismatch_server.out.log"
$serverErr = Join-Path $env:TEMP "one_gun_version_mismatch_server.err.log"
$clientOut = Join-Path $env:TEMP "one_gun_version_mismatch_client.out.log"
$clientErr = Join-Path $env:TEMP "one_gun_version_mismatch_client.err.log"
Remove-Item -LiteralPath $serverOut, $serverErr, $clientOut, $clientErr -Force -ErrorAction SilentlyContinue

$server = $null
$client = $null
try {
    $serverArgs = "--headless --path `"$project`" -- --server --port=$Port --max-players=4 --map=res://node_3d.tscn --lobby-name=Version-Mismatch-Smoke"
    $server = Start-Process -FilePath $godot -ArgumentList $serverArgs `
        -RedirectStandardOutput $serverOut -RedirectStandardError $serverErr `
        -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 750

    $clientArgs = "--headless --path `"$project`" res://tools/version_mismatch_client.tscn -- --port=$Port"
    $client = Start-Process -FilePath $godot -ArgumentList $clientArgs `
        -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr `
        -WindowStyle Hidden -PassThru
    $client.WaitForExit($TimeoutMilliseconds) | Out-Null
    if (-not $client.HasExited) {
        throw "mismatched client timed out after $TimeoutMilliseconds ms"
    }
    $client.WaitForExit()
}
finally {
    foreach ($process in @($client, $server)) {
        if ($null -ne $process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
    }
}

$serverLog = (Get-Content -Raw $serverOut -ErrorAction SilentlyContinue), `
    (Get-Content -Raw $serverErr -ErrorAction SilentlyContinue) -join "`n"
$clientLog = (Get-Content -Raw $clientOut -ErrorAction SilentlyContinue), `
    (Get-Content -Raw $clientErr -ErrorAction SilentlyContinue) -join "`n"
$serverLog | Write-Output
$clientLog | Write-Output

if ($serverLog -notmatch "\[DEDICATED\] Listening on UDP $Port") { throw "server did not listen on UDP $Port" }
if ($serverLog -notmatch "rejected \| reason network_protocol") { throw "server did not log the protocol rejection" }
if ($serverLog -match "admitted \| client build") { throw "mismatched client was admitted to the roster" }
if ($serverLog -match "SCRIPT ERROR|disconnect_peer") { throw "server logged an error while removing the rejected peer" }
if ($clientLog -notmatch "VERSION_MISMATCH_CLIENT_PASS reason=network_protocol") { throw "client did not complete the mismatch flow" }

Write-Output "VERSION MISMATCH SMOKE: PASS"
