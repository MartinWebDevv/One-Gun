$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = "D:\GodotEngine\Godot_v4.6.3-stable_win64.exe"
$pathValue = $env:Path
[Environment]::SetEnvironmentVariable("PATH", $null, "Process")
[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
$localOut = Join-Path $env:TEMP "one_gun_combat_validation.out.log"
$localErr = Join-Path $env:TEMP "one_gun_combat_validation.err.log"
$combatData = Join-Path $env:TEMP "one_gun_combat_validation_data"
New-Item -ItemType Directory -Force -Path $combatData | Out-Null
$env:APPDATA = $combatData
$env:LOCALAPPDATA = $combatData

Write-Host "FAST LOCAL COMBAT VALIDATION"
$local = Start-Process -FilePath $godot `
    -ArgumentList "--headless --path `"$project`" --scene res://tools/combat_rules_validation.tscn" `
    -RedirectStandardOutput $localOut -RedirectStandardError $localErr `
    -WindowStyle Hidden -Wait -PassThru
$localOutput = (Get-Content -Raw $localOut), (Get-Content -Raw $localErr) -join "`n"
$localOutput
if ($local.ExitCode -ne 0 -or $localOutput -notmatch "COMBAT RULES VALIDATION: PASS") {
    throw "Fast local combat validation failed. Review the reported rule before changing implementation."
}

Write-Host "FULL TWO-INSTANCE ONLINE VALIDATION"
& (Join-Path $PSScriptRoot "run_online_smoke.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "Two-instance online validation failed. Review whether the test or gameplay behavior is wrong before correcting it."
}
