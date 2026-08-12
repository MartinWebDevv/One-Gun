param(
    [string]$Map = "res://node_3d.tscn",
    [int]$TimeoutMilliseconds = 45000
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}
$godotData = Join-Path $env:TEMP "one_gun_late_spectator_data"
New-Item -ItemType Directory -Force -Path $godotData | Out-Null
$env:APPDATA = $godotData
$env:LOCALAPPDATA = $godotData
$pathValue = $env:Path
[Environment]::SetEnvironmentVariable("PATH", $null, "Process")
[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")

$processes = @()
$outputs = @{}
foreach ($role in @("host", "client")) {
    $out = Join-Path $env:TEMP "one_gun_late_${role}.out.log"
    $err = Join-Path $env:TEMP "one_gun_late_${role}.err.log"
    $args = "--headless --path `"$project`" res://tools/online_smoke.tscn -- --role=$role --map=$Map --mode=late_spectator"
    $processes += Start-Process -FilePath $godot -ArgumentList $args -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
    $outputs[$role] = @($out, $err)
    Start-Sleep -Milliseconds 500
}

Start-Sleep -Seconds 8
$spectatorOut = Join-Path $env:TEMP "one_gun_late_spectator.out.log"
$spectatorErr = Join-Path $env:TEMP "one_gun_late_spectator.err.log"
$spectatorArgs = "--headless --path `"$project`" res://tools/online_smoke.tscn -- --role=spectator --map=$Map --mode=late_spectator"
$processes += Start-Process -FilePath $godot -ArgumentList $spectatorArgs -RedirectStandardOutput $spectatorOut -RedirectStandardError $spectatorErr -WindowStyle Hidden -PassThru
$outputs["spectator"] = @($spectatorOut, $spectatorErr)

foreach ($process in $processes) {
    $process.WaitForExit($TimeoutMilliseconds) | Out-Null
}
foreach ($process in $processes) {
    if (-not $process.HasExited) { $process.Kill() }
}

$combined = @{}
foreach ($role in @("host", "client", "spectator")) {
    $combined[$role] = (Get-Content -Raw $outputs[$role][0]), (Get-Content -Raw $outputs[$role][1]) -join "`n"
    $combined[$role] | Write-Output
}
foreach ($role in @("host", "client", "spectator")) {
    if ($combined[$role] -notmatch "ONLINE_LATE_SPECTATOR_PASS $role") { exit 1 }
}
exit 0
