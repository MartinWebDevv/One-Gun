# Standalone lab validation — 2026-09-05

**Result: source isolation passes; 39 headless checks pass; Low and High Forward+
capture runs exit successfully with no script/resource errors.** The exact
`run.ps1 -Validate` launcher was exercised, including its separate import step.

All additions live in `tools/live_lobby_lab/`. The eight pre-existing modified
game/document files shown at task start were left untouched. No live startup,
menu, game setup or network file references the lab. Existing `.gdignore` and
export boundaries are checked by `verify_isolation.py`.

## Functional coverage

- Runtime offline peer; zero autoloads; no HTTP or replication nodes; separate
  user-data namespace; static scan for external loads, live calls and connections.
- Live-size capsule, normal camera boom/FOV, actual arrival-to-pit movement,
  individual tier collision heights, climbing, wall collision and dash travel.
- Modal movement suppression; mask preview rollback and explicit confirmation.
- Ten-person mock capacity and local setup's two-human/eight-bot cap.
- Queue duplication, cancellation and timeout; ready acceptance from inside the
  locker; physical traversal of the opened departure tunnel.
- Departure/return state, retained demo party and mask, and late-cancel protection
  for the return screen.
- A real camera/physics ray scores a practice target.
- Forty departure/return rehearsals preserve node/object counts. These transitions
  keep the room alive; they do not represent real match-map teardown.
- All nine visitors and their tween handles are removable.
- Five complete station create/free cycles preserve the node count. Measured
  static-memory delta after shared caches: **208,752 bytes** (about 204 KiB).

## Rendered evidence

Godot 4.7.1, D3D12, Forward+, NVIDIA GeForce RTX 4060 Ti. Sequential Low/High
captures used the **pilot's actual gameplay camera**, including its capsule-origin
offset and normal spring-arm framing. No alternate cinematic camera was used.

First reveal, central pit, locker, Events panel, ready check over Locker, ten-person
mock gathering, departure, pit detail and 1280×720 setup were captured. Inspection
led to corrected annulus winding/contrast, a wider arrival portal and a clear
departure opening/sign. World text is supplemented by native-resolution overlays
and shortcuts; two-player splitscreen readability remains a later test.

Final warmed samples, six seconds / 991 frames each, window 1920×1080:

| Metric | Low | High |
|---|---:|---:|
| 3D render scale | 75% | 100% |
| Frame interval median | 6.061 ms | 6.061 ms |
| Frame interval p95 | 6.144 ms | 6.166 ms |
| Maximum sampled interval | 6.288 ms | 6.575 ms |
| Draw calls | 192 | 192 |
| Rendered primitives | 65,484 | 65,486 |
| Static engine memory | 114,856,709 bytes | 114,789,894 bytes |
| Reported video memory | 281,411,584 bytes | 358,367,232 bytes |

Frame intervals measure delivery between `frame_post_draw` callbacks. They are
not separate CPU/GPU profiler measurements, and the approximately 165 FPS cadence
does not establish uncapped GPU capacity. Shader/first-use warm-up and screenshot
encoding are outside the warmed sample. Final full-party scene count: 943 nodes.
The seven source art assets total **790,521 bytes**, including the font; no GLBs
or large textures were added.

Generated screenshots and raw JSON live in `artifacts/`; the High set is under
`artifacts/high/`. These reproducible outputs and logs are ignored by Git.

## Remaining acceptance work

Hands-on camera/feel and navigation testing, especially on the weaker laptop at
1080p Low, is still required. The masked art and movement adapter are prototypes.
No tests here establish full controller/gamepad parity, P2 splitscreen, bot AI,
real account cosmetics, actual matchmaking, online parties, real match combat,
or integrated lobby/map/return memory stability. Those systems were intentionally
kept outside this standalone slice and must be validated when integration is
explicitly requested.
