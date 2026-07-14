# One Gun — Architecture

> Godot 4.6, Forward+ rendering, Jolt physics. Git is initialized. There are still several stray Godot autosave `.tmp` files in the project root (`game_setup.tscn*.tmp`, `node_3d.tscn*.tmp`) from unsaved/crashed editor sessions — worth cleaning up (see [TODO.md](TODO.md)).

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
- Weapon/item slot management: `active_slot` state (`"none"` / `"weapon"` / `"item1"` / `"item2"`), `get_hold_point()` / `get_melee_hold_point()` / `get_item_hold_point()` node lookups for attaching held objects. See §6 for the full pickup/swap/hold-drop architecture.
- `nearby_interactables`: an array populated by pickup Area3Ds registering themselves (`register_interactable`) so the player/bot knows what's in pickup range without polling the scene tree.
- Status effects: knockback, stagger, slow, bullet immunity, disarm-shield — all implemented as timers/flags on the controller itself, applied externally by `melee_weapon.gd`, `bullet.gd`, or `bubble_gum_trap.gd`.
- Animation: merges multiple GLB animation sources into one `AnimationPlayer` at runtime (`ANIM_SOURCE_GLB` + per-clip scenes under `models/playerAnimations/`), keyed by string constants (`ANIM_IDLE`, `ANIM_RUN`, etc.) mapped to indices.

## 4. Weapons Architecture

- `weapon_data.gd` — a `Resource` subclass holding a melee weapon's static stats (reach, windup/active/recovery base times, stamina cost, held pose offsets, model path). `melee_weapon_registry.gd` constructs one `WeaponData` instance per weapon type at `_ready()` and hands out random picks.
- `melee_weapon.gd` (on `melee_weapon.tscn`) is the single scene used for whichever weapon/tier/effect combination the registry rolled — the model, stats, and effect are applied onto one generic scene rather than having 5 separate weapon scenes. Tier/effect are resolved via `MeleeWeaponRegistry.get_stats_for_tier()` and `get_random_effect()`.
- `gun.gd` (on `gun.tscn`) is a `RigidBody3D`: physics-frozen and parented to the holder's hold point while held; unfrozen and dropped on death/disarm; `reset_to_spawn()` each round.
- `bullet.gd` (on `bullet.tscn`) is fire-and-forget: instantiated by `gun.fire()`, travels at a fixed speed, checks `GameConfig.can_affect()` (teams/friendly-fire) and target bullet-immunity, then eliminates and frees itself on contact.

## 5. Items & Powerups Architecture

- `item.gd` (`item.tscn`, `grenade.tscn`) — generic held/throwable consumable container, data-driven via `item_type` + `deployed_scene`, backing both the bubble gum trap and the grenade. An exported `fuse_time` (default 0) controls detonation timing: `0` means "deploy on first contact" (bubble gum trap's behavior — `_on_flight_body_entered` triggers `_deploy()` immediately); `> 0` means the item ignores contact entirely and instead runs its own concurrent countdown (`_start_fuse_timer()`) that calls `_deploy()` after `fuse_time` seconds regardless of whether/where it has landed (the grenade's behavior). This is the pattern to extend for any future fuse-based item — don't fork a second copy of `item.gd`.
- `bubble_gum_trap.gd` (`bubble_gum_trap.tscn`) — the deployed hazard instance spawned when a thrown item lands; owns its own **lingering** Area3D slow effect and respawn timer, independent of the item pickup itself. Stays live until players walk into it or its lifetime expires.
- `grenade_explosion.gd` (`grenade_explosion.tscn`) — the grenade's deployed instance, but architecturally the opposite of the bubble gum trap: it's a **one-shot** effect, not a lingering hazard. On `_ready()` it immediately queries all `"player"`-group nodes, applies knockback to everyone within its radius (respecting `GameConfig.can_affect()`), plays a brief flash tween, then frees itself. No Area3D/`body_entered` — the blast either catches you at the instant it detonates or it doesn't.
- `powerup.gd` (`powerup.tscn`) — single map pickup, self-cycling type on a timer, applies its effect directly to the player on Area3D contact (`apply_powerup()` called on the player controller), then respawns itself after a delay.
- `powerup_status.gd` — pure UI, listens for active powerup state on the local player to render the countdown stack; not itself a gameplay system.
- **Throw arc**: `item.gd` and `melee_weapon.gd` each have their own `throw()` (no shared base class, per the duplication pattern noted in §13) but use the same physics shape: impulse in the full 3D aim direction (`get_aim_direction()`, pitch included) plus a fixed upward boost constant (`THROW_ARC_UPWARD_BOOST`, 4.0 in both), so throws arc even when aiming level instead of skidding flat. If one is retuned, check whether the other should match.

## 6. Pickup / Interact / Swap Architecture

The interact button drives all pickup, swap, and voluntary-drop behavior through one per-frame decision in `character_body_3d.gd._physics_process()` — see `docs/GAME_RULES.md` §9 for the player-facing behavior this implements.

- **`pick_up()` returns a `bool` now, on every pickup-able object** (`gun.gd`, `melee_weapon.gd`, `item.gd`) — `true` if the pickup/swap happened, `false` if it refused. This is the core contract: `character_body_3d.gd._try_interact()` just loops `nearby_interactables` calling `pick_up(self)` until one succeeds; it does not pre-compute eligibility (empty slot? valid swap? gun exception?) — each object decides for itself and reports back. Any future pickup type should follow this contract rather than having the player special-case it.
- **Tap vs. hold** is resolved once, at press time: if `_try_interact()` returns `false` (nothing nearby could be picked up/swapped), the press starts a hold timer (`interact_hold_active` + `interact_hold_timer`, threshold `INTERACT_HOLD_DROP_TIME` = 0.5s); crossing the threshold while still held fires `_drop_active_slot()` once. If `_try_interact()` succeeds, no hold timer starts at all — holding the button afterward does nothing.
- **Swap-in-place**: when an object's `pick_up()` needs to bump something the player already holds (melee-for-melee, melee-for-gun, item-for-item), it captures its own `global_position` before anything moves, calls `.drop()` on the old object, then repositions the old object to that captured spot. This is what makes the displaced item land exactly where the new one was instead of at the player's feet.
- **The gun exception is enforced in `melee_weapon.gd`, not the player**: `pick_up()` returns `false` immediately if `p.holding_gun` is true, with no auto-drop. Putting this at the object level (rather than only gating it in the player's input code) means it can't be bypassed by another caller — bots included, even though they call `pick_up()` directly with no tap/hold concept at all.
- **Item slots are dual, weapon slot stays singular**: `character_body_3d.gd` exposes `held_item_1`/`held_item_2` plus a small interface — `can_pick_up_item()`, `assign_item()`, `clear_item_slot()`, `get_active_item()` — that `item.gd` calls generically instead of touching slot fields directly. `dummy.gd` (bots) implements the same method names against its own single `held_item` field, so `item.gd` has one code path for both: `if p.has_method("can_pick_up_item"): ... elif "held_item" in p: ...`.
- **Bots bypass the tap/hold system by design, not oversight**: `dummy.gd` keeps a simpler single-`held_item` model and calls `pick_up()` directly — every bot pickup is effectively an instant tap. The gun exception above still protects bots as a free side effect, and bots additionally already gate their own melee-pickup attempts on `not holding_gun` before ever calling `pick_up()`.
- **Both item slots share one physical attachment point**: there's no second `ItemHoldPoint` node on the character model, so `held_item_1` and `held_item_2` both parent under the same node when held. `_update_active_slot_and_visuals()` toggles each held item's `.visible` individually based on which slot is active, so only one item is ever rendered in-hand even though both are legitimately held.

## 7. Round/Match State Machine (`round_manager.gd`)

Owns a single `round_state` string machine: `"countdown" → "live" → "ended"` (repeating per round), plus `round_number`/`set_number` counters and per-player dictionaries (`round_wins`, `match_points`, `stat_kills`, `stat_deaths`, `stat_disarms`, `stat_pickups`, `stat_melee`). It:
- Spawns bots at `_ready()` from `GameConfig.bot_configs`.
- Filters players to those relevant to the current mode (drops P2 if splitscreen is off).
- Subscribes to `GameEvents` (`player_eliminated`, `player_disarmed`, `gun_picked_up`, `melee_hit_landed`) to update stats — **this is the only consumer of most of these signals for scoring purposes**; UI systems (kill feed, HUD) subscribe to the same signals independently for presentation.
- Computes scoreboard data on demand (`get_scoreboard_data()`), sorted by sets then rounds.
- Drives round/set/match end transitions and countdown timing, using the `@export` timing vars as the single source of truth for banner durations.

## 8. Global Event Bus (`game_events.gd`)

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

## 9. UI Architecture

UI is composed of small, single-responsibility scripts, each polling or listening to one thing and rendering it, rather than one large HUD controller:

- `match_hud.gd` — round/set banner, remaining-player drama states, scoreboard overlay (TAB), notification toasts (via `hud_notification`).
- `gun_ui.gd` / `melee_ui.gd` / `reload_spinner.gd` — weapon-specific status, mutually exclusive display depending on `active_slot`.
- `inventory_slots.gd` — the three-slot (weapon, item1, item2) display, including a per-slot `HoldBar` (`ProgressBar`) that fills while that slot's `interact_hold_active`/`interact_hold_timer` hold-to-drop is in progress (see §6).
- `item_ui.gd` — shows whichever item slot is currently active (mirrors how `gun_ui.gd`/`melee_ui.gd` only show while the weapon slot is active), not both items at once.
- `stamina_bar.gd` / `dash_charges.gd` / `powerup_status.gd` — player-resource displays, each reading directly off the local player controller.
- `crosshair.gd`, `kill_feed.gd`, `status_label.gd`, `round_label.gd` — presentation-only, driven by either direct player state or `GameEvents`.
- `player_ui_container.gd` — likely the per-viewport root that composes the above per split-screen pane (confirm scene composition before extending).

## 10. Splitscreen & Spectating

- `splitscreen_manager.gd` maintains two `SubViewport`s (P1 left, P2 right), copying each player's camera transform into the corresponding viewport's `Camera3D` every frame. When `GameConfig.split_screen_enabled` is false, P2's viewport is hidden and P1's stretches full width — same scene tree either way, just visibility/sizing changes.
- `spectator_controller.gd` takes over for a player after their death animation finishes, offering a follow-cam (cycle through living players) or free-fly cam, with its own input handling layered on top of (not replacing) the eliminated player's controller.

## 11. Menus & Settings

- `main_menu.gd` — page-based (MAIN/MULTI) with animated transitions; owns the live 3D background viewport (`title_bg_map.tscn` + `title_background.gd`).
- `game_setup.gd` — the lobby: map selection, bot config popup, collapsible match-settings panel (mirrors `GameConfig` fields 1:1), preset save/load UI, per-player ready state.
- `player_settings.gd` (`player_settings.tscn`) — dual-mode: standalone (from main menu, returns to `main_menu.tscn`) or overlay (from pause menu, emits `settings_closed` instead of navigating).
- `pause_menu.gd` / `pause_manager.gd` — pause overlay + the ESC-routing singleton described in §1.

## 12. Online Multiplayer

- `NetworkManager` is an autoload over ENet intended for Tailscale peers. It owns host/join, the peer roster and names, host-to-client `GameConfig`/map sync, a monotonically increasing match ID, coordinated scene changes, and a match-scene readiness handshake. The host does not spawn network actors until every connected peer reports that its map and `MultiplayerSpawner` path are ready.
- Online maps reuse the local map scenes without editing them. `round_manager.gd` removes the baked local players, splitscreen and local HUD at runtime, creates `NetPlayers`, and host-spawns one `player.tscn` actor per peer plus the host-configured `DummyModel.tscn` bots.
- A network actor has an `actor_id` (match/scoring identity) separately from `owner_peer_id` (the controlling ENet peer). Human actor IDs equal their peer IDs; bots use IDs beginning at 10000 and are owned by peer 1. `net_authority_id` remains the Godot replication authority.
- Movement is owner-authoritative and replicated by a runtime-built `MultiplayerSynchronizer` (position, body rotation, aim yaw/pitch, velocity and stamina). Gun pickup, firing, bullet hits and elimination are host-resolved. Requests are bound to `multiplayer.get_remote_sender_id()` and checked against round epoch/state, ownership, alive state, pickup distance, reload state and aim direction.
- Online gun reload completion is broadcast by the host. Bullets carry the round epoch that created them, so a late collision cannot eliminate an actor after the match has advanced to a different round.
- Online melee uses `round_manager.gd` as a stable RPC coordinator because each `melee_weapon.gd` node can be reparented between the map and a player's hand. Every melee placement authored in a map is preserved and activated; the host rolls an independent synchronized weapon type/effect/tier identity for each placement every round. Each placement has a stable candidate ID so pickup/swing/drop/throw traffic reaches the same weapon on every peer. The host validates those requests, resolves hitboxes, effects, disarms and melee eliminations, and broadcasts swing/throw/landing/reset presentation.
- Online items use the same stable `RoundManager` coordinator because they are reparented into either of a player's two item slots. Every authored `item_spawn_point` and `powerup_spawn_point` is preserved; the host rolls assignments and broadcasts their exact marker transforms each round. Pickup distance/ownership, drops, throw aim, fuse/contact deployment, mid-round rerolls, powerup collection, Second Wind, disarm shields, Magnet Hands and deployed gameplay effects are host-resolved. Clients simulate thrown visuals, but the host broadcasts the final deployable position and effect targets. Deployed instances have host-issued IDs so trap/pad/decoy presentation events address the same object on every peer.
- Host/join always tears down an earlier ENet peer before opening a new one, and a join that never completes fails after 12 seconds instead of leaving the menu stuck. The host advertises its chosen lobby name on UDP 24546; a joiner reads the local Tailscale peer list and probes those peers for an exact name match before opening the gameplay ENet connection on UDP 24545. Direct `100.x` entry remains a fallback and no public rendezvous service is involved. Roster updates include the session name, and each peer can edit only its own synchronized display name. Leaving the online screens explicitly closes the peer. Online lobby previews keep their environmental animation processing active and render internally at 960×540 while the ENet session is alive.
- Phase status: connection/movement, gun combat, melee combat, items/powerups, host-owned bots, the host-authoritative FFA round/set/match loop, coordinated round resets and the online HUD are implemented. Online bot count/difficulty is host-configured in the lobby, capped so humans plus bots never exceed eight; only the host runs bot AI/physics while clients render synchronized puppets. Bots use the same actor-state scoring and host-resolved weapon/item paths as humans. The HUD binds to the locally owned actor and renders countdown/winner banners, alive count, scores/stats (including melee hits/disarms), kill feed, stamina, dash charges, weapon/reload state, all three inventory slots, active powerups, spectator state and remote name tags. It also creates an online ESC overlay without pausing `SceneTree`: the host can return all peers to the lobby or main menu, while a client sees no lobby-return control and its main-menu action disconnects only that client. Online team assignment is not implemented, so team/friendly-fire settings are explicitly disabled online.

## 13. Data-Driven Patterns Worth Preserving

- **Input prefix pattern**: all input reads go through `input_prefix + "_action"` — new player-specific actions must follow this convention or splitscreen will silently break for one player.
- **Interactable registration**: pickup objects register themselves into the player's `nearby_interactables` array rather than the player scanning the tree — new pickup types should follow this registration pattern to stay consistent with gun/melee/item pickup.
- **`pick_up()` returns success/failure, not void**: since §6's rework, every pickup-able object's `pick_up()` returns `true`/`false` so the caller can tell whether anything happened — required for the player's tap-vs-hold decision. Any new pickup type must follow this contract.
- **Tier stats as data, not code branches**: `melee_weapon_registry.get_stats_for_tier()` computes tier scaling from multipliers rather than hardcoded per-tier stat blocks — adding a weapon means adding one `_build_x()` function, not touching tier logic.
- **GameConfig as single source of truth for rules**: UI (lobby toggles), gameplay (round manager, weapons), and persistence (presets) all read/write the same autoload fields — avoid shadowing these values locally in gameplay scripts.

## 14. Known Structural Gaps

See [TODO.md](TODO.md) for the full list; architecturally significant ones:
- Online team assignment is still absent; online matches remain FFA.
- No shared base class between `character_body_3d.gd` (human) and `dummy.gd` (bot) despite significant behavioral overlap — tuning drift risk.
- No admin/debug console for runtime testing (spawning items, forcing round state, teleporting).
