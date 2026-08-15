# One Gun development match coordinator

This Cloudflare Worker is the trusted boundary between shipped One Gun clients and the limited Edgegap Matchmaker API. It never returns or logs `EDGEGAP_MATCHMAKER_TOKEN`. Clients receive only a signed queue capability and, when ready, their assigned ticket plus the dynamic public ENet/UDP endpoint.

This is a development/playtest service. It uses anonymous, rate-limited queue capabilities; production still needs real player authentication and durable lobby ownership.

## Local validation

From this directory:

```powershell
npm.cmd install
npm.cmd test
```

The Godot-side contract test is run from the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_matchmaking_client_smoke.ps1
```

## Deploy once

Do not paste either secret into source, `wrangler.jsonc`, GitHub variables, or the One Gun client. Because both secrets are declared required, upload them atomically with the first Worker deployment.

First generate the signing key locally and copy the one-line result:

```powershell
$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
[Convert]::ToBase64String($bytes)
```

Then create a temporary ignored secret file, edit it locally, deploy, and remove it:

```powershell
cd "D:\Godot Projects\one-gun\services\match-coordinator"
npm.cmd install
npx.cmd wrangler login
Copy-Item .dev.vars.example .dev.vars
notepad .dev.vars
npx.cmd wrangler deploy --secrets-file .dev.vars
Remove-Item -LiteralPath .dev.vars
```

In `.dev.vars`, replace only the two placeholder values:

- `EDGEGAP_MATCHMAKER_TOKEN`: the Edgegap Matchmaker instance's limited Auth Token, not the organization API token.
- `COORDINATOR_SIGNING_KEY`: the random value generated above.

The file is ignored, but still delete it immediately after deployment. Do not paste either value into chat.
After deploy, record the printed HTTPS `*.workers.dev` URL and verify:

```powershell
Invoke-RestMethod "https://YOUR-WORKER.workers.dev/health"
```

Expected fields: `service = one-gun-match-coordinator`, `status = ok`, `schema = 1`.

Then update `matchmaking/coordinator_config.json` with that public URL and set `enabled` to `true`. The URL is not a secret. Never put either backend secret in that file.
