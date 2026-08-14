param(
    [int]$TimeoutMilliseconds = 70000
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $project "Godot_v4.7.1-stable_win64.exe"
if (-not (Test-Path -LiteralPath $godot)) {
    throw "Godot 4.7.1 executable not found at $godot"
}

$port = 24758
$ticketA = "smoketicketa"
$ticketB = "smoketicketb"
$dataRoot = Join-Path $env:TEMP "one_gun_match_server_smoke_data"
New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
$env:APPDATA = $dataRoot
$env:LOCALAPPDATA = $dataRoot

$logs = @{}
$processes = @{}
function Start-OneGunProcess([string]$name, [string]$arguments) {
    $stdout = Join-Path $env:TEMP "one_gun_match_server_${name}.out.log"
    $stderr = Join-Path $env:TEMP "one_gun_match_server_${name}.err.log"
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    $script:logs[$name] = @($stdout, $stderr)
    $script:processes[$name] = Start-Process -FilePath $godot -ArgumentList $arguments `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -PassThru
}

try {
    $env:MM_MATCH_ID = "onegun-smoke-match"
    $env:MM_MATCH_PROFILE = "simple-example"
    $env:MM_EXPANSION_STAGE = "initial"
    $env:MM_TICKET_IDS = ConvertTo-Json @($ticketA, $ticketB) -Compress
    Set-Item -Path "Env:MM_TICKET_$ticketA" -Value `
        (ConvertTo-Json @{ id = $ticketA; player_ip = "127.0.0.1"; attributes = @{} } -Compress)
    Set-Item -Path "Env:MM_TICKET_$ticketB" -Value `
        (ConvertTo-Json @{ id = $ticketB; player_ip = "127.0.0.1"; attributes = @{} } -Compress)
    Start-OneGunProcess "server" "--headless --path `"$project`" -- --server --port=$port --max-players=4 --map=res://node_3d.tscn --lobby-name=Match-Server-Smoke"
    Remove-Item Env:MM_MATCH_ID, Env:MM_MATCH_PROFILE, Env:MM_EXPANSION_STAGE, `
        Env:MM_TICKET_IDS, "Env:MM_TICKET_$ticketA", "Env:MM_TICKET_$ticketB" `
        -ErrorAction SilentlyContinue

    Start-Sleep -Milliseconds 900
    Start-OneGunProcess "intruder" "--headless --path `"$project`" res://tools/match_ticket_rejection_client.tscn -- --port=$port"
    $processes["intruder"].WaitForExit(15000) | Out-Null
    if (-not $processes["intruder"].HasExited) {
        throw "invalid-ticket client timed out"
    }

    Start-OneGunProcess "controller" "--headless --path `"$project`" res://tools/dedicated_client_smoke.tscn -- --role=controller --match-server --ticket=$ticketA --port=$port"
    Start-Sleep -Milliseconds 500
    Start-OneGunProcess "guest" "--headless --path `"$project`" res://tools/dedicated_client_smoke.tscn -- --role=guest --match-server --ticket=$ticketB --port=$port"

    foreach ($name in @("controller", "guest")) {
        $processes[$name].WaitForExit($TimeoutMilliseconds) | Out-Null
        if (-not $processes[$name].HasExited) {
            throw "$name timed out after $TimeoutMilliseconds ms"
        }
    }
}
finally {
    Remove-Item Env:MM_MATCH_ID, Env:MM_MATCH_PROFILE, Env:MM_EXPANSION_STAGE, `
        Env:MM_TICKET_IDS, "Env:MM_TICKET_$ticketA", "Env:MM_TICKET_$ticketB" `
        -ErrorAction SilentlyContinue
    foreach ($process in $processes.Values) {
        if ($null -ne $process -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
    }
}

$combined = @{}
foreach ($name in @("server", "intruder", "controller", "guest")) {
    $combined[$name] = (Get-Content -Raw $logs[$name][0] -ErrorAction SilentlyContinue), `
        (Get-Content -Raw $logs[$name][1] -ErrorAction SilentlyContinue) -join "`n"
    $combined[$name] | Write-Output
}
if ($combined["server"] -notmatch "\[MATCH SERVER\] Assignment accepted \| expected players 2") { exit 1 }
if ($combined["server"] -notmatch "reason match_ticket_invalid") { exit 1 }
if ($combined["intruder"] -notmatch "MATCH_TICKET_REJECTION_PASS reason=match_ticket_invalid") { exit 1 }
if ($combined["server"] -notmatch "match participant admitted \(2/2 assigned tickets\)") { exit 1 }
if ($combined["server"] -notmatch "match 1 ready peer .*\(2/2\)") { exit 1 }
foreach ($role in @("controller", "guest")) {
    if ($combined[$role] -notmatch "MATCH_SERVER_ACTIONS_PASS $role") { exit 1 }
    foreach ($marker in @(
        "DEDICATED_INPUT_PICKUP_PASS",
        "DEDICATED_INPUT_FIRE_PASS",
        "DEDICATED_INPUT_DROP_PASS",
        "DEDICATED_MELEE_PICKUP_PASS",
        "DEDICATED_MELEE_SWING_PASS",
        "DEDICATED_MELEE_DROP_PASS",
        "DEDICATED_ITEM_PICKUP_PASS",
        "DEDICATED_ITEM_DROP_PASS",
        "DEDICATED_ITEM_ACTION_PASS"
    )) {
        if ($combined[$role] -notmatch "$marker $role") { exit 1 }
    }
}
foreach ($request in @(
    "gun pickup", "gun fire", "gun drop",
    "melee pickup", "melee swing", "melee drop",
    "item pickup", "item drop"
)) {
    if ($combined["server"] -notmatch "\[DEDICATED ACTION\] $request requested") { exit 1 }
}
if ($combined["server"] -notmatch "\[DEDICATED ACTION\] item (throw|photo|activate_shoes) requested") { exit 1 }
if (($combined.Values -join "`n") -match "Failed to get cached node|Node not found: .*NetSync|Ignoring sync data from non-authority or for missing node") { exit 1 }
if (($combined.Values -join "`n") -match "MATCH_TICKET_REJECTION_FAIL|DEDICATED_SERVER_FAIL") { exit 1 }
"MATCH SERVER SMOKE: PASS"
exit 0