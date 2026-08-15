# One Gun Project Structure

## Repository organization

The project is functional but physically flat. Most gameplay scenes and scripts live directly in the repository root, while maps, art, audio, tools, documentation, and the Terrain3D add-on have dedicated folders.

| Path | Purpose | Audit notes |
|---|---|---|
| `/` | Core gameplay, autoloads, menus, HUD scripts, player/weapon/item scenes, project settings | 163 top-level files; the main maintainability pressure point |
| `docs/` | Rules, design, architecture, standards, TODO/history | Substantial but contains stale and contradictory statements |
| `maps/test/` | Three current maps, one legacy map, and menu background | Folder name still says `test` even for shipping/playtest maps |
| `models/` | Character, animation, weapon, item, environment, Western, Forest, and City assets | 149 GLBs; several distinct provenance/pipeline styles |
| `Scenes/weternMap/` | Interactive saloon subscenes | Folder name contains the existing `weternMap` typo; do not rename casually because scene paths depend on it |
| `audio/` | Menu/level music, ambience, UI, weapon, and footstep audio | Large uncompressed WAV footprint; several gameplay cues absent |
| `tools/` | Deterministic Blender generators, map builders, preview script, online smoke test | Useful but partly machine-specific; City builder is retired |
| `addons/terrain_3d/` | Terrain3D 1.0.2 plug-in and native binaries | Enabled in the editor, but no current game scene contains a Terrain3D node |
| `desertTerrain/` | Terrain3D region `.res` files | No current scene/script reference found; likely legacy/orphaned content |
| `fonts/` | Fredoka variable font | Used by the shared theme |
| `export_templates/`, `feature_profiles/`, `script_templates/`, `text_editor_themes/` | Empty project-support folders | No functional content |
| `.godot/` | Godot import/editor cache | Generated; not project source |
| `.git/` | Version control | Worktree was already dirty during audit |

## Core configuration files

| File | Role |
|---|---|
| `project.godot` | Main scene, autoloads, input map, rendering/physics settings, enabled plug-ins |
| `export_presets.cfg` | Windows Desktop export preset |
| `one_gun_theme.tres` | Shared Godot theme; also regenerated/saved by `ThemeManager` |
| `AGENTS.md`, `CLAUDE.md` | Repository instructions and architectural guardrails |
| `README.md` | Setup and high-level game overview |

Project settings of note:

- Main scene: `main_menu.tscn`.
- Godot feature level: 4.6, Forward+.
- Physics: Jolt.
- Base viewport: 1600x900, fullscreen mode configured.
- Windows export preset: `One Gun v0.0.1`.
- Enabled editor plug-in: Terrain3D.

## Autoload order

Autoload order is significant and should be preserved.

| Order | Autoload | Script | Responsibility |
|---:|---|---|---|
| 1 | `GameEvents` | `game_events.gd` | Global gameplay signal bus |
| 2 | `GameConfig` | `game_config.gd` | Shared match rules, presets, teams/friendly-fire checks |
| 3 | `PlayerPrefs` | `player_prefs.gd` | Local settings, display/input preferences, persistent rebinding |
| 4 | `PauseManager` | `pause_manager.gd` | ESC routing and local/online pause behavior |
| 5 | `MeleeWeaponRegistry` | `melee_weapon_registry.gd` | Five melee definitions, fixed base handling, and randomized type/effect selection |
| 6 | `ThemeManager` | `theme_manager.gd` | Runtime theme construction and styling helpers |
| 7 | `AudioManager` | `audio_manager.gd` | Music, ambience, and pooled SFX playback |
| 8 | `NetworkManager` | `network_manager.gd` | ENet/Tailscale session, roster, discovery, config, scene coordination |

## Scene organization

### Application and lobby scenes

| Scene | Script | Purpose |
|---|---|---|
| `main_menu.tscn` | `main_menu.gd` | Runtime-built title menu with live 3D background and local/online entry |
| `game_setup.tscn` | `game_setup.gd` | Runtime-built local/online lobby, map preview, bots, rules, presets, names, ready/start |
| `player_settings.tscn` | `player_settings.gd` | Runtime-built standalone or pause-overlay settings screen |
| `maps/test/title_bg_map.tscn` | `title_background.gd` through viewport setup | Menu-only 3D background |

### Actor scenes

| Scene | Script | Purpose |
|---|---|---|
| `player.tscn` | `character_body_3d.gd` | Human player body, camera, cat rig, hand attachments, animation player |
| `DummyModel.tscn` | `dummy.gd` | Bot actor, navigation agent, bot model, hold points |
| `botmodel.tscn` | Imported animation/model scene | Orange bot visual used by `DummyModel.tscn` |
| `decoy_body.tscn` | `decoy_body.gd` | Static cat decoy deployed by the decoy item |

### Weapon and projectile scenes

| Scene | Script | Purpose |
|---|---|---|
| `gun.tscn` | `gun.gd` | Unique gun pickup, holder state, reload, firing, network validation |
| `bullet.tscn` | `bullet.gd` | Projectile and hit/elimination reporting |
| `melee_weapon.tscn` | `melee_weapon.gd` | Generic runtime-skinned melee pickup and attack lifecycle |
| `sword.tscn`, `baseball_bat.tscn`, `stick.tscn`, `crowbar.tscn`, `frying_pan.tscn` | Primarily legacy/specialized presentations | Individual melee scenes; live randomized system centers on `melee_weapon.tscn` plus registry data |

### Item and deployed-effect scenes

| Pickup scene | Deployed scene/effect | Purpose |
|---|---|---|
| `item.tscn` | `bubble_gum_trap.tscn` | Bubble gum slow trap; generic base item pattern |
| `grenade.tscn` | `grenade_explosion.tscn` | Fused radial knockback |
| `smoke_bomb.tscn` | `smoke_cloud.tscn` | Temporary smoke volume/effect |
| `bear_trap.tscn` | `bear_trap_deployed.tscn` | Snare/deployed trap |
| `spring_pad.tscn` | `spring_pad_deployed.tscn` | Launch pad |
| `decoy.tscn` | `decoy_body.tscn` | Static player decoy |
| `boomerang.tscn` | Self-contained `boomerang.gd` behavior | Thrown returning item |
| `powerup.tscn` | Direct player effect | Generic colored powerup pickup for seven powerup identities |

### Gameplay map scenes

| Status | Scene | Lobby name |
|---|---|---|
| Selectable | `maps/test/ForestMap.tscn` | Whispering Woods |
| Selectable | `maps/test/WesternV2Map.tscn` | Western Town |
| Selectable | `maps/test/CityMap.tscn` | Maple & 3rd |
| Legacy/not selectable | `node_3d.tscn` | Former Coliseum/prototype |
| Legacy/not selectable | `maps/test/NukeTownMap.tscn` | Former Explosion Town/NukeTown prototype |
| Menu only | `maps/test/title_bg_map.tscn` | No gameplay selection |

All current selectable map scenes contain local gameplay scaffolding: baked human instances, local HUD/splitscreen nodes, `RoundManager`, the gun, authored melee instances, spawn markers, item markers, and powerup markers. Online play reuses these scenes and removes/replaces local-only scaffolding at runtime.

### Map subscenes and effects

- `Scenes/weternMap/buildings/saloon/westernMap_saloon.tscn`: interactive Western saloon.
- `Scenes/weternMap/buildings/saloon/saloon_swinging_door.tscn`: swinging saloon door.
- `Scenes/weternMap/buildings/saloon/Table_set.tscn`: saloon furniture assembly.
- `tumbleweed.tscn`, plus map-effect scripts for birds, clouds, traffic, traffic lights, pond splash, shooting stars, forest ambience, and windmill animation.

### Test scene

- `tools/online_smoke.tscn` runs `online_smoke_driver.gd` for two-process loopback testing.

## Application flow

### Local flow

`main_menu.tscn` -> Local Play -> `game_setup.tscn` -> host/local lobby selections -> selected map scene -> baked local player(s), bots spawned by `RoundManager`, local HUD/splitscreen -> round/set/match loop -> lobby or main menu.

### Online flow

`main_menu.tscn` -> Online Host/Join panel -> `NetworkManager` starts or joins ENet -> `game_setup.tscn` online lobby -> host synchronizes map/config and starts -> all peers load the same map -> `RoundManager` strips local-only player/HUD/splitscreen nodes -> runtime `NetPlayers` and `MultiplayerSpawner` -> one human actor per peer plus host-owned bots -> readiness handshake -> authoritative round loop -> connected online lobby or coordinated exit.

## Script organization by responsibility

### Foundation

- `game_events.gd`
- `game_config.gd`
- `player_prefs.gd`
- `pause_manager.gd`
- `theme_manager.gd`
- `audio_manager.gd`
- `network_manager.gd`

### Match and actors

- `round_manager.gd`
- `character_body_3d.gd`
- `dummy.gd`
- `spectator_controller.gd`
- `splitscreen_manager.gd`

### Combat and content

- `gun.gd`, `bullet.gd`
- `melee_weapon.gd`, `melee_weapon_registry.gd`, `weapon_data.gd`
- `item.gd`, `boomerang.gd`
- deployed item/effect scripts
- `powerup.gd`

### UI

- `main_menu.gd`, `game_setup.gd`, `player_settings.gd`, `pause_menu.gd`
- `match_hud.gd`, `online_hud.gd`, `player_ui_container.gd`
- focused HUD widgets such as stamina, dash, inventory, reload, feed, labels, crosshair, and powerup status

### World behavior

- traffic, lighting/traffic cycle, windmill, tumbleweed, bird, cloud, pond, shooting star, and forest ambience scripts

### Tooling

- Three map builders.
- Four Blender asset generators.
- One Blender preview renderer.
- Two-process online smoke driver and PowerShell runner.

## Architecture overview

### Local architecture

- Maps own the instantiated gameplay tree.
- `RoundManager` discovers player/group content, spawns bots, initializes pickups/powerups, and drives score state.
- Human players use the same `player.tscn` and controller script; `input_prefix` differentiates P1 and P2.
- Bots are a separate controller implementation with its own constants and AI.
- Pickups register with nearby actors through overlap callbacks.
- UI reads local player state directly and listens to `GameEvents` for match events.

### Online architecture

- ENet is the transport; Tailscale supplies private connectivity and peer discovery input.
- Movement is owner-authoritative and replicated through runtime-created `MultiplayerSynchronizer` nodes.
- Combat and match results are host-authoritative.
- `RoundManager` is the stable RPC coordinator for melee, items, deployed effects, powerups, round resets, and scoring because pickups can be reparented.
- Gun RPCs remain in `gun.gd`.
- Current RPC annotations total 41: 25 in `round_manager.gd`, 8 in `gun.gd`, and 8 in `network_manager.gd`.
- Actor IDs are stable scoring identities; owner peer IDs identify control authority. Bots begin at actor ID 10000 and remain host-owned.

## Resources and data

- Match rules and presets are dictionaries/fields in `GameConfig`, not external `.tres` data.
- Melee definitions are `WeaponData` resources constructed in code by `MeleeWeaponRegistry`.
- The main shared visual theme is `one_gun_theme.tres`, also generated by `ThemeManager`.
- Terrain3D data exists as binary `.res` files under `desertTerrain/`, but no live reference was found.
- Map navigation configuration is embedded as `NavigationMesh` subresources.
- Imported asset metadata is maintained through Godot `.import` files and `.uid` files.

## Structural cautions

- Root-level organization is crowded; this audit records that fact but does not recommend a folder move during stabilization because resource paths are pervasive.
- Runtime-built UI means sparse `.tscn` files do not represent the complete UI hierarchy.
- Current maps are root-scaled to 2x. Online actor code compensates for inherited map scale; this is an important compatibility behavior.
- `Scenes/weternMap/` and other oddly named paths are already referenced by resources and should not be renamed without a dedicated migration.
- The worktree contains existing modified/untracked files. Future baseline work should identify and commit intended changes before broad development.
