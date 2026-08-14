# Dynamic Match Deployment

This document defines the Phase 11 security boundary and migration path for per-match One Gun servers. It is intentionally provider-neutral at the game-code boundary. The current persistent development deployment remains the default until every stage below is verified.

## Current verified flow

Today one Edgegap deployment performs both jobs:

```text
Windows clients
    -> Edgegap onegun-dev/dev
    -> Godot lobby
    -> same Godot process changes to the selected map
    -> match
    -> same process returns to the lobby
```

`NetworkManager.begin_prelaunch()` runs the three-second countdown and `NetworkManager.start_game()` changes every peer, including the dedicated server, to the selected map. No endpoint migration occurs. This path is working and must remain available while dynamic deployment is developed.

## Why a coordinator is required

A lobby server cannot replace itself with a match server and still tell its connected clients where the new server is. The production flow therefore needs a coordination service that remains reachable while an Edgegap match deployment starts.

The Edgegap organization API token is privileged account access. It must exist only in a trusted coordinator or CI environment. It must never be committed, exported into `OneGun.pck`, injected into a Windows client build, printed in logs, or sent through an ENet RPC.

The coordinator, not a game client, owns these operations:

- choose an allowlisted Edgegap application and version;
- request exactly one deployment for an authenticated lobby;
- pass player placement data to Edgegap;
- inject sanitized match bootstrap data into the deployment;
- wait for `READY` or consume a readiness webhook;
- return the FQDN and dynamic external UDP port;
- stop abandoned or completed deployments;
- enforce authentication, rate limits, idempotency, capacity, and timeouts.

One Gun clients receive only a short-lived lobby/session credential, a one-time match ticket, and the assigned public endpoint. They never receive the Edgegap organization API token or registry credentials.

## Recommended development architecture

Use Edgegap Matchmaker as the always-available assignment/deployment layer, with a small game-backend proxy in front of it when player authentication and abuse controls are added:

```text
One Gun client
    -> authenticated lobby/coordinator
       -> Edgegap Matchmaker or Deployments API
          -> onegun-dev/dev match deployment

coordinator
    <- READY + FQDN + external UDP port
    -> endpoint + one-time match ticket to lobby members

clients
    -> disconnect from lobby ENet peer
    -> connect to assigned ENet/UDP endpoint
    -> send build/protocol + match ticket
```

Edgegap Matchmaker manages ready/group state and server assignment, but it is not a replacement for One Gun's rich lobby state. Map choice, bots, match rules, skins, privacy, invites, and controller ownership still need a lobby service. A matchmaker group can reference that lobby and begin assignment after the lobby owner starts the match.

The current Edgegap free tier permits only one active game deployment. That is enough for one match server if the lobby/coordinator is not itself using the account's only game-deployment slot. It is not enough to keep the current Godot lobby deployment alive while starting a second match deployment. Therefore the final cutover requires moving pre-match coordination out of the current `onegun-dev/dev` Godot process.

## Backend contract

The exact transport may be Edgegap's generated Matchmaker API or a small HTTPS proxy, but One Gun should depend on these concepts rather than Edgegap management endpoints.

### Create match

The authenticated lobby owner asks the coordinator to start one match. The coordinator derives the lobby identity from authentication rather than trusting arbitrary application/version values supplied by the client.

Conceptual request:

```json
{
  "schema": 1,
  "idempotency_key": "lobby-id:launch-generation",
  "game": {
    "version": "0.0.4",
    "protocol": 2,
    "build_id": "dev-a83f91c"
  },
  "map": "res://maps/test/ForestMap.tscn",
  "player_count": 4,
  "match_config": {}
}
```

The request deliberately contains no Edgegap application name, Edgegap version name, registry identity, API token, or arbitrary deployment tags. Those are server-side allowlisted configuration.

### Read assignment

Clients may poll with exponential backoff or receive a lobby notification. A ready response has the actual external port assigned by Edgegap:

```json
{
  "schema": 1,
  "match_id": "opaque-match-id",
  "state": "ready",
  "endpoint": {
    "host": "request-id.pr.edgegap.net",
    "port": 30937,
    "transport": "enet_udp"
  },
  "ticket": "short-lived-one-time-ticket"
}
```

Valid states are `queued`, `deploying`, `ready`, `failed`, and `expired`. Clients must not substitute internal port `24545` when the external mapping is absent.

### Match-server bootstrap

Edgegap Matchmaker injects read-only assignment variables into the Linux deployment. `match_server_context.gd` activates only when `MM_MATCH_ID` is present and parses the documented `MM_MATCH_PROFILE`, `MM_EXPANSION_STAGE`, `MM_TICKET_IDS`, per-ticket `MM_TICKET_<ticketId>`, `MM_GROUPS`, `MM_TEAMS`, `MM_INTERSECTION`, and `MM_EQUALITY` values. The context contains assignment metadata only; it contains no Edgegap organization token, Matchmaker auth token, or registry credential.

The implemented match-server mode:

- starts ENet on internal UDP `24545`;
- loads the allowlisted `--map` directly without exposing the editable lobby;
- admits only ticket IDs present in the assignment and claims each ticket once;
- verifies `GAME_VERSION` and `NETWORK_PROTOCOL` before spawning an actor;
- rejects missing, unknown, duplicate, and replayed tickets before roster admission;
- keeps raw ticket IDs server-only and out of normal logs/roster replication;
- waits for every assigned participant before completing scene readiness;
- prints a clear `[MATCH SERVER]` error and terminates with a nonzero exit code when active Matchmaker assignment data is invalid.

An ordinary `--server` launch with no `MM_MATCH_ID` continues to use the existing persistent lobby-and-match flow. Match completion reporting, sanitized map/rules injection, deployment cleanup, and automatic client endpoint migration remain coordinator work.

## Migration stages and gates

1. **Current fallback (verified):** `onegun-dev/dev` remains a persistent lobby-and-match server deployed by pushes to `main`.
2. **Matchmaker sandbox (verified):** the development Matchmaker API, two-ticket assignment, dynamic external UDP endpoint, and public ENet connection all pass.
3. **Coordinator contract (next):** add an authenticated proxy or lobby service, server-side application/version allowlists, idempotency, rate limiting, and deployment cleanup. Test it locally with fake Edgegap responses before using a real token.
4. **Match-server boot (locally verified):** a valid `MM_*` assignment starts directly in the map, requires one assigned ticket per client, and passes two-client movement/combat coverage. Normal Windows and ordinary `--server` behavior remain unchanged.
5. **Endpoint migration:** have lobby clients show a transfer/loading state, disconnect, connect to the assigned endpoint with their one-time ticket, and recover gracefully on timeout.
6. **Development cutover:** enable dynamic deployment only behind an explicit development feature flag. Retain direct endpoint entry as the emergency fallback.
7. **Production hardening:** add real player authentication, replay protection, metrics, cleanup webhooks, reconnect policy, and a no-kill deployment/version rollout policy.

Do not advance a stage until its preceding layer passes locally and then on Edgegap.

## Secrets

The shipped client must never contain:

```text
EDGEGAP_API_TOKEN
EDGEGAP_GHCR_TOKEN
registry credentials
Butler credentials
coordinator signing keys
```

The Edgegap Matchmaker API uses a separate limited auth token, but One Gun will still keep it behind the trusted coordinator. It will not be committed, stamped into build metadata, or shipped in `OneGun.exe`/`OneGun.pck`. The coordinator returns only the assigned endpoint and the individual one-time ticket required by the game server.

## Development Matchmaker sandbox

The free development instance was created on 2026-08-14:

```text
Name: onegun-matchmaker-dev
Service: Matchmaker 3.2.5
API: https://om-te7fpgo2ru.edgegap.net
Profile: simple-example
Application/version: onegun-dev/dev
Team count: 1
Minimum team size: 2
Maximum team size: 2
```

The generated OpenAPI 3.0.1 document confirms the required lifecycle: create two `/tickets`, poll `/tickets/{ticketId}`, wait for `HOST_ASSIGNED`, then read `assignment.fqdn` and `assignment.ports.gameport.external`. The Matchmaker uses its separate `Authorization` header. The development script `tools/run_edgegap_matchmaker_smoke.ps1` implements that exact contract and validates that `gameport` maps external UDP to internal port `24545`.

Run its credential-free contract check locally:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_edgegap_matchmaker_smoke.ps1 `
    -ApiUrl "https://om-te7fpgo2ru.edgegap.net" `
    -ValidateOnly
```

Expected output:

```text
EDGEGAP MATCHMAKER CONTRACT: PASS
```

For a live sandbox test, first terminate the current persistent `onegun-dev/dev` deployment because the free Edgegap plan permits only one active game deployment. Keep the Matchmaker itself online. Set its separate auth token only in the current PowerShell process:

```powershell
$credential = [pscredential]::new(
    "matchmaker",
    (Read-Host "Temporary Matchmaker auth token" -AsSecureString)
)
$env:ONEGUN_MATCHMAKER_TOKEN = $credential.GetNetworkCredential().Password

try {
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_edgegap_matchmaker_smoke.ps1 `
        -ApiUrl "https://om-te7fpgo2ru.edgegap.net"
}
finally {
    Remove-Item Env:\ONEGUN_MATCHMAKER_TOKEN -ErrorAction SilentlyContinue
    Remove-Variable credential -ErrorAction SilentlyContinue
}
```

The script cancels tickets if the test fails. On success it deliberately leaves the assigned deployment running so a normal Windows client can connect to the printed FQDN and external UDP port. Terminate that test deployment in Edgegap when verification is complete. The sample beacon values are suitable only for proving the generated API contract; production placement must use measured player latency or trusted player location data.

The live sandbox gate passed on 2026-08-14. Two tickets advanced through `SEARCHING`, `MATCH_FOUND`, and `HOST_ASSIGNED`, received the same dynamic endpoint, and mapped external UDP `31983` to internal UDP `24545`. The assigned server started build `dev-42bd2ca`; a matching Windows client connected, passed compatibility admission, loaded City, and produced an authoritative `gun fire requested` action. That deployed build still used the ordinary lobby admission path, so this live test proves Matchmaker assignment and the public ENet endpoint without claiming live ticket admission.

The ticket-aware server path is covered locally with synthetic, non-secret Matchmaker assignment data:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_match_server_smoke.ps1
```

Expected result:

```text
MATCH SERVER SMOKE: PASS
```

This test starts one match server, proves an unknown ticket is rejected, admits two distinct assigned tickets, waits for both participants, and completes movement plus gun/melee/item action coverage. A final live gate will exercise this protocol-2 ticket path after the coordinator can securely deliver each player's ticket and assigned endpoint.

## Phase 11 checkpoint

Dynamic deployment is now isolated rather than globally enabled. The persistent `onegun-dev/dev` server remains the default and direct endpoint fallback. When documented `MM_*` assignment variables are present, the Linux server starts the ticket-aware match path and fails closed on malformed data. Matchmaker contract validation, live assignment/public UDP, and local two-ticket gameplay now pass. The next layer is the trusted coordinator and client transfer state; no privileged Edgegap or Matchmaker token will be placed in the shipped client.