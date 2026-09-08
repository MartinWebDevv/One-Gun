> **Current version:** Open `res://tools/live_lobby_preview/live_lobby_preview.tscn`
> in the main One Gun project and press **F6**. That enlarged scene uses the real
> character and separate Player Hub kiosks, and remains unlinked from the main
> menu and matches. This folder is the older separate-project fallback.
# One Gun — Live Lobby Lab

**Standalone, offline prototype. Nothing is connected to the live game.**

Double-click **`Launch Lobby.cmd`** in this folder, then choose **Enter the Hideout**.
It starts the nested `project/project.godot`, using the existing Godot 4.7.1 executable.
You can also import that nested project separately in Godot. Do not add this scene to
the OneGun main menu or run it as a scene inside the parent project.

The new room is called **Unlisted / Platform 01**. It combines the station concept's
architecture with the Sunken Pit's central gathering space. Read `DESIGN.md` for the
project audit, measured layout, proposed complete experience, and eventual integration seams.

## What works in this lab

- Walkable station, collision, camera boom collision, arrival-door reveal, jump,
  dash charges, optional sprint, and the existing controller's step-up algorithm.
- Event board and global shortcuts; exploring continues during a simulated search.
- Local search → timed ready check → departure shutter/countdown → destination
  rehearsal → return, retaining the same room, demo party, mask, and range score.
- Simulated visitors physically travel from the arrival doors into the central pit.
  Up to ten visible competitors including the pilot; no empty player pads when solo.
- Mask-color preview, confirm and rollback. The confirmed color lives only in memory.
- Three ray-tested light-trainer targets, hit feedback, shot counter and score reset.
- Low/High presentation switches. Low is the default: Forward+, 75% 3D scale,
  no glow, SSAO, SSIL, SSR, volumetric fog, MSAA, or real-time light shadows.

## What is explicitly mocked or deferred

The masked runner is lightweight temporary art. The pilot is a **movement-only
snapshot**, not the full `character_body_3d.gd`. Live controller settings, input
rebinding, controller devices, combat, animation rig, stamina HUD, inventory,
abilities and network ownership are not imported. Full control parity must be
verified later. The lab supports one controllable keyboard/mouse player.

Friends are local animated stand-ins. Public/private/join actions are simulations;
`LAB-01` is an illustrative code. There is no party service, invitation, account,
matchmaker, socket, server, RPC, or live destination. Local-human count and bots are
setup previews; **P2 splitscreen and AI are not spawned**. Bot difficulty is a
preview label. The world destinations are creative studies, not playable map links.
The light trainer has no gun, projectile, inventory, damage or gameplay pickup.

The destination screen marks where the real game would eventually take over.
Return rehearses persistence **within this running lab**, not an integrated
lobby/map/network teardown. Closing the lab clears all session choices.

## Controls and a five-minute test

| Input | Action |
|---|---|
| WASD / mouse | Move / look |
| Space | Jump |
| Shift | Dash, three charges, each recharges in 3 seconds |
| E | Use a nearby event, party or locker station |
| Tab / P / L | Events / party / locker from anywhere |
| R / X | Accept / decline or cancel the active rehearsal from anywhere |
| Left click inside range | Aim with the center reticle and fire the light trainer |
| T inside range | Reset practice score |
| Escape | Menu, release mouse, or close the current station overlay |
| F1 | Switch Low/High |
| Ctrl | Sprint while the menu's sprint-practice option is enabled |

1. Enter and walk down the arrival stairs into the pit. Check the signage at your
   normal shoulder-camera height, then walk around the locker, range and departure.
2. Press **P**, simulate two friend arrivals, and return to the room to watch them.
3. Press **L**, preview a color and close it to test rollback. Reopen and confirm one.
4. Press **Tab → Public Event**. Practice at the range or open the locker while the
   eight-second demo search runs. Press **R** anywhere when the ready check appears.
5. Watch departure, then choose **Return With Your Party**. Check that visitors,
   color and score remain. Repeat; also try **X** during search and countdown and
   let a ready check time out without accepting.
6. Try private, join and local/bot setup previews. Inspect the two-human/eight-bot
   cap without expecting a playable split-screen or bot match.

## Isolation and reversibility

`tools/live_lobby_lab/.gdignore` hides the whole lab from the parent Godot importer.
The existing client and server export presets already exclude `tools/**`.
The nested project declares **zero autoloads** and has a separate `OneGunLiveLobbyLab`
user-data namespace. Its runtime resource loads stay within its own `res://` root.
It uses an independent copy of the heading font. No main-game scene, script,
configuration, save, account, endpoint or existing Blender source is modified.

The launcher imports and runs only this nested project. It does not start a game
server, matchmaking process, or the main game's bootstrap. Removing this lab
folder reverses the entire feature; no fallback/menu switch needs undoing.

`verify_isolation.py` makes these boundaries reviewable and fails on newly added
live singleton calls, network/process construction, escaping loads, autoloads,
or a live startup/menu reference. The headless suite also inspects the running tree.

## Rebuild and verify

From the repository root in PowerShell:

```powershell
python tools/live_lobby_lab/verify_isolation.py
powershell -NoProfile -File tools/live_lobby_lab/run.ps1 -Validate
powershell -NoProfile -File tools/live_lobby_lab/run.ps1 -Capture
```

`-Capture` produces actual pilot-camera PNGs and `artifacts/render_profile.json`.
`-High` uses full render scale, FXAA, modest glow and SSAO. `-Editor` opens only the
standalone project. The station is built by `station.gd` at runtime, so run the
scene to inspect it; geometry dimensions and station positions are in that file.
`generate_art.py` regenerates the seven small art assets with Pillow. The copied
font's source remains in the main repository; ordinary launch never needs it.

The prototype's behavioral suite covers offline isolation, real capsule navigation,
wall collision, dash, modal input, cosmetic transactions, capacity, global ready,
cancellation and timeout, a real target ray, forty return cycles, visitor cleanup,
and repeated station construction/freeing. Rendered captures additionally inspect
the first reveal, central pit, locker, event UI, ready overlay, full mock party, and
1280×720 setup UI. These checks do not substitute for a hands-on feel test.

**Before integrating:** test this lab on the weaker laptop at 1920×1080 Low,
including maximum visitors, first arrivals, targets and repeated rehearsals. The
RTX 4060 Ti measurement is a development-machine sample, not a laptop guarantee.
Real local matches, online parties, full map transitions, and RAM/VRAM stability
across those integrated transitions remain later validation gates.
