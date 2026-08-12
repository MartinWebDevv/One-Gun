# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project

**One Gun** — a local (splitscreen or solo + bots) Godot 4.7.1 arena shooter. GDScript, Forward+ rendering, Jolt physics. Full project docs live in `docs/` and are kept current — read the relevant one before making non-trivial changes to a system rather than re-deriving it from scratch:

- `docs/GAME_RULES.md` — mechanics, numbers, match settings (source of truth for balance/tuning values)
- `docs/DESIGN.md` — the design intent/pillars behind those mechanics
- `docs/ARCHITECTURE.md` — full technical breakdown of every system and how they connect
- `docs/TODO.md` — known gaps, incomplete features, technical debt

## Running / verifying changes

No CLI build or lint framework exists in this project, and `godot` is not on PATH — but Godot 4.7.1 is available at `D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe`. Use it headlessly to catch script/scene errors after edits, e.g.:

```
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --quit
```

This surfaces GDScript parse errors and broken resource references without opening the editor UI. The project also has targeted validation scenes/scripts under `tools/`, but they are not a substitute for actually playing the game, so gameplay/feel changes still need a human editor playtest.

## Architecture essentials

- **Scarcity model**: exactly one gun (`gun.tscn`/`gun.gd`) exists per match. Every authored `melee_spawn_point` starts populated and independently refills with a fresh randomized instance 5s after pickup, so multiple carried melee weapons may accumulate. Do not casually add ammo pickups or extra guns without checking `docs/DESIGN.md` first.
- **Autoloads** (declared in `project.godot` `[autoload]`, load order matters): `GameEvents` (signal bus) → `GameConfig` (all match rules + disk-backed presets) → `PlayerPrefs` (personal settings) → `PauseManager` (ESC routing) → `MeleeWeaponRegistry` → `ThemeManager` → `AudioManager`.
- **`GameConfig` is the single source of truth for match rules** — lobby UI (`game_setup.gd`), gameplay scripts, and the preset save/load system all read/write the same autoload fields. Don't shadow these values locally in a script.
- **`GameEvents` is the only cross-system coupling** for match events — gameplay code never holds direct references to UI or `round_manager.gd`; everything communicates by emitting/listening to its signals.
- **Splitscreen is one script, two instances**: `character_body_3d.gd` drives both P1 and P2, differentiated only by an exported `input_prefix` (`"p1"`/`"p2"`). Any new input action must follow the `input_prefix + "_action_name"` convention or it will silently break for one player.
- **Bots (`dummy.gd`) are a separate script from the human controller**, not a shared base class — movement/combat tuning constants (speed, stamina, dash) are duplicated by hand between the two. Changes to `character_body_3d.gd` constants do not automatically apply to bot behavior; update both if parity matters.
- **Pickup registration pattern**: interactable objects (gun, melee weapon, items) register themselves into the player's `nearby_interactables` array on `Area3D` overlap rather than the player polling the scene tree. Follow this pattern for any new pickup type.
- **Online multiplayer (Phases 1–2e, 2026-07-11 to 2026-07-13):** `NetworkManager` autoload (`network_manager.gd`) does ENet host/join over Tailscale (gameplay UDP 24545; named-lobby discovery UDP 24546), roster/name exchange, host→client match-config/map sync, coordinated scene load and an all-peer scene-ready handshake. Players normally join by a host-chosen lobby name discovered across the Tailscale peer list; direct `100.x` entry remains a fallback. Host/join first closes any stale peer, and incomplete joins time out after 12 seconds. In-map, `round_manager.gd` runtime-strips baked local players/splitscreen/HUD, then spawns human actors plus host-configured bots through one `MultiplayerSpawner`. Humans own their movement; bots use stable actor IDs from 10000 upward, are owned/run only by peer 1, and replicate to clients as puppets. Gun, melee, item and powerup actions/effects are host-resolved, actor-ID addressed and round-epoch guarded; reparented melee/items route traffic through stable `RoundManager` RPCs. Every authored melee/item/powerup/player-spawn marker remains intact. The online HUD includes scoring, local-style inventory slots, matching stamina-width dash pips, active powerups and a local-only ESC overlay. Only the host can return everyone to the lobby or main menu; a client can leave to the main menu without ending the host session. Online teams/friendly fire are disabled until peer team assignment exists. All online code is gated behind `is_online()`; local play is untouched.

## Asset budgets (prevents editor crashes)

AI-generated models (Tripo, Meshy, etc.) ship absurdly heavy by default — ~1M triangles and four 4096×4096 textures *per prop*, which once crashed the editor outright when a scene stacked a dozen of them. Before adding any new `.glb` to the project, check its file size: **anything over ~10 MB needs optimizing first.** Budget guidance: props (bottles, furniture) ≤ ~15k tris + 1024² textures; buildings/landmarks ≤ ~100k tris + 2048² textures.

The established pipeline (Node.js is installed) preserves shape within 0.1% and keeps the same file path so scene references never break:

```
npx -y @gltf-transform/cli simplify in.glb tmp.glb --error 0.001
npx -y @gltf-transform/cli resize tmp.glb in.glb --width 1024 --height 1024
```

Pre-optimization originals of all `models/westernAssets/` files are backed up at `D:\Godot Projects\one-gun_originalAssets_backup\`.
