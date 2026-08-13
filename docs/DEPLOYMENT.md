# One Gun Deployment

This document records the deployment pipeline as each layer is verified. Phases 1–5 established the Godot 4.7.1 headless dedicated-server runtime, Linux export, Docker image, build metadata, GHCR publication, and a verified public Edgegap UDP deployment. GitHub Actions, itch.io, and Butler remain deferred to later phases.

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

The runner starts one real `--server` process and two headless clients on test UDP port `24756`. It succeeds only when both clients reach a synchronized live two-human match, client-owned movement reaches peer 1, a real client input action completes an authoritative gun pickup, both clients observe the held state, and the session returns to the persistent lobby without replication-cache cleanup errors. Passing logs include `DEDICATED_SERVER_PASS`, `DEDICATED_MOVEMENT_SYNC_PASS`, `DEDICATED_INPUT_PICKUP_PASS`, and `DEDICATED_RETURN_PASS` for both clients.

## Linux dedicated-server export

Install the official Godot 4.7.1 export templates first. In Godot, open **Editor → Manage Export Templates**, choose **Install from File**, and select the official `Godot_v4.7.1-stable_export_templates.tpz` package.

Then export from the repository root:

```powershell
& ".\Godot_v4.7.1-stable_win64.exe" --headless --path "." --export-release "One Gun - Linux Server" "build/server/OneGunServer.x86_64"
```

Verified on 2026-08-12 with Godot 4.7.1: the command produced a valid Linux x86_64 ELF executable and OneGunServer.pck with no export errors.

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

Phase 6 automation is implemented in `.github/workflows/deploy-server-dev.yml`. A push to `main` stamps `dev-<short-sha>`, installs the exact Godot 4.7.1 editor and export templates, validates and exports the Linux server, builds and pushes `ghcr.io/<github-user>/one-gun-server:dev-<short-sha>`, then creates or updates Edgegap version `onegun-dev/dev` to reference that immutable tag. The workflow never stops or creates a deployment; development restart behavior belongs to Phase 7.

Required GitHub Actions repository secrets:

```text
EDGEGAP_API_TOKEN
EDGEGAP_GHCR_TOKEN
```

`EDGEGAP_GHCR_TOKEN` is a classic GitHub PAT with `read:packages` only. GHCR publication uses the workflow's short-lived `GITHUB_TOKEN` with `packages: write`; no package-write PAT is stored in GitHub Secrets. The Edgegap API token must remain in GitHub Actions only and must never enter the project export or shipped client.

Remaining checkpoints:

- First live Phase 6 GitHub Actions run and verification of the generated GHCR image plus Edgegap `dev` version.
- Phase 7 development-only deployment replacement.
- itch.io or Butler publishing.
- GitHub Actions Windows-client publishing.
- The later player-facing version-mismatch flow and secure dynamic-deployment backend.

Do not begin Phase 7, itch.io, or client automation until the Phase 6 workflow succeeds from a GitHub push.

## Troubleshooting

- `Couldn't bind to UDP 24545`: stop the other host/server using that port or choose another local test port. The current menu joins `127.0.0.1` on the default `24545` port.
- `No export template found`: install the exact Godot `4.7.1.stable` export-template package, not templates for another Godot version.
- Build displays `dev`: this is correct for an unstamped local run. Run `tools\stamp_build.ps1` before exporting; if the wrong commit remains, run it again with the intended `-CommitSha`.
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
- Client moves locally but authoritative pickups are rejected as too far away: verify both client and server include the peer-1 movement-visibility fix and inspect the server's pickup-rejection distance log. Build `dev-4868d24-pickupfix1` contains the verified fix.
- `Cannot create pipe from command: "xdg-user-dir"`: this single startup line is expected in the shell-free distroless runtime and does not affect ENet or server data. Any other `ERROR:` line still needs investigation.
