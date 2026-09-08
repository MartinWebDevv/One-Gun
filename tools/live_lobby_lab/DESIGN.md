# Unlisted / Platform 01 — standalone Live Lobby study

Date: 2026-09-05. Scope: one isolated, playable spatial/UX prototype. **No live
integration is authorized or implemented in this slice.** The user's latest
standalone instruction supersedes the attachment's proposed connected launch flow.

## 1. Existing project audit

Read `AGENTS.md`, `docs/DESIGN.md`, `docs/GAME_RULES.md`, `docs/ARCHITECTURE.md`,
`docs/TODO.md` and `docs/PERFORMANCE.md`, then verified the relevant paths in code.
Some older design/AGENTS text still describes an eight-player/local-only game or
the former toy identity. Current code/rules and the user's new premise take priority.

| Current route | Actual behavior and evidence |
|---|---|
| Startup | `project.godot` → `app_bootstrap.tscn` → approved five-word startup cinematic → `main_menu.tscn`. Server mode bypasses presentation. |
| Local | Main menu's Local cabinet → Solo + Bots or local two-player → `game_setup.tscn`. The selection changes `GameConfig.split_screen_enabled`; lobby settings stay in `GameConfig`. |
| Local launch | `game_setup.gd::_launch_match()` checks the map registry/capacity and loads the selected map. Its RoundManager supplies match state, bots, items and the single match gun. |
| Online | `UI/online_play_overlay.gd` provides browser/quick join, host, code/direct join and development matchmaking. Successful connection is routed by the main menu into `game_setup.tscn`. |
| Development queue | `matchmaking/matchmaking_client.gd` POSTs/polls a coordinator contract, then supplies an endpoint/ticket to the existing join path. Tickets are individual; there is no durable party-ticket contract in this client. Do not relabel this as finished party matchmaking. |
| Online launch | Host/controller starts synchronized prelaunch; `NetworkManager`, scene-ready handshake, actor roles and `RoundManager` retain authority. Runtime actor spawning uses MultiplayerSpawner, owner movement, host bots and epoch-protected combat. |
| Social | `supabase/social_manager.gd` manages authenticated friends, presence and lobby invites. It describes joinable network sessions; it is not a general party object independent of transport/server lifetime. |
| Playpen | Online listen-host practice, entered through `request_enter_playpen()`. Its manager reuses authoritative round/actor contracts while disabling match scoring. Peers have explicit loading/practice/lobby roles and visibility-filtered traffic. Dedicated-session Playpen is unavailable. It is not a safe standalone lobby dependency. |
| Cosmetics | Home/lobby use the shared themed locker, PlayerPrefs and authenticated ownership/loadout APIs, stable local registries, rig binding and online roster IDs. Preview/Confirm/Cancel semantics are reusable, but importing the existing overlay would also import live dependencies. |
| Return | Winners Circle/host controls can call `host_return_everyone_to_lobby()`. Existing persistent sessions have a coordinated teardown/return route. Assigned dynamic match servers have their own ending/lifetime; no durable party home is guaranteed across every transport/queue route. |

`match_limits.gd` defines **10 total active humans + bots**, with at least two online
humans for applicable sessions. Local split screen supports two humans. Current
registry maps each advertise capacity ten; host human capacity can be configured
lower. A ten-person display in this study is a capacity rehearsal, not a claim that
ten-person party matchmaking exists.

The current registry names are Whispering Woods, Western Town, Gun Square,
Cat Tower, Neon Circuit and Trippy Mountains. The lab's The Town / Trippy Forest
labels preserve the brief's creative examples; none resolves a map path.

## 2. Concept and source inspection

Both supplied images were visually inspected. Sunken Pit supplies the common
center, readable destinations, social sightlines and tiered gathering edge.
Subway Station supplies repurposed transit architecture, believable arrivals,
crossing routes, tile/plinth construction and expandable tunnels. Text inside the
images was treated only as design reference, including the obsolete eight-person
example.

Opened `art_src/menu_hubs/one_gun_menu_hubs.blend` read-only in Blender 5.1.2:

| Scene | Objects | Mesh objects | Raw mesh faces |
|---|---:|---:|---:|
| LockerBackdrop | 67 | 62 | 2,203 |
| PrizeCounterBackdrop | 69 | 62 | 8,655 |
| ProfileBackdrop | 56 | 50 | 5,292 |

Total 192 objects. Each scene has one authored camera and three lights. These are
static menu-backdrop compositions, also confirmed by the generator and architecture
documentation. They are useful references for lockers, booth hardware, trophies and
materials, but do not establish a collision-complete, walkable shared room. The
prototype therefore builds new modular geometry. The Blender file and its runtime
PNGs remain unchanged; no destructive replacement or heavy GLB import is needed.

## 3. Specific spatial design

One Godot unit is one metre. Plan axes: east = +X, north = -Z. The principal room
is 34 × 34m with a 6.3–10m vault. Its active gathering space is much smaller than
the footprint: the pit is roughly 12m across, and every essential overlay is
available without travel. At the real 10m/s walk speed, most central routes are
one or two seconds; no artificial lobby speed nerf is introduced.

| Element | Position / dimension | Experience |
|---|---|---|
| Arrival | South, Z 14.2, +1.2m landing, six 0.2m steps | Brief sliding-door reveal. Wide portal clears the normal shoulder camera. Control begins immediately; no long cinematic. |
| Central pit | X/Z 0, floor -0.6m; three 0.2m annular tiers out to radius 8.2m | Common social center with painted One Gun seal. No functional display gun. Sparse benches and partial rails leave multiple routes open. |
| Event desk | X 0, Z -9.5 | Large event board directly beyond it at Z -15.6; alias/state readable from the approach. Tab mirrors the interaction. |
| Locker | Northwest, X -10.7, Z -12 | Magenta sign, repurposed steel lockers, transactional mask preview. |
| Party station | West, X -13, Z 0 | Cyan console; no empty pads. Demo visitors gather inward rather than occupying a grid. |
| Compact range | Northeast, X 7–14, Z -8.5 to -16.5 | Three 7m lanes with simple target/backstop collision; orange cue. No gameplay gun or damaging projectiles. |
| Departure | East, X 16.5, Z 0; short 4m tunnel | Shutter opens on accepted ready check. Destination updates. Automatic transition does not require crossing the gate. |
| Movement line | Southeast, X 9–12, Z 6–14 | Optional jump/step/dash route; can be ignored without losing access to anything. |
| Social/expansion edge | Southwest, sealed Line 02, radio, crates, benches | Suggests occupied infrastructure and future range/tunnels. Radio and expansion doors are scenery in this slice. |

The first view is generated by the pilot's own SpringArm/Camera3D, not an isometric
camera. Capsule radius/height match the live player. The feet-origin adapter adds
the live 1.09m body-origin offset before reproducing spring-arm/shoulder transforms,
4m boom and 75° baseline FOV. Step-up uses the existing body sweep. Walk 10,
sprint 18, jump 7, dash 30 for 0.2s; three independent 3s charges follow the game
rules/config, rather than the old controller's unused 2s fallback constant.

## 4. Visual direction

The room belongs to a secret global event circuit, not one map's physical world.
"The location changes. The rule never does." carries that identity without
requiring neon, western, forest and tower arenas to resemble each other.

| Role | Color | Use |
|---|---|---|
| One Gun / navigation | Acid gold `#D8D23E` | Painted seal, essential sign rules, stairs, event board |
| Ready | Green `#9EDC6B` | Accept cue and departure confirmation |
| People | Cyan `#58C9DB` | Party console, arrivals and alias labels |
| Identity | Magenta `#E080B9` | Locker and competitor expression |
| Practice | Orange `#E69850` | Target lane and optional movement |
| Base | Ink `#152328`, paper `#E5DFC6`, desaturated tile/steel | Warm, worn infrastructure; readable high-contrast typography |

Warm overhead practicals establish the base. Local colored light is limited to
two stations; most navigation color is paint or restrained emission. No every-
surface glow, transparent hologram stack, oversized screen collection or military
equipment. Structural ribs, plinth tile, conduit, patched lockers, worn posters,
route diagram and alias marks tell the occupation story. No new model exceeds the
asset budgets; the environment uses procedural meshes and 512/1024px textures.

This is an art blockout with a coherent palette and layout, not the final concept-
art finish. Next art passes should refine the station kit and masked competitor
silhouette while preserving the tested camera clearance and simple collision.

## 5. Complete intended experience and current rehearsal

1. **Entry:** eventual main-menu Play would hand off to a private hideout via the
   arrival transition. In this slice, launch the separate lab and click Enter the
   Hideout. Doors reveal the room; the board welcomes STRAY. There is no main-menu
   connection.
2. **Public event:** open Events with E or Tab → Public Event. That single button
   starts the local eight-second search. The room regains control immediately.
   X or the overlay cancels. The final integrated version would keep one durable
   party ticket alive independently of open UI; this backend contract is deferred.
3. **Private event:** Events → Private → choose destination → Rehearse Private
   Event. The future version would edit the existing GameConfig transaction and
   host options; this one only selects a local label and enters a ready rehearsal.
4. **Join:** Events → Join → Accept Demo Invitation. LAB-01 illustrates the invite
   context. Future friend invitations must reuse SocialManager consent and the
   existing protocol-aware join path; no such methods are callable here.
5. **Local humans/bots:** Events → Local + Bots → destination, one/two humans,
   count and difficulty → Rehearse Local Departure. Counts clamp to ten. Future
   integration must use GameConfig pending/apply/rollback and P1/P2 input routing.
   This slice does not run two cameras or bot controllers.
6. **People:** P / party console → Simulate Friend Arrival → Back to Room. Each
   stand-in comes from the doors and joins the center. Remove Last Demo Friend is
   available at home. Roster changes are disabled during a search/ready/departure
   rehearsal; the real future system needs ticket-aware leave/disconnect policy.
7. **Cosmetics:** L / locker → preview a mask color → Confirm, or Back/ESC to
   discard. Queueing continues. Real ownership, full models/hats and persistence
   are deferred; reuse the established registry and confirm semantics later.
8. **Practice while queued:** return to movement, use range or movement line.
   Range rays only score known target bodies behind the firing line and never
   create guns/damage. Cue, score and all state are local.
9. **Match found:** a high-contrast banner and short generated two-note cue appear
   anywhere. R / Accept works over an open station UI. The 15-second ready window
   can be declined with X; timeout restores Home while retaining the party.
10. **Departure:** accept → green destination/shutter → four-second countdown.
    X cancels. Gate entry is optional theater. The countdown opens an explicit
    destination rehearsal screen; it loads no arena and creates no server.
11. **Return:** Return With Your Party restores control at arrivals. The same room
    and demo party remain. Future integrated return must retain party identity
    outside the match-scene lifetime, re-admit peers through scene readiness and
    release the previous world/resources before loading the next.

## 6. Eventual reuse and changes — design only

Reuse GameConfig, GameEvents, the real player and input-prefix contract, cosmetic
registries and confirmed loadouts, existing social consent/UI, protocol admission,
host/controller permissions, ready handshakes, spawner visibility and round epochs.
Do not branch or bypass these to make the lobby appear integrated quickly.

New work will be a persistent party/session identity with a defined leader/leave/
disconnect policy, party-aware matchmaking tickets and durable return destination,
plus a lobby-specific player mode that safely disables damage and scoring. Existing
Playpen authority must either be preserved for later shared practice or separated
behind an explicitly reviewed contract; importing its manager is not a shortcut.

Map presentation should eventually use registry thumbnails/cached previews, not
load complete arenas into the lobby. Future stations should emit GameEvents intent
and consume existing session state, while match rules continue to reside in
GameConfig. No future adapter, dormant endpoint, feature flag or launch hook is
included in this standalone project.

## 7. Performance and acceptance boundary

Static mesh instances are consolidated by material and spatial quadrant at build
time. Dynamic doors, targets, characters and text remain independent. Simple
capsules/boxes and low-poly annulus collision keep physics bounded. Per-frame work
is one pilot, the active local phase timer and only visitors currently arriving;
readouts update at 10 Hz. No tree scans run in the gameplay loop. Target flashes
reuse the targets and cancel replaced tweens. Inactive states do no event polling.

Headless validation exercises forty destination/return rehearsals and five station
create/free cycles; rendered captures include ten visible stand-ins and a six-
second warmed Low sample at 1080p. Record the hardware and read `render_profile.json`
alongside screenshots; screenshot export/first-use warm-up is not included in that
sample. Prototype performance does not establish live-combat or final-asset cost.

Before connecting anything, play the lab on the weaker laptop, measure startup and
first-use stalls, movement/camera feel, route readability, maximum arrivals and
frame pacing. Integrated acceptance must later cover P1/P2, gamepads, online
two-machine party flow, real map teardown/reload and repeated RAM/VRAM growth.
