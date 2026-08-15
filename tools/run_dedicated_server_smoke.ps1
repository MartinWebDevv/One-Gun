param(
    [int]$TimeoutMilliseconds = 60000
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}

$dataRoot = Join-Path $env:TEMP "one_gun_dedicated_smoke_data"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
$env:APPDATA = $dataRoot
$env:LOCALAPPDATA = $dataRoot

$logs = @{}
$processes = @{}
function Start-OneGunProcess([string]$name, [string]$arguments) {
    $stdout = Join-Path $env:TEMP "one_gun_dedicated_${name}.out.log"
    $stderr = Join-Path $env:TEMP "one_gun_dedicated_${name}.err.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $script:logs[$name] = @($stdout, $stderr)
    $script:processes[$name] = Start-Process -FilePath $godot -ArgumentList $arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -PassThru
}

try {
    Start-OneGunProcess "server" "--headless --path `"$project`" -- --server --port=24756 --max-players=4 --map=res://node_3d.tscn --lobby-name=Dedicated-Smoke"
    Start-Sleep -Milliseconds 750
    Start-OneGunProcess "controller" "--headless --path `"$project`" res://tools/dedicated_client_smoke.tscn -- --role=controller"
    Start-Sleep -Milliseconds 500
    Start-OneGunProcess "guest" "--headless --path `"$project`" res://tools/dedicated_client_smoke.tscn -- --role=guest"

    foreach ($name in @("controller", "guest")) {
        $processes[$name].WaitForExit($TimeoutMilliseconds) | Out-Null
        if (-not $processes[$name].HasExited) {
            throw "$name timed out after $TimeoutMilliseconds ms"
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
foreach ($name in @("server", "controller", "guest")) {
    $combined[$name] = (Get-Content -Raw $logs[$name][0] -ErrorAction SilentlyContinue), `
        (Get-Content -Raw $logs[$name][1] -ErrorAction SilentlyContinue) -join "`n"
    $combined[$name] | Write-Output
}
if ($combined["server"] -notmatch "\[DEDICATED\] Listening on UDP 24756") { exit 1 }
if ($combined["server"] -notmatch "\[DEDICATED\] Lobby runtime restored") { exit 1 }
if ($combined["controller"] -notmatch "DEDICATED_SERVER_PASS controller") { exit 1 }
if ($combined["guest"] -notmatch "DEDICATED_SERVER_PASS guest") { exit 1 }
if ($combined["controller"] -notmatch "DEDICATED_RETURN_PASS controller") { exit 1 }
if ($combined["guest"] -notmatch "DEDICATED_RETURN_PASS guest") { exit 1 }
foreach ($role in @("controller", "guest")) {
    foreach ($marker in @(
        "DEDICATED_INPUT_PICKUP_PASS",
        "DEDICATED_INPUT_FIRE_PASS",
        "DEDICATED_INPUT_DROP_PASS",
        "DEDICATED_MELEE_PICKUP_PASS",
        "DEDICATED_MELEE_SWING_PASS",
        "DEDICATED_MELEE_HIT_PASS",
        "DEDICATED_MELEE_DROP_PASS",
        "DEDICATED_ITEM_PICKUP_PASS",
        "DEDICATED_ITEM_DROP_PASS",
        "DEDICATED_ITEM_THROW_PASS"
    )) {
        if ($combined[$role] -notmatch "$marker $role") { exit 1 }
    }
}
foreach ($request in @(
    "gun pickup", "gun fire", "gun drop",
    "melee pickup", "melee swing", "melee drop",
    "item pickup", "item drop", "item throw"
)) {
    if ($combined["server"] -notmatch "\[DEDICATED ACTION\] $request requested") { exit 1 }
}
if ($combined["server"] -match "\[DEDICATED ACTION\].*rejected.*(matching gun not found|matching melee not found|item \d+ not found)") { exit 1 }
if (($combined.Values -join "`n") -match "pickup aborted: holder has no active .* attachment socket") { exit 1 }
if ($combined["server"] -match "Attempt to disconnect a nonexistent connection") { exit 1 }
if (($combined.Values -join "`n") -match "Failed to get cached node|Node not found: .*NetSync|Ignoring sync data from non-authority or for missing node") { exit 1 }
if ($combined["controller"] -match "on_despawn_receive") { exit 1 }
if ($combined["guest"] -match "on_despawn_receive") { exit 1 }
exit 0
