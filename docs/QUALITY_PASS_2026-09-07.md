# One Gun — quality repair pass, 2026-09-07

This pass implements the highest-priority repairs from [the deep audit](DEEP_AUDIT_2026-09-07.md), then addresses loading and accessibility QoL. Changes are local source/assets; nothing was published. **Hideout integration was not started.** Its prototype remains outside the live map/lobby flow and outside exports.

## Good — repaired and verified

| Area | Result |
|---|---|
| Gun origins and cover | Local/server shots reject an origin across solid cover before consuming reload. The server envelope is 3.25m rather than 7m; ownership, direction and epoch checks remain. Valid shots preserve the exact viewport-center origin/direction pair. |
| Melee hit detection | Shared physical-cover checks cover local swings, dedicated candidates, authoritative hits and One of Us conversion. Smoke does not become a physical wall. Genuine thrown-weapon collisions remain valid beyond the holder's swing range. |
| Online bullets | Shot IDs plus reliable, round-guarded retirement stop ghost tracers. Clients predict world impacts for presentation; damage remains authoritative. Retirement still reaches a bullet after its gun is dropped/reparented. |
| Network lifetime | Delayed appearance hydration requires connected/admitted status. Host spawning owns despawns. Return-to-lobby waits for peers to suspend movement, removes the visibility filter that previously re-enabled it, then despawns before scene handoff. A stalled peer times out after five seconds. Playpen departure suspends the local actor while host bots continue. |
| Assets | Bot: **660,544 → 82,214 triangles**, **24.67 → 2.85 MiB**. Bat: **89,296 → 13,394 triangles**, **4.30 → 2.37 MiB**. Both use 1024px textures. Rig nodes, joint relationships, transforms and animation metadata are retained; rendered equipment/model checks pass. Source backups remain in the local ignored artifact folder. |
| Loading | One autoload owns serialized/coalesced background scene requests for previews and match handoff. Cancelling removes the caller's callback; already-started Godot workers drain safely. Online callbacks carry connection/match/load generations. Local loading adds Cancel/Escape and guards duplicate/guest launch. Main-thread instantiation remains. |
| Lobby accessibility | The actual 720p/125%-UI/large-text capture revealed clipped controls/roster rows and crushed map text. Focus-following scrolling now keeps all ten actors' controls and Back reachable; narrow map details stack. Taller rosters retain full-height rows. |
| Camera and Hats | ADS shoulder x moves from 0.75m to 0.85m to clear the female wide-brim hat throughout Idle. Boom, FOV, collision and reticle calculation remain. All **12 Hats × 8 models × 2 camera modes**, at eight deterministic Idle phases, pass. Solo/split reticle regressions still meet their 0.5px tolerance. |
| Maps | Trippy's first-round marker and 40° sweep now satisfy the interior bounds. Neon has seven readable, depth-tested circuit/vault/capacity signs, repositioned clear of its dressed portal columns and verified in seven rendered viewpoints. Navigation/collision checks pass. |
| Combat feedback | Blocked shots show a short amber **COVER** cue without a hit-confirmation sound. Boomerang disarms send a valid icon to both feed/stat events rather than a null value that broke the feed callback. |
| Online QoL | Optional Connection Status/Ping uses existing ENet statistics once per second. Lobby UI says **Unlisted** and explains endpoint/code access. It no longer implies enforced private/friend admission. |
| Resource/export hygiene | Two unparented title Labels now share the menu lifetime. Exports exclude audit captures/artifacts and high-resolution Hat sources. The original smoke mask/mipmaps are precomputed and byte-verified; its appearance and gameplay rules are unchanged. |
| Validation/docs | Fixed Idle-phase normalization, legitimate pointer/controller focus setup and newest-map expectations. Added combat-cover, loading/cancellation and large-text lobby tests. Updated design, rules, architecture, performance and deployment notes while retaining existing user work. |

## Verification

- Ran the **37-suite broad headless pass**, covering combat, shared hitboxes, M/F and six gift models, decoys, maps/navigation, modes, overtime, capacity, input, cosmetics, social/catalog, winners and migration. The menu failure found in that pass was repaired and rerun successfully.
- Ran the **11-suite Forward+ rendered pass**. The hat sightline failure was repaired and rerun with stronger full-cycle sampling. Extra rendered checks cover the compact lobby, real menu pointer actions, asynchronous preview switching, smoke and the seven Neon signs.
- Ran the **12-scenario localhost networking matrix**, plus protocol-3 match/ticket/version checks and repeated dedicated/exit tests. The final three dedicated movement/combat/return runs are clean, including two with a 600ms client stall. Listen-host/guest exit and Playpen checks complete their intended flow.
- Added/ran focused checks for through-wall gun origins and melee, valid openings, thrown range, visual bullet retirement, stale impact epochs, boomerang feed delivery, shared loader requests, cancellation, missing resources and guest launch rejection.
- Ran four local coordinator tests with protocol-3 fixtures: **4 pass, 0 fail**. No live coordinator/account/reward operation was performed.
- Rendered **two six-map cycles twice**, one human plus nine expert bots. Each map retained one Standard-mode gun, ten actors and ten spawns. The second run includes frame-spike telemetry and completes without engine errors.
- Re-ran the separate Hideout prototype after the shared changes: **291 checks, zero failures**, with networking kept offline. Its final exit still reports one resource-in-use warning; no live entry point or integration was added.
- Five repeated headless lobby create/free cycles returned to **30 nodes, 0 orphan nodes and 90 resources** every time. Map unloads also return to 30 nodes; the extra node versus the audit is the intentional SceneLoadManager autoload.

Logs/captures are in `artifacts/quality_pass_20260907/`. `final_validation_summary.json` selects the final results; earlier logs retain discoveries and intermediate failures. Some headless scenario exits still emit an isolated resource-in-use warning, and some rendered UI exits report a small ObjectDB count. Those are not silently counted as clean exits; they remain a shutdown-investigation item. The measured cleanup loops do not show accumulating scene nodes.

## Needs improvement — measured remaining work

### Frame pacing and weaker hardware

Same development GPU, 1080p window, Low (75% 3D scale), Forward+/D3D12. The following is the warm second-cycle frame sample. Bots and visibility vary, so these numbers are not a controlled speedup claim.

| Map | Audit median / p95 ms | First repair-pass median / p95 ms |
|---|---:|---:|
| Whispering Woods | 12.87 / 16.88 | 5.86 / 9.50 |
| Western Town | 6.89 / 11.84 | 5.28 / 9.80 |
| Gun Square | 9.43 / 13.50 | 7.64 / 11.75 |
| Cat Tower | 6.97 / 11.52 | 7.04 / 11.28 |
| Neon Circuit | 6.76 / 11.65 | 4.92 / 8.77 |
| Trippy Mountains | 9.67 / 15.11 | 6.02 / 10.94 |

Tracked rendering memory after unloading settled to **321.61 MiB** in that repair pass versus **425.80 MiB** in the audit: about **104 MiB less**. The second seeded run settles around 299 MiB, with a small retained first-use resource difference.

Long frames still occur: 157ms in one warm Trippy sample and 198ms around smoke creation in the seeded run. Cold effect creation/pipeline work remains a concern. Smoke's isolated construction measurement went from **87.6ms to 42.8ms** after moving the exact pixel mask offline, but render-frame spikes remain and individual samples are noisy. Removing particle pre-simulation did not eliminate the first-use stall, so the original effect was retained.

**Next:** profile and warm first-use GPU/material/particle work within the loading budget, investigate Woods visibility/draw calls, and measure real CPU/GPU timing on the weaker laptop. Do not declare the 60 FPS target met from these short desktop samples. Main-thread scene instantiation also needs a lower-spec transition budget.

### Readability, feel and network conditions

- **Dark skins in Woods/Western:** tune restrained character/material lighting against representative backgrounds; preserve shadows, atmosphere and concealment. This pass did not change that art direction.
- **Human animation/camera feel:** the model, socket, collision, reticle and sampled-animation checks pass; physical-controller combat transitions, grip/foot sliding and long-session comfort still need hands-on play.
- **Real internet:** test two machines, Tailscale/public endpoints, packet loss and latency. Localhost does not establish WAN prediction or reconnection quality.
- **Shutdown warnings:** trace the remaining isolated resource/ObjectDB reports under complete rendered menu/network loops. Do not suppress actionable script or replication errors in smoke runners.

## Missing features deliberately left for later

Reconnect/resume and a clear host-loss policy; enforced Friends Only/invitation admission; onboarding/control-discovery improvements. Existing friends, settings, accessibility, input remapping and progression interfaces are already present. No new music requirement is being added. **Hideout networking, live entry points, squad travel and live match integration remain deferred.**

## Release compatibility

Source now uses **network protocol 3**. Export matching clients and dedicated servers and deploy the matching coordinator configuration together. Old protocol-2 clients/servers should be rejected instead of mixing incompatible projectile/teardown RPCs. This pass updated local configuration and documentation only; the currently deployed service was not changed.

Before a public release: test a build on the weaker laptop at 1080p Low, with physical controllers, ten actors and repeated lobby → Playpen → match → Winners Circle transitions; then complete a two-machine network session.
