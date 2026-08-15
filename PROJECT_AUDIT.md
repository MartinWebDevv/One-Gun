# One Gun Project Audit

Audit date: 2026-07-14  
Engine target: Godot 4.6.3, Forward+, Jolt physics  
Audit scope: repository structure, documentation, scenes, gameplay, multiplayer, UI, assets, maps, character, Blender tooling, Godot startup, and existing smoke tests.

## Executive summary

One Gun is a playable, feature-rich arena shooter rather than an early prototype. Local solo/bot play, two-player splitscreen, round/set/match scoring, a one-gun combat loop, randomized melee weapons, seven item types, seven powerups, three selectable maps, player settings, and an online Tailscale/ENet mode are all present. Online phases 1 through 2e are implemented in the current code, including host-owned bots and host-authoritative gun, melee, item, powerup, elimination, and scoring paths.

The strongest work is the clear gameplay identity, centralized match configuration, signal-based cross-system events, reuse of the same map scenes for local and online play, stable online actor IDs, marker-preserving online spawning, and deterministic generators for the three newer map asset sets.

The project is ready for a stabilization phase, not an uninformed feature pass. The largest immediate risks are:

1. Existing documentation contradicts the current implementation in important places.
2. The online smoke test is not fully stable: Western V2 failed the Magnet Hands check twice; Forest failed once and passed once.
3. The three current selectable map files contain NavigationMesh settings but no serialized navigation polygons, despite older documentation claiming baked polygon counts.
4. Core responsibilities are concentrated in several very large scripts, especially `round_manager.gd`, `character_body_3d.gd`, `dummy.gd`, and `game_setup.gd`.
5. The Blender pipeline is reproducible for generated map assets but hardcoded to one machine and contains no `.blend` source files for imported character/legacy assets.
6. The current bot character model is approximately 660,636 triangles and 24.67 MB, over the repository's own model budget.

No gameplay, scene, asset, configuration, or existing documentation file was intentionally changed by this audit. The worktree was already dirty before the audit; those changes were preserved.

## Audit method

The audit used the following order:

1. Read every Markdown file in the repository.
2. Inventory folders, file types, scenes, scripts, resources, add-ons, and configuration.
3. Trace the main-menu-to-match flow and the local/online branches.
4. Inspect player, bot, weapon, item, powerup, scoring, UI, and networking scripts and scenes.
5. Inspect all map-like scenes and their authored gameplay markers.
6. Inventory models, textures, shaders, audio, duplicates, temporary files, and unused candidates.
7. Inspect Blender generator and map-builder tooling.
8. Verify installed Godot and Blender versions and run existing Godot smoke coverage.

Approximate repository snapshot excluding `.git/` and `.godot/` caches:

| Measure | Result |
|---|---:|
| Files | 987 |
| Size | 332.92 MB |
| GDScript files, including add-on scripts | 87 |
| Godot scenes, including add-on examples | 58 |
| Game-owned GDScript files | 58 |
| Game-owned scenes | 50 |
| GLB models | 149 |
| PNG/JPG source textures | 132 |
| EXR images | 35 |
| Source audio files | 14 |
| Selectable gameplay maps | 3 |
| Legacy/prototype gameplay maps | 2 |
| Menu-background map | 1 |
| Enabled editor plug-ins | 1 (`Terrain3D`) |
| `.blend` source files | 0 |

## Current product state

### Implemented and playable

- Main menu with live 3D background, local play, online play, settings, and quit.
- Local solo play with bots and two-player splitscreen.
- Three selectable maps: Whispering Woods, Western Town, and Maple & 3rd.
- Last-player-standing rounds, sets, match wins, statistics, scoreboard, and spectating.
- Movement, sprint, stamina, jump, dash charges, aim, ADS, camera, and step-up.
- Exactly one gun instance per map and multiple authored melee placements.
- Five randomized melee weapon types and effects using one shared mode-aware hit capsule.
- Seven consumable/deployable item types.
- Seven powerup types.
- Four bot difficulties with navigation, combat, item, and powerup behavior.
- Player settings, persistent input overrides, audio/display settings, and local pause flow.
- Online host/join over ENet and Tailscale, named-lobby discovery, synchronized roster/names, coordinated loading, authoritative combat/scoring, online HUD, pause overlay, and host-owned bots.
- Two-process online smoke-test tooling.

### Present but incomplete or provisional

- Character customization entry point and popup exist, but there is no customization system.
- Online teams and friendly fire are explicitly disabled because peer team assignment does not exist.
- Named lobby discovery is limited to the host's Tailscale peer list; there is no public lobby service.
- No reconnect, host migration, robust late-join, or client-side prediction/interpolation layer.
- Several combat and round SFX are missing.
- Grenade explosion, bubble-gum trap, powerup pickup, bullet, and some world/UI presentations use simple procedural geometry or text/emoji presentation.
- Legacy maps exist but are not selectable and do not conform fully to current marker conventions.
- Current selectable-map navigation data needs revalidation.
- The existing export preset is not a clean, verified release pipeline.

## What should be preserved

These are architectural or content contracts that future work should treat as protected unless a deliberate redesign is approved:

- `GameConfig` as the single shared source of match rules.
- `GameEvents` as the cross-system gameplay signal bus.
- Autoload order in `project.godot`.
- The scarcity identity: one gun per map/match and no casual addition of ammo or extra guns.
- Authored `spawn_point`, `gun_spawn_point`, `item_spawn_point`, `powerup_spawn_point`, and melee placements in current maps.
- Stable online actor identity separate from ENet owner identity.
- Host authority for combat, item effects, powerups, elimination, round state, and scoring.
- Online code gated behind `NetworkManager.is_online()` so local play remains isolated.
- The single human controller scene with `p1_`/`p2_` input-prefix behavior.
- Pickup registration through overlap areas and the `pick_up() -> bool` contract.
- The existing cat mascot, rig, materials, animations, hand attachments, and import settings until a character-art phase is explicitly approved.
- Deterministic original asset generators for Forest, Western V2, City, and generated item models.
- The three user-tuned selectable maps; the City builder is explicitly marked retired for rebuilds.

## Verification results

### Blender

- Installed executable: `D:\Blender\blender.exe`.
- Verified version: Blender 5.1.2.
- The current cat gameplay model imports successfully with one armature, one action, about 33,376 triangles, and one 2048x2048 color texture.
- `Dance.glb`, the runtime animation source, imports with one armature and 11 actions.
- The orange bot model imports successfully but is about 660,636 triangles with four 2048x2048 images and is substantially over budget.
- Four asset generators are present and runnable in principle, but all output paths are hardcoded absolute paths.
- There are no `.blend` source files in the repository.

### Godot

- Installed executable: `D:\GodotEngine\Godot_v4.6.3-stable_win64.exe`.
- Verified engine build from smoke output: Godot 4.6.3 stable.
- Project/editor initialization completed its file scan and layout stages, but Terrain3D native-library hot reload failed while another Godot editor process had the debug DLL in use. The restricted audit environment also prevented Godot from writing normal AppData editor caches, so those AppData errors are environment-specific.
- The two-peer online lobby smoke test passed for host and client.
- CityMap online-bot smoke passed for host and client.
- ForestMap full match smoke failed once at Magnet Hands host movement, then passed on repeat. The passing run still logged multiplayer despawn/synchronization warnings and exit leaks.
- WesternV2Map full match smoke failed twice at the same Magnet Hands host movement check; the client then timed out because the host test exited.
- Smoke-process shutdown repeatedly reports ObjectDB/RID leaks. Some may be caused by abrupt test teardown, but they remain observable diagnostics.
- Real two-machine Tailscale play is still required; loopback smoke tests cannot validate actual latency, firewall behavior, or discovery across two machines.

## Documentation state before this audit

Useful existing documentation is present, especially `docs/ARCHITECTURE.md`, `docs/GAME_RULES.md`, `docs/CODING_STANDARDS.md`, and the resolved-history section of `docs/TODO.md`. However, several statements are obsolete or internally contradictory:

- `docs/DESIGN.md` still calls online play stubbed and says bots do not use items.
- `docs/GAME_RULES.md` says one melee weapon exists, while current selectable maps author 6-8 melee instances and online preserves all of them.
- Powerups are described both as cycling and fixed at spawn.
- `docs/TODO.md` begins with items marked missing even though later entries record them as implemented.
- Older map names and claims about baked navmeshes no longer match the scene files.
- `docs/TODO.md` calls `docs/CODING_STANDARDS.md` empty, but it is a substantial standards document.

For current behavior, code and scene files should be treated as authoritative until the older documents are reconciled.

## New audit documentation

- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md): folders, scenes, autoloads, and high-level architecture.
- [GAMEPLAY_SYSTEMS.md](GAMEPLAY_SYSTEMS.md): player, combat, scoring, bots, items, powerups, audio, and multiplayer.
- [UI_AUDIT.md](UI_AUDIT.md): menus, HUDs, lobby, settings, placeholder UI, and UI risks.
- [ART_AUDIT.md](ART_AUDIT.md): models, textures, materials, shaders, audio, character, duplicates, placeholders, and Blender pipeline.
- [MAP_AUDIT.md](MAP_AUDIT.md): every current and legacy map-like scene.
- [TECH_DEBT.md](TECH_DEBT.md): prioritized debt and risks, without implementation.
- [FUTURE_RECOMMENDATIONS.md](FUTURE_RECOMMENDATIONS.md): ordered future work recommendations only.

## Audit conclusion

The project has a strong playable core and a surprisingly complete online vertical slice. The next responsible step is to establish a reliable baseline: reconcile documentation, reproduce and isolate the Magnet Hands smoke failure, verify current-map navigation in the editor, and confirm the export/Tailscale paths. New feature development before those checks would increase uncertainty around systems that already span local play, online authority, bots, UI, and map-specific content.

This audit stops at documentation. No Phase 2 work is included.
