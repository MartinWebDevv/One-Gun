param(
    [switch]$IncludeOnline
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}
$godotData = Join-Path $env:TEMP "one_gun_high_priority_validation_data"
New-Item -ItemType Directory -Force -Path $godotData | Out-Null
$env:APPDATA = $godotData
$env:LOCALAPPDATA = $godotData
$pathValue = $env:Path
[Environment]::SetEnvironmentVariable("PATH", $null, "Process")
[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")

function Invoke-OneGunValidation {
    param(
        [string]$GodotArguments,
        [string]$ExpectedText,
        [string]$Label
    )
    $safeLabel = $Label -replace '[^A-Za-z0-9_-]', '_'
    $logPath = Join-Path $env:TEMP "one_gun_${safeLabel}.log"
    $arguments = "$GodotArguments --log-file `"$logPath`""
    $process = Start-Process -FilePath $godot -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    $output = Get-Content -Raw -LiteralPath $logPath -ErrorAction SilentlyContinue
    $output | Write-Output
    if ($process.ExitCode -ne 0 -or $output -notmatch [regex]::Escape($ExpectedText)) {
        throw "Validation failed: $Label"
    }
}

$scenes = @(
    "res://tools/player_capacity_validation.tscn",
    "res://tools/high_priority_09_18_validation.tscn"
)

foreach ($scene in $scenes) {
    $expected = if ($scene -like "*player_capacity*") { "PLAYER CAPACITY VALIDATION: PASS" } else { "HIGH PRIORITY 09-18 VALIDATION: PASS" }
    Invoke-OneGunValidation "--headless --path `"$project`" $scene" $expected ($scene -replace 'res://tools/', '')
}

Invoke-OneGunValidation "--headless --path `"$project`" --script res://tools/menu_systems_validation.gd" "MENU SYSTEMS VALIDATION: PASS" "menu_systems_validation"
$env:ONEGUN_MIGRATION_SPLIT = "0"
Invoke-OneGunValidation "--headless --path `"$project`" --scene res://tools/godot_47_migration_validation.tscn --fixed-fps 60 --quit-after 600" "GODOT 4.7 MIGRATION VALIDATION (SOLO): PASS" "godot_47_migration_solo"
$env:ONEGUN_MIGRATION_SPLIT = "1"
Invoke-OneGunValidation "--headless --path `"$project`" --scene res://tools/godot_47_migration_validation.tscn --fixed-fps 60 --quit-after 600" "GODOT 4.7 MIGRATION VALIDATION (SPLITSCREEN): PASS" "godot_47_migration_splitscreen"
Remove-Item Env:ONEGUN_MIGRATION_SPLIT -ErrorAction SilentlyContinue

if ($IncludeOnline) {
    $onlineRunner = Join-Path $PSScriptRoot "run_online_smoke.ps1"
    $lobbyOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $onlineRunner -Mode lobby -TimeoutMilliseconds 150000 2>&1
    $lobbyOutput | Write-Output
    $lobbyText = $lobbyOutput -join "`n"
    if ($lobbyText -notmatch "ONLINE_LOBBY_PASS host" -or $lobbyText -notmatch "ONLINE_LOBBY_PASS client") {
        throw "Online lobby smoke failed"
    }
    $matchOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $onlineRunner -Mode match -TimeoutMilliseconds 45000 2>&1
    $matchOutput | Write-Output
	$matchText = $matchOutput -join "`n"
	if ($matchText -notmatch "ONLINE_SMOKE_PASS host" -or $matchText -notmatch "ONLINE_SMOKE_PASS client") {
		throw "Online match smoke failed"
	}
	foreach ($mode in @("online_bots", "overtime")) {
		$modeOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $onlineRunner -Mode $mode -TimeoutMilliseconds 45000 2>&1
		$modeOutput | Write-Output
		$modeText = $modeOutput -join "`n"
		$modePrefix = if ($mode -eq "online_bots") { "ONLINE_BOTS_PASS" } else { "ONLINE_OVERTIME_PASS" }
		if ($modeText -notmatch "$modePrefix host" -or $modeText -notmatch "$modePrefix client") {
			throw "Online $mode smoke failed"
		}
	}
	$lateRunner = Join-Path $PSScriptRoot "run_online_late_spectator.ps1"
	$lateOutput = powershell -NoProfile -ExecutionPolicy Bypass -File $lateRunner -TimeoutMilliseconds 45000 2>&1
	$lateOutput | Write-Output
	$lateText = $lateOutput -join "`n"
	foreach ($role in @("host", "client", "spectator")) {
		if ($lateText -notmatch "ONLINE_LATE_SPECTATOR_PASS $role") {
			throw "Online late-spectator smoke failed for $role"
		}
	}
}

Write-Output "HIGH PRIORITY 09-18 SUITE: PASS"
