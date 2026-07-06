# One Gun — Architecture

> Godot 4.6, Forward+ rendering, Jolt physics. No git repo is initialized for this project as of 2026-07-06; there's an `ONEGUN.zip` in the project root that looks like a manual backup, and several stray Godot autosave `.tmp` files (`game_setup.tscn*.tmp`, `node_3d.tscn*.tmp`) from unsaved/crashed editor sessions — worth cleaning up (see [TODO.md](TODO.md)).

## 1. Autoloads (Singletons)

Registered in `project.godot` under `[autoload]`, load order as listed:

| Singleton | Script | Responsibility |
|---|---|---|
| `GameEvents` | `game_events.gd` | Global signal bus — the only cross-system coupling mechanism for match events |
| `GameConfig` | `game_config.gd` | All match-rule state (teams, melee lethality, dash charges, item toggles, bot configs) + disk-backed preset save/load (`user://match_preset_slots.json`, 5 slots) |
| `PlayerPrefs` | `player_prefs.gd` | Personal settings (volume, sensitivity, FOV, crosshair color, sprint toggle mode) — disk-backed (`user://player_prefs.json`), always-on autosave, distinct from `GameConfig`'s shared "house rules" |
| `PauseManager` | `pause_manager.gd` | Owns ESC key routing (`PROCESS_MODE_ALWAYS`) so nested overlays can claim `escape_override` instead of every screen handling ESC independently |
| `MeleeWeaponRegistry` | `melee_weapon_registry.gd` | Defines the 5 `WeaponData` resources (Sword/Bat/Stick/Crowbar/Frying Pan) and tier/effect randomization logic |
| `ThemeManager` | `theme_manager.gd` | Builds and applies the shared `Theme` resource at startup (saves to `res://one_gun_theme.tres`) |
| `AudioManager` | `audio_manager.gd` | Music/SFX playback, bus volume control, `PROCESS_MODE_ALWAYS` |

## 2. Scene Flow

```
main_menu.tscn  →  game_setup.tscn (lobby)  →  <selected map>.tscn (match)  →  back to main_menu.tscn
                                                        │
                                          RoundManager (per-map Node) drives
                                          round/set/match state for that scene
```

- Maps live under `maps/test/` (`NewMap.tscn`, `NukeTownMap.tscn`) plus a root-level `node_3d.tscn` (Coliseum-style arena) and `title_bg_map.tscn` (used only as the main menu's live 3D background).
- Each map scene contains its own `RoundManager` node instance (`round_manager.gd`), spawn-point markers (`spawn_point` group), and a `gun_spawn_point` group for `"random"` gun spawn mode.
- Player instances come from `player.tscn`; bots are spawned at runtime from `DummyModel.tscn` (`dummy.gd`) by `RoundManager._spawn_bots()`.

## 3. Player Architecture

`character_body_3d.gd` (attached to `player.tscn`, a `CharacterBody3D`) is the single script driving both P1 and P2 in splitscreen — differentiated entirely by the exported `input_prefix` (`"p1"` / `"p2"`) and `use_gamepad_look` flag, rather than by separate scripts or scenes. This is the key pattern for the whole input layer: every `Input.is_action_*` call is built as `input_prefix + "_action_name"`, so splitscreen support is a matter of instancing the same scene twice with different prefixes, not maintaining parallel code paths.

Bots (`dummy.gd`) are a **separate script** from the human controller, not a subclass or a shared-base-class specialization — they reimplement movement/combat decisions independently, driven by a difficulty-tuned decision loop (`_decide_objective`) instead of input polling. This means gameplay-affecting tuning (speed, stamina, dash) that lives as `const` in `character_body_3d.gd` must be mirrored by hand in `dummy.gd` if it needs to match; there's no shared base class enforcing parity.

Key subsystems inside `character_body_3d.gd`:
- Movement/physics (`_physics_process`): walk/sprint/jump/dash, stamina drain/regen.
- Weapon/item slot management: `active_slot` state (`"none"`/`"weapon"`/`"item"`), `get_hold_point()` / `get_melee_hold_point()` / `get_item_hold_point()` node lookups for attaching held objects.
- `nearby_interactables`: an array populated by pickup Area3Ds registering themselves (`register_interactable`) so the player/bot knows what's in pickup range without polling the scene tree.
- Status effects: knockback, stagger, slow, bullet immunity, disarm-shield — all implemented as timers/flags on the controller itself, applied externally by `melee_weapon.gd`, `bullet.gd`, or `bubble_gum_trap.gd`.
- Animation: merges multiple GLB animation sources into one `AnimationPlayer` at runtime (`ANIM_SOURCE_GLB` + per-clip scenes under `models/playerAnimations/`), keyed by string constants (`ANIM_IDLE`, `ANIM_RUN`, etc.) mapped to indices.

## 4. Weapons Architecture

- `weapon_data.gd` — a `Resource` subclass holding a melee weapon's static stats (reach, windup/active/recovery base times, stamina cost, held pose offsets, model path). `melee_weapon_registry.gd` constructs one `WeaponData` instance per weapon type at `_ready()` and hands out random picks.
- `melee_weapon.gd` (on `melee_weapon.tscn`) is the single scene used for whichever weapon/tier/effect combination the registry rolled — the model, stats, and effect are applied onto one generic scene rather than having 5 separate weapon scenes. Tier/effect are resolved via `MeleeWeaponRegistry.get_stats_for_tier()` and `get_random_effect()`.
- `gun.gd` (on `gun.tscn`) is a `RigidBody3D`: physics-frozen and parented to the holder's hold point while held; unfrozen and dropped on death/disarm; `reset_to_spawn()` each round.
- `bullet.gd` (on `bullet.tscn`) is fire-and-forget: instantiated by `gun.fire()`, travels at a fixed speed, checks `GameConfig.can_affect()` (teams/friendly-fire) and target bullet-immunity, then eliminates and frees itself on contact.

## 5. Items & Powerups Architecture

- `item.gd` (`item.tscn`) — generic held/throwable consumable container, currently backing only the bubble gum trap.
- `bubble_gum_trap.gd` (`bubble_gum_trap.tscn`) — the deployed hazard instance spawned when a thrown item lands; owns its own Area3D slow effect and respawn timer, independent of the item pickup itself.
- `powerup.gd` (`powerup.tscn`) — single map pickup, self-cycling type on a timer, applies its effect directly to the player on Area3D contact (`apply_powerup()` called on the player controller), then respawns itself after a delay.
- `powerup_status.gd` — pure UI, listens for active powerup state on the local player to render the countdown stack; not itself a gameplay system.

## 6. Round/Match State Machine (`round_manager.gd`)

Owns a single `round_state` string machine: `"countdown" → "live" → "ended"` (repeating per round), plus `round_number`/`set_number` counters and per-player dictionaries (`round_wins`, `match_points`, `stat_kills`, `stat_deaths`, `stat_disarms`, `stat_pickups`, `stat_melee`). It:
- Spawns bots at `_ready()` from `GameConfig.bot_configs`.
- Filters players to those relevant to the current mode (drops P2 if splitscreen is off).
- Subscribes to `GameEvents` (`player_eliminated`, `player_disarmed`, `gun_picked_up`, `melee_hit_landed`) to update stats — **this is the only consumer of most of these signals for scoring purposes**; UI systems (kill feed, HUD) subscribe to the same signals independently for presentation.
- Computes scoreboard data on demand (`get_scoreboard_data()`), sorted by sets then rounds.
- Drives round/set/match end transitions and countdown timing, using the `@export` timing vars as the single source of truth for banner durations.

## 7. Global Event Bus (`game_events.gd`)

A minimal autoload exposing 6 signals with no listener/emitter registration logic — pure pub/sub:

| Signal | Emitted by | Consumed by |
|---|---|---|
| `player_eliminated(victim_name, killer_name, weapon_icon)` | `character_body_3d.eliminate()`, `bullet.gd`, `melee_weapon.gd` | `round_manager.gd` (stats), `kill_feed.gd` (UI) |
| `player_disarmed(victim_name, disarmer_name, weapon_icon)` | `melee_weapon.gd` | `round_manager.gd`, `kill_feed.gd` |
| `gun_picked_up(player_name)` | `gun.gd` | `round_manager.gd` (stats), `match_hud.gd` (notification) |
| `gun_dropped()` | `gun.gd` | `match_hud.gd` (notification) |
| `melee_hit_landed(hitter_name)` | `melee_weapon.gd` | `round_manager.gd` (stats) |
| `hud_notification(message)` | `round_manager.gd` and other systems as needed | `match_hud.gd` |

This bus is the primary decoupling mechanism in the codebase: gameplay scripts never hold direct references to UI or the round manager, they only emit signals and let interested systems subscribe.

## 8. UI Architecture

UI is composed of small, single-responsibility scripts, each polling or listening to one thing and rendering it, rather than one large HUD controller:

- `match_hud.gd` — round/set banner, remaining-player drama states, scoreboard overlay (TAB), notification toasts (via `hud_notification`).
- `gun_ui.gd` / `melee_ui.gd` / `reload_spinner.gd` — weapon-specific status, mutually exclusive display depending on `active_slot`.
- `inventory_slots.gd` — the two-slot (weapon/item) display.
- `stamina_bar.gd` / `dash_charges.gd` / `powerup_status.gd` — player-resource displays, each reading directly off the local player controller.
- `crosshair.gd`, `kill_feed.gd`, `status_label.gd`, `round_label.gd` — presentation-only, driven by either direct player state or `GameEvents`.
- `player_ui_container.gd` — likely the per-viewport root that composes the above per split-screen pane (confirm scene composition before extending).

## 9. Splitscreen & Spectating

- `splitscreen_manager.gd` maintains two `SubViewport`s (P1 left, P2 right), copying each player's camera transform into the corresponding viewport's `Camera3D` every frame. When `GameConfig.split_screen_enabled` is false, P2's viewport is hidden and P1's stretches full width — same scene tree either way, just visibility/sizing changes.
- `spectator_controller.gd` takes over for a player after their death animation finishes, offering a follow-cam (cycle through living players) or free-fly cam, with its own input handling layered on top of (not replacing) the eliminated player's controller.

## 10. Menus & Settings

- `main_menu.gd` — page-based (MAIN/MULTI) with animated transitions; owns the live 3D background viewport (`title_bg_map.tscn` + `title_background.gd`).
- `game_setup.gd` — the lobby: map selection, bot config popup, collapsible match-settings panel (mirrors `GameConfig` fields 1:1), preset save/load UI, per-player ready state.
- `player_settings.gd` (`player_settings.tscn`) — dual-mode: standalone (from main menu, returns to `main_menu.tscn`) or overlay (from pause menu, emits `settings_closed` instead of navigating).
- `pause_menu.gd` / `pause_manager.gd` — pause overlay + the ESC-routing singleton described in §1.

## 11. Data-Driven Patterns Worth Preserving

- **Input prefix pattern**: all input reads go through `input_prefix + "_action"` — new player-specific actions must follow this convention or splitscreen will silently break for one player.
- **Interactable registration**: pickup objects register themselves into the player's `nearby_interactables` array rather than the player scanning the tree — new pickup types should follow this registration pattern to stay consistent with gun/melee/item pickup.
- **Tier stats as data, not code branches**: `melee_weapon_registry.get_stats_for_tier()` computes tier scaling from multipliers rather than hardcoded per-tier stat blocks — adding a weapon means adding one `_build_x()` function, not touching tier logic.
- **GameConfig as single source of truth for rules**: UI (lobby toggles), gameplay (round manager, weapons), and persistence (presets) all read/write the same autoload fields — avoid shadowing these values locally in gameplay scripts.

## 12. Known Structural Gaps

See [TODO.md](TODO.md) for the full list; architecturally significant ones:
- No networking layer exists at all (not stubbed at the protocol level, just a disabled menu button) — "Online" is a menu-only placeholder.
- No shared base class between `character_body_3d.gd` (human) and `dummy.gd` (bot) despite significant behavioral overlap — tuning drift risk.
- No admin/debug console for runtime testing (spawning items, forcing round state, teleporting).
