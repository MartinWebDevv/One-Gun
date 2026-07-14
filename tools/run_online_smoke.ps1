param(
    [string]$Map = "res://node_3d.tscn",
    [int]$TimeoutMilliseconds = 30000,
    [ValidateSet("match", "lobby", "named_lobby", "exit_flow", "client_exit", "online_bots")]
    [string]$Mode = "match",
    [switch]$Rendered
)

$ErrorActionPreference = "Stop"

$godot = "D:\GodotEngine\Godot_v4.6.3-stable_win64.exe"
$project = Split-Path -Parent $PSScriptRoot
$pathValue = $env:Path
[Environment]::SetEnvironmentVariable("PATH", $null, "Process")
[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
$godotData = Join-Path $env:TEMP "one_gun_godot_smoke_data"
New-Item -ItemType Directory -Force -Path $godotData | Out-Null
$env:APPDATA = $godotData
$env:LOCALAPPDATA = $godotData

$hostOut = Join-Path $env:TEMP "one_gun_online_smoke_host.out.log"
$hostErr = Join-Path $env:TEMP "one_gun_online_smoke_host.err.log"
$clientOut = Join-Path $env:TEMP "one_gun_online_smoke_client.out.log"
$clientErr = Join-Path $env:TEMP "one_gun_online_smoke_client.err.log"
$displayArg = if ($Rendered) { "" } else { "--headless " }
$hostArgs = "${displayArg}--path `"$project`" --scene res://tools/online_smoke.tscn -- --role=host --map=$Map --mode=$Mode"
$clientArgs = "${displayArg}--path `"$project`" --scene res://tools/online_smoke.tscn -- --role=client --map=$Map --mode=$Mode"

$hostProcess = Start-Process -FilePath $godot -ArgumentList $hostArgs -RedirectStandardOutput $hostOut -RedirectStandardError $hostErr -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 500
$clientProcess = Start-Process -FilePath $godot -ArgumentList $clientArgs -RedirectStandardOutput $clientOut -RedirectStandardError $clientErr -WindowStyle Hidden -PassThru

$hostProcess.WaitForExit($TimeoutMilliseconds) | Out-Null
$clientProcess.WaitForExit($TimeoutMilliseconds) | Out-Null
if (-not $hostProcess.HasExited) { $hostProcess.Kill() }
if (-not $clientProcess.HasExited) { $clientProcess.Kill() }

$hostOutput = (Get-Content -Raw $hostOut), (Get-Content -Raw $hostErr) -join "`n"
$clientOutput = (Get-Content -Raw $clientOut), (Get-Content -Raw $clientErr) -join "`n"
$hostOutput
$clientOutput

$passPrefix = if ($Mode -eq "lobby") { "ONLINE_LOBBY_PASS" } elseif ($Mode -eq "named_lobby") { "ONLINE_NAMED_LOBBY_PASS" } elseif ($Mode -eq "exit_flow") { "ONLINE_EXIT_FLOW_PASS" } elseif ($Mode -eq "client_exit") { "ONLINE_CLIENT_EXIT_PASS" } elseif ($Mode -eq "online_bots") { "ONLINE_BOTS_PASS" } else { "ONLINE_SMOKE_PASS" }
if ($hostOutput -notmatch "$passPrefix host" -or $clientOutput -notmatch "$passPrefix client") {
	exit 1
}
