# One Gun Deployment

This document records the deployment pipeline as each layer is verified. Phases 1–7 established the Godot 4.7.1 dedicated-server runtime, Linux export, Docker image, build metadata, GHCR publication, public Edgegap UDP deployment, and automatic development-server replacement. Phase 8 verified restricted itch.io distribution and Butler updates. GitHub Actions client publishing is the next checkpoint.

## Local dedicated server

From PowerShell in the repository root:

```powershell
& ".\Godot_v4.7.1-stable_win64.exe" --headless --path "." -- --server --port=24545 --max-players=10 --lobby-name=OneGun-Dev --map=res://maps/test/ForestMap.tscn
```

The `--` separator is significant: arguments after it are passed to One Gun instead of the Godot engine. `--server` is never enabled by a normal desktop launch.

Supported server arguments:

- `--port=<1-65535>`; default `24545` UDP.
- `--max-players=<2-10>`; default `10` remote humans.
- `--lobby-name=<name>`; default `OneGun-Dev`.
- `--map=<res:// path>`; default `res://maps/test/ForestMap.tscn`.

Expected startup output includes the game version, network protocol, UDP listening port, maximum players, lobby name, and initial map. Invalid arguments, a missing map, or an ENet bind failure terminate with an explicit error.

The dedicated process has no local human actor. The first compatible client becomes lobby controller and can edit match settings, manage the roster, and start the match. If that player leaves, control moves to the next connected lobby peer. The dedicated process remains the ENet and gameplay authority. The Playpen is unavailable in dedicated sessions for Phase 1.

## Connect a local client

1. Leave the server command running.
2. Start One Gun normally from the editor or run `& ".\Godot_v4.7.1-stable_win64.exe" --path "."` in a second PowerShell window.
3. Open **ONLINE PLAY**.
4. In the join field, enter `127.0.0.1` and select **JOIN**.
5. Confirm the client reaches the online lobby and is shown as the lobby controller.
6. Connect a second client the same way, set it Ready, then start the match from the controller client.

Success means both clients load the selected map, the server logs both scene-ready reports, and the match reaches live combat with two remote human actors.

Rendered-client verification passed on 2026-08-12: a normal Windows client joined the headless server at 127.0.0.1:24545, entered the online lobby, and received lobby-controller controls.

## Automated dedicated-server smoke test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_dedicated_server_smoke.ps1
```

The runner starts one real `--server` process and two headless clients on test UDP port `24756`. It succeeds only when both clients reach a synchronized live two-human match, client-owned movement reaches peer 1, and both peers observe the controller complete gun pickup/fire/drop, melee pickup/swing/drop, and item pickup/drop/throw before returning to the persistent lobby. It also rejects unstable RPC paths and replication-cache cleanup errors. Passing logs include the `DEDICATED_INPUT_*`, `DEDICATED_MELEE_*`, `DEDICATED_ITEM_*`, and `DEDICATED_RETURN_PASS` markers for both clients.

## Linux dedicated-server export

Install the official Godot 4.7.1 export templates first. In Godot, open **Editor → Manage Export Templates**, choose **Install from File**, and select the official `Godot_v4.7.1-stable_export_templates.tpz` package.

Then export from the repository root:

```powershell
& ".\Godot_v4.7.1-stable_win64.exe" --headless --path "." --export-release "One Gun - Linux Server" "build/server/OneGunServer.x86_64"
```

Verified on 2026-08-13 with Godot 4.7.1: the command produced a valid Linux x86_64 ELF executable and `OneGunServer.pck` with no export errors, and the resulting Docker image passed the complete two-client gun/melee/item action suite.

The Linux preset intentionally keeps `export_filter="all_resources"` and uses the `dedicated_server` custom feature instead of Godot's resource-stripping dedicated export mode. Stripping previously produced placeholder-loaded presentation branches and broke gameplay paths that still referenced them. Authoritative held gun/melee/item state no longer depends on animated hand sockets: dedicated actors create invisible gameplay-only attachment markers under `AimPivot`, while rendered clients retain the existing visual sockets. The process still starts headlessly. The larger PCK remains an accepted development tradeoff until every gameplay dependency has been separated from presentation assets and the stripped export can be revalidated safely.

Run the exported server on Linux:

```bash
chmod +x build/server/OneGunServer.x86_64
./build/server/OneGunServer.x86_64 --headless -- --server --port=24545 --max-players=10 --lobby-name=OneGun-Dev
```

The Windows client preset is named `One Gun - Windows`. A normal Windows export still launches the main menu.

## Build/version metadata

One Gun keeps three concepts separate:

- `GAME_VERSION` is the player-facing release (`0.0.4`).
- `NETWORK_PROTOCOL` controls network compatibility (`1`).
- `build_id` identifies the exact artifact, normally `dev-<7-character-commit-SHA>`.

An unstamped local editor run uses build ID `dev`. Before exporting artifacts that should share an exact build ID, stamp the current Git commit from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\stamp_build.ps1 -Channel dev
```

Expected output has this form:

```text
[BUILD] Stamped dev-4868d24 (4868d244804be2a9556979fe973682026f81b859) -> ...\build_metadata.json
```

`build_metadata.json` is generated, ignored by Git, and explicitly included by both export presets. Stamp once, then export the Linux server and Windows client so both artifacts show the same ID. The dedicated server prints it at startup and records each admitted client's build; the client main-menu footer displays it.

A CI job can stamp an explicitly supplied commit without relying on the checkout's Git command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\stamp_build.ps1 -Channel dev -CommitSha $env:GITHUB_SHA
```

Return local editor runs to the `dev` fallback by deleting generated metadata through the helper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\stamp_build.ps1 -Reset
```

A different commit-derived `build_id` is metadata, not automatically a protocol break. Admission still rejects mismatched `GAME_VERSION` or `NETWORK_PROTOCOL`; the stricter player-facing mismatch flow remains a later compatibility phase.

## itch.io development client

The restricted development project is `https://one-gun.itch.io/one-gun`. Its Butler target is:

```text
one-gun/one-gun:windows-dev
```

Restricted projects do not grant access from the ordinary game-page URL. The project owner installs from the itch app's **Creations** tab. Testers must receive an individual download key from **Edit game -> Distribute -> Download keys**, claim that key while signed into their own itch.io account, and then install through the itch desktop app. Do not enable a shared page password or make the project public for development testing.

Install Butler by installing and signing into the itch desktop app. The app keeps its selected Butler version in `%APPDATA%\itch\broth\butler\.chosen-version`. Resolve that version instead of assuming a permanent executable path:

```powershell
$butlerVersion = (Get-Content "$env:APPDATA\itch\broth\butler\.chosen-version" -Raw).Trim()
$butler = "$env:APPDATA\itch\broth\butler\versions\$butlerVersion\butler.exe"
& $butler login
```

Never paste the resulting credential into chat, source files, or documentation. Before a manual client upload, stamp the intended server-compatible build, confirm the generated metadata exists, export, validate, and push the output directory:

```powershell
$buildId = "dev-<server-build-id>"
$commitSha = "<full-server-commit-sha>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\stamp_build.ps1 -BuildId $buildId -CommitSha $commitSha
if (-not (Test-Path .\build_metadata.json)) { throw "build_metadata.json is missing" }

& ".\Godot_v4.7.1-stable_win64.exe" --headless --path "." --export-release "One Gun - Windows" "build/client-windows/OneGun.exe"
& $butler validate ".\build\client-windows"
& $butler push ".\build\client-windows" "one-gun/one-gun:windows-dev" --userversion $buildId
& $butler status "one-gun/one-gun"
```

The status command takes the project target without a channel suffix. A successful table lists `windows-dev`, its build number, and the supplied user version. The installed client footer must show the stamped build ID; `dev` means the export did not contain valid generated metadata.

Manual Phase 8 verification passed on 2026-08-13. Butler `15.30.0` published the initial `dev-2318743` client, the itch app installed and launched it from a user-selected D-drive install location, and a second corrected build became active as itch build `1881779`. The second upload reused `99.92%` of the previous build and produced a `336.94 KiB` patch (`99.94%` savings). After the itch app applied that update, the main-menu footer displayed `BUILD v0.0.4 | dev-2318743`.

## Local Docker server

Prerequisites:

- Docker Desktop is running with Linux containers.
- The Linux server export exists in `build/server/`.

Confirm Docker is ready:

```powershell
docker version
docker info --format 'OSType={{.OSType}} Architecture={{.Architecture}}'
```

The second command must report `OSType=linux` and `Architecture=x86_64`.

Build the image from the repository root:

```powershell
docker build --file Dockerfile.server --tag one-gun-server:phase2 .
```

The `.dockerignore` sends only `Dockerfile.server`, `OneGunServer.x86_64`, and `OneGunServer.pck` as build context. The runtime uses a Debian 12 distroless base, runs as an unprivileged user, and contains no shell, editor, source project, or Windows build. Tini is the container PID 1 and forwards termination signals to Godot.

Start the server with the required UDP mapping:

```powershell
docker run --rm --name one-gun-server-local --publish 24545:24545/udp one-gun-server:phase2
```

Expected logs include:

```text
[DEDICATED] One Gun 0.0.4 | build dev-<7-character-sha> | protocol 1
[DEDICATED] Listening on UDP 24545 | max players 10 | lobby 'OneGun-Dev'
```

Connect a normal One Gun Windows client to `127.0.0.1`. Stop the foreground container with `Ctrl+C`. If it is running detached or in another terminal, stop it cleanly with:

```powershell
docker stop --time 10 one-gun-server-local
```

Tini forwards Docker's `SIGTERM` to Godot and maps the expected signal exit to success. Final automated validation stopped the active server in 0.41 seconds with exit code 0 and no OOM kill.

## Manual GHCR and Edgegap deployment

Edgegap pulls a prebuilt OCI image; it does not run the Godot export or Docker build. Use an immutable tag for every server artifact rather than overwriting `latest`.

1. Stamp the intended build, export the Linux server, and build the image:

```powershell
$buildId = "dev-<unique-build-id>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\stamp_build.ps1 -BuildId $buildId
& ".\Godot_v4.7.1-stable_win64.exe" --headless --path "." --export-release "One Gun - Linux Server" "build/server/OneGunServer.x86_64"
docker build --file Dockerfile.server --tag "ghcr.io/<github-user>/one-gun-server:$buildId" .
```

2. Authenticate to GHCR with a temporary classic GitHub PAT that has `write:packages`, push the immutable tag, then run `docker logout ghcr.io` and revoke that temporary push token. Edgegap uses a different classic PAT with only `read:packages`; store it in the Edgegap registry profile, never in source, documentation, or the shipped client.

3. In Edgegap, create or duplicate a version under `onegun-dev` with these settings:

```text
Registry profile: OneGunGHCR (ghcr.io)
Image repository: <github-user>/one-gun-server
Tag: the immutable build ID
Resources: 0.50 vCPU / 1.00 GiB
Time to deploy: 300 seconds
Maximum duration: 60 minutes (development)
Restart policy: Never
Active caching: Disabled for the manual development test
Port name: gameport
Internal port: 24545
Protocol: UDP
Port verification: Enabled
1:1 port mapping: Disabled
```

4. Deploy using the tester IP and public cloud. On the free tier, terminate the previous development deployment before creating another one.

5. When status is Ready, read the Host FQDN and **external** UDP port from Deployment Details. Edgegap dynamically maps that external port; it is not expected to equal internal port `24545`. Join from One Gun with:

```text
<host-fqdn>:<external-port>
```

Do not hardcode the temporary endpoint in the client. It changes when a new deployment is created.

Manual public verification passed on 2026-08-13 with build `dev-4868d24-pickupfix1`: a normal Windows client connected without Tailscale, VPN, port forwarding, or LAN access; became lobby controller; started City with a bot; moved; picked up and used gun, melee, and item gameplay; and returned to the persistent lobby. Server and client admission logs carried the same build ID.

## Current phase boundary

Phases 4–5 passed on 2026-08-13. The private GHCR image was pulled by Edgegap, internal UDP `24545` received a dynamic public mapping, and build `dev-4868d24-pickupfix1` passed the rendered public lobby/match/gameplay/lobby test. Tailscale is no longer required for this development-server path. Commit hashes remain informational while `GAME_VERSION` and `NETWORK_PROTOCOL` are the compatibility gate.

Phase 6 automation is implemented in `.github/workflows/deploy-server-dev.yml`. A push to `main` stamps `dev-<short-sha>`, installs the exact Godot 4.7.1 editor and export templates, validates and exports the Linux server, builds and pushes `ghcr.io/<github-user>/one-gun-server:dev-<short-sha>`, then creates or updates Edgegap version `onegun-dev/dev` to reference that immutable tag. GitHub Actions run `31679224169` passed on 2026-08-13 and published build `dev-ebd4a8c`.

Phase 7 extends that workflow with development-only replacement. It stops every active deployment whose authoritative status exactly matches application `onegun-dev` and version `dev`, including manual deployments that would otherwise consume the free tier's single slot; waits for termination; creates the replacement through Edgegap's v2 deployment API with tag `onegun-dev-ci`; waits for `READY`; and prints the new FQDN plus dynamic external UDP port in the GitHub Actions summary. The script re-verifies application/version identity before every stop and cannot target a production application or version. Automatic replacement was verified by GitHub Actions run `31684303253` for build `dev-d7c7867`.

Placement defaults to broad Fremont, California coordinates, matching the successful manual public test. To override the development location without changing source, create optional GitHub Actions repository variables named `EDGEGAP_DEV_LATITUDE` and `EDGEGAP_DEV_LONGITUDE`. These are configuration values, not secrets.

Required GitHub Actions repository secrets:

```text
EDGEGAP_API_TOKEN
EDGEGAP_GHCR_TOKEN
```

`EDGEGAP_GHCR_TOKEN` is a classic GitHub PAT with `read:packages` only. GHCR publication uses the workflow's short-lived `GITHUB_TOKEN` with `packages: write`; no package-write PAT is stored in GitHub Secrets. The Edgegap API token must remain in GitHub Actions only and must never enter the project export or shipped client.

Phase 7 and the dedicated action regression are verified complete. GitHub Actions run `31764060357` published build `dev-2318743`, replaced the existing free-tier development deployment, and produced a Ready public UDP endpoint. A normal rendered Windows client connected through Edgegap and successfully used the gun; authoritative logs reported `gun fire requested` rather than `matching gun not found`. The same attachment path is covered locally and in the exported Linux Docker image for gun pickup/fire/drop, melee pickup/swing/drop, and item pickup/drop/throw.

Phase 8 manual client distribution is verified. The restricted `windows-dev` channel installs through the itch desktop app, launches successfully, and applies Butler binary patches while retaining the matching server build identity.

Remaining checkpoints:

- GitHub Actions Windows-client publishing.
- The later player-facing version-mismatch flow and secure dynamic-deployment backend.

The manual server and client distribution paths are now stable enough to begin GitHub Actions client publishing. Dynamic match-server deployment remains deferred until the automatic client pipeline is also verified.

## Troubleshooting

- `Couldn't bind to UDP 24545`: stop the other host/server using that port or choose another local test port. The current menu joins `127.0.0.1` on the default `24545` port.
- `No export template found`: install the exact Godot `4.7.1.stable` export-template package, not templates for another Godot version.
- Build displays `dev`: this is correct for an unstamped local run. Run `tools\stamp_build.ps1` before exporting; if the wrong commit remains, run it again with the intended `-CommitSha`.
- An exported or itch-installed client unexpectedly displays `dev`: confirm `build_metadata.json` exists after stamping and before exporting. The Windows preset explicitly includes that file, but it cannot package a generated file that is absent.
- Client never reaches the lobby: verify client/server game and network protocol versions match and allow the Godot executable through the local UDP firewall.
- Client joins but cannot start: the first connected client is the lobby controller; every other lobby participant must be Ready unless the controller confirms Force Start.
- Executable permission denied on Linux: run `chmod +x` on `OneGunServer.x86_64`.
- `docker` is not recognized: install and start Docker Desktop, then open a new PowerShell window.
- Docker reports a Windows daemon: switch Docker Desktop to Linux containers before building.
- Container starts but the client cannot connect: confirm the mapping includes `/udp`; `-p 24545:24545` without `/udp` is incorrect for ENet.
- GHCR push returns `permission_denied` after a successful login: the token can authenticate but lacks upload permission. Use a classic PAT with `write:packages` for the local push; keep Edgegap on a separate read-only token.
- Edgegap cannot pull the image: confirm the registry profile uses `ghcr.io`, the package-reading username, a classic PAT with `read:packages`, and the exact immutable image tag.
- Edgegap free tier reports one active deployment: terminate the old development deployment, wait for termination, then deploy the new version.
- Edgegap is Ready but the client cannot connect: use the deployment Host FQDN plus its dynamic **external** UDP port. Do not substitute internal port `24545` unless Edgegap actually assigned it externally.
- Butler refuses the first upload with `Please verify your account's email address`: verify the creator account email in itch.io account settings, then rerun the same push command. No partial build is published.
- A restricted itch.io page says the owner has no access from its ordinary URL: open the project from the itch app's **Creations** tab. Give testers individual download keys; the bare restricted URL does not grant permission.
- The itch app does not show an update immediately: close the running game, refresh or restart the itch app, and reopen the Library entry. Confirm the new build from its in-game footer after updating.
- Client moves locally but authoritative pickups are rejected as too far away: verify both client and server include the peer-1 movement-visibility fix and inspect the server's pickup-rejection distance log. Build `dev-4868d24-pickupfix1` contains the verified fix.
- Client can move and pick up objects but cannot fire, swing, activate, or drop them: inspect server/client logs for `Failed to get path from RPC`. Gun, melee, and item requests must route through stable `RoundManager` RPCs, and the Linux server must use the full-resource preset rather than stripped placeholder resources.
- `Cannot create pipe from command: "xdg-user-dir"`: this single startup line is expected in the shell-free distroless runtime and does not affect ENet or server data. Any other `ERROR:` line still needs investigation.
