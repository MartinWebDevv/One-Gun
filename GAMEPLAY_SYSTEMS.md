# One Gun Gameplay Systems

## Game loop

One Gun is an elimination-based arena game built around positional scarcity rather than health attrition. A round starts with every actor alive and ends when one player/team remains or a draw condition is detected. Round wins accumulate into sets; set wins accumulate into the match.

The defining rule is that there is one gun in the arena. A bullet eliminates. Melee attacks contest gun ownership, apply control effects, or optionally eliminate depending on lobby rules. Stamina, dash charges, item slots, pickups, and powerups are the resource layer.

Current selectable maps also contain multiple authored melee placements: Forest has 8, Western V2 has 6, and City has 7. This is the actual current scene behavior and contradicts older documentation that describes exactly one melee weapon.

## Match configuration

`GameConfig` is the shared rules source for local lobby UI, gameplay, online config snapshots, and saved presets.

Configurable rules include:

- Teams and friendly fire for local play.
- Melee lethality against gun holders or anyone.
- Whether melee effects can affect anyone.
- Melee spawn delay, breaking, drop/despawn timing, and disarm lock.
- Gun center/random spawn mode.
- Maximum dash charges.
- Rounds required per set and sets required per match.
- Hazard/consumable category toggles and per-item enable flags.
- Bot count, difficulty, and local team identity.

Up to five match presets are saved to `user://match_preset_slots.json`. Personal controls and display/audio choices belong to `PlayerPrefs`, not `GameConfig`.

Important audit finding: the live item registry contains seven items, but `GameConfig.DEFAULT_VALUES.item_registry` contains only bubble gum and grenade. Resetting to defaults can therefore discard the five newer registry entries. Unknown items default to enabled, but category/per-item controls can no longer address them consistently through the registry.

## Player system

### Scene composition

`player.tscn` is a `CharacterBody3D` containing:

- Capsule collision.
- Aim pivot, spring arm, and camera.
- Cat model, armature, skeleton, and animation player.
- Left/right hand bone attachments.
- Gun, melee, and item hold markers.

`character_body_3d.gd` drives both local human players. The exported `input_prefix` selects `p1_*` or `p2_*` actions, and `use_gamepad_look` selects look input behavior. This single-controller/two-instance pattern is essential to splitscreen compatibility.

### Movement

Implemented movement includes:

- Ground movement and acceleration.
- Sprinting with stamina drain and delayed regeneration.
- Jumping and gravity.
- Limited dash charges with recharge.
- Camera-relative input.
- Mouse or gamepad look.
- Aim-down-sights behavior.
- Knee-height step-up through shape casts.
- Knockback, stagger, slow, movement lock, and temporary immunity state.
- Online ownership gating and puppet visual updates.

The controller also compensates for the selectable maps' 2x root scale so online human collision/render size remains correct.

### Camera and aiming

- Each human player owns an aim pivot and spring-arm camera.
- Local fullscreen uses the player's camera directly.
- Local splitscreen copies player camera transforms into two SubViewports.
- Online players see their locally owned camera; remote players render as puppets.
- Spectating supports follow and free-fly modes after elimination.
- Online aim yaw and pitch are synchronized.

### Health and elimination

There is no numeric health pool.

- A valid bullet hit eliminates immediately unless Second Wind prevents that elimination.
- Melee normally applies disarm/control effects and only eliminates when configured.
- `is_eliminated` is the primary alive/dead state.
- Death drops held equipment/items, transitions the player into spectating, and waits for the next round reset.
- Online elimination and Second Wind consumption are resolved by the host.

### Shield semantics

`extra_melee_shield` is a one-use disarm shield, not health and not bullet armor. It protects a gun holder from one qualifying melee/disarm interaction. Bullets are intended to ignore this shield and remain lethal.

### Inventory

Human inventory consists of:

- One weapon slot: either gun or melee.
- Two item slots.
- An equipped item-slot index.

Interaction behavior includes tap-to-pick-up/swap, hold-to-voluntarily-drop, and item-slot cycling. Pickup objects decide whether they can be acquired and return `true`/`false`; the player does not duplicate each pickup's eligibility rules.

### Animation

- The cat gameplay model provides the skeleton/base animation player.
- `Dance.glb` is loaded as a runtime animation library source containing 11 actions.
- Actions are copied into named runtime animations by numeric source-list indices.
- Locomotion, pistol locomotion, jump, roll, death, and victory dance are represented.
- One-shot animations are duplicated/adjusted so their loop modes differ from locomotion.

This works but depends on stable import ordering. Re-exporting the animation source with a different action order can silently map names to the wrong clips.

### Status effects and powerup state

The human controller owns timers/state for:

- Slow.
- Knockback/stagger and temporary immunity.
- Speed Surge.
- Silent Steps.
- Vampire Touch stamina refund.
- Second Wind.
- Magnet Hands.
- Extra dash.
- Melee/disarm shield.

## Bot system

Bots use `DummyModel.tscn` and `dummy.gd`; they do not share a controller base class with humans.

Implemented bot behavior includes:

- Four difficulty profiles.
- NavigationAgent-driven objective selection.
- Gun, melee, item, and powerup seeking.
- Target selection, retreat behavior, line-of-sight checks, and gunner positioning.
- Sprint/stamina, dash, step-up, knockback, stagger, shields, Second Wind, and other status effects.
- Gun firing, melee pickup/swing/throw, item pickup/use, and powerup collection.
- Online host-only AI and physics.
- Runtime synchronizer data so clients render bots as puppets.

Bot actor IDs begin at 10000. Peer 1 remains their owner, while the actor ID is used for scoring and action attribution.

Known limitations:

- Human and bot movement/status constants are duplicated and already differ in places.
- Bot line of sight checks world geometry on collision mask 1 but not the player layer, so another player may not occlude a shot.
- Bot navigation quality depends on map navmesh validity; current selectable scene files need navigation revalidation.
- Bots do not perform the human victory dance.
- The bot character model is far over the documented asset budget.

## Gun system

`gun.tscn` is a rigid-body pickup with a water-gun visual, collision, pickup range, muzzle marker, reload timer, pickup label, and locator/holder presentation.

Local behavior:

- Registers with nearby players/bots through its pickup area.
- Reparents to the holder's hand.
- Prevents firing during reload/cooldown.
- Spawns a projectile from the muzzle along the actor's aim direction.
- Drops on voluntary action, disarm, or death.
- Returns to the round's assigned spawn during resets.

Online behavior:

- Pickup and fire requests go to the host.
- The host binds requests to the actual RPC sender and actor ownership.
- Validation includes round epoch/state, actor alive state, pickup distance, reload state, and aim constraints.
- Bullet origin comes from the host-side muzzle.
- Spawn, reload completion, drop, and forced disarm are broadcast.
- Hit/elimination resolution is host-authoritative.

## Bullet system

`bullet.tscn` is an emissive rigid-body projectile.

- Tracks shooter/actor attribution and online round epoch.
- Applies host-authoritative elimination online.
- Emits hit-confirmation events for attacker-only hit markers.
- Respects team/friendly-fire rules in local play.
- Is cleared during round resets to prevent stale projectiles affecting the next epoch.

## Melee system

`melee_weapon.tscn` is a generic runtime-skinned rigid body. `MeleeWeaponRegistry` builds five `WeaponData` definitions:

- Sword.
- Baseball bat.
- Stick.
- Crowbar.
- Frying pan.

Each spawn rolls weapon type and effect. Effects include control/displacement behavior such as knockback, stagger, and slow. Weapon data contains base timing, stamina cost, pose offsets, and model path; the generic scene owns the shared mode-aware hit capsule.

The melee lifecycle includes:

- Pickup and swap rules.
- Held pose and hand parenting.
- Windup, active, and recovery phases.
- Stamina cost and optional weapon breaking.
- Throwing and landing.
- Gun-holder disarm and reacquisition lock.
- Optional lethal melee rules.
- Drop/despawn/reset behavior.

Online melee uses `RoundManager` as a stable RPC endpoint because melee nodes move between the map and actor hands. Every authored placement receives a stable candidate ID. The host assigns and broadcasts each identity and validates pickup/action/epoch/ownership before resolving hits and effects.

Melee tiers and the unused `upgrade_tier()` hook are retired. Extra tier keys in stale dictionary payloads are ignored because melee identity reads only type and effect.

## Item system

Seven item types are registered:

| Type | Category | Behavior |
|---|---|---|
| Bubble gum | Hazard | Contact-deployed lingering slow trap |
| Grenade | Hazard | Timed fuse and one-shot radial knockback flash |
| Bear trap | Hazard | Deployed snare/trap |
| Spring pad | Hazard | Deployed launch pad |
| Smoke bomb | Consumable | Temporary smoke cloud |
| Decoy | Consumable | Static cat decoy body |
| Boomerang | Consumable | Returning thrown item with its own script |

`item.gd` is the generic pickup/hold/drop/throw/deploy implementation for six of the seven items; boomerang extends behavior through `boomerang.gd`.

Local items are spawned at `item_spawn_point` markers by `RoundManager`, filtered through `GameConfig`. Players hold two at a time. Bots have a simpler one-item behavior path.

Online items use stable IDs through `RoundManager`. The host assigns item types to every authored marker, validates pickup/swap/drop/throw, resolves fuse/contact deployments and gameplay effects, and broadcasts final deployed positions. Clients may simulate visual flight, but the host owns the outcome.

Known online limitation: existing review notes say melee/item pickup validation lacks the same explicit server proximity check used by the gun. This should be confirmed before adversarial networking is considered.

## Powerup system

`powerup.tscn` is one generic bobbing/rotating colored pickup. Its type is fixed while visible and rerolled after collection/respawn. Older documentation describing live cycling is stale; `cycle_*` fields remain only for scene compatibility.

Seven types exist:

| Type | Effect |
|---|---|
| Extra Dash | Temporary additional dash charge |
| Extra Melee Shield | One protected gun-holder melee/disarm interaction |
| Speed Surge | Temporary movement speed multiplier |
| Silent Steps | Temporary footstep suppression |
| Vampire Touch | Melee hits refund stamina |
| Second Wind | Prevents one otherwise valid elimination |
| Magnet Hands | Pulls nearby loose pickups toward the player |

Local collection applies directly to the actor. Online collection, respawn type, shield/Second Wind consumption, and Magnet Hands movement are host-resolved.

Current verification risk: Magnet Hands failed the existing full online smoke check consistently on Western V2 and intermittently on Forest.

## Round, set, and match system

`round_manager.gd` owns both local and online match orchestration.

Local responsibilities include:

- Discovering active player instances.
- Spawning configured bots.
- Spawning marker-driven items/powerups.
- Assigning spawn transforms and resetting the gun/melee/items.
- Countdown, live, and ended state transitions.
- Alive-player/team checks and draw handling.
- Round wins, set wins, match completion, and statistics.
- Winner presentation and victory dance.
- HUD state and GameEvents subscriptions.

Online responsibilities include all of the above plus:

- Stripping baked local players, HUD, and splitscreen nodes.
- Creating the network actor container and spawner.
- Spawning humans and host-owned bots.
- Readiness handshake coordination.
- Round epochs and stale-action rejection.
- Actor state snapshots and authoritative scoring.
- Stable melee/item/powerup/deployed-object registries.
- Most authoritative RPC endpoints.
- Coordinated lobby return and disconnect removal.

The local state machine is effectively `countdown -> live -> ended`; online broadcasts equivalent state and epoch data to every peer.

## Scoring and events

Tracked values include:

- Round wins.
- Match/set points.
- Kills.
- Deaths.
- Disarms.
- Pickups.
- Melee hits.

`GameEvents` exposes seven cross-system signals:

- `player_eliminated`.
- `player_disarmed`.
- `gun_picked_up`.
- `gun_dropped`.
- `hud_notification`.
- `melee_hit_landed`.
- `hit_confirmed`.

Gameplay emitters do not need direct HUD references; match/HUD/feed systems subscribe separately.

## Spectator system

After elimination, a player transitions to `spectator_controller.gd`:

- Follow-camera mode can cycle living eligible targets.
- Free-fly mode keeps eliminated players engaged.
- Online activates the spectator camera directly because the local splitscreen manager is not present.
- The actor's normal camera is reclaimed on next-round respawn.

The eligible-target rules should be playtested when only bots remain; earlier online implementation work deliberately treats bots differently in some spectator paths.

## Splitscreen system

`splitscreen_manager.gd` maintains two SubViewports and copies each human camera transform into the corresponding viewport camera. When splitscreen is disabled, P2 is hidden and P1 stretches full-width. Both players still come from the same actor scene/controller contract.

## Audio system

`AudioManager` provides:

- Menu music.
- Forest-specific level music and ambience.
- Gun shot.
- Melee swing and per-weapon impact sounds.
- Footsteps.
- UI hover and click.
- A small reusable SFX player pool.

Missing or commented categories include pickup, drop, disarm, round start/end, death, and generic game music. Audio is routed through the Master bus with manual volume application rather than dedicated Music/SFX/UI buses.

## Pause and exit behavior

Local ESC pause uses `PauseManager` and pauses the SceneTree. Online ESC opens a local-only overlay and does not pause network processing.

- Host: can return all peers to lobby or send everyone to the main menu.
- Client: does not receive Return to Lobby and can leave only its own session for the main menu.
- Host loss sends clients through the server-disconnected flow.

## Multiplayer system

### Transport and discovery

- Godot ENet over UDP 24545 for gameplay.
- Named-lobby discovery over UDP 24546.
- Tailscale CLI peer list supplies candidate tailnet addresses.
- Host advertises a chosen lobby name.
- Direct `100.x.x.x` entry remains a fallback.
- Join timeout is 12 seconds and stale peers are closed before host/join.

This is private-tailnet discovery, not public matchmaking. Duplicate lobby names, Tailscale CLI availability, and host firewall state remain external concerns.

### Session and loading

`NetworkManager` owns:

- Host/join/disconnect state.
- Peer roster and display names.
- Lobby identity.
- Host config/map snapshots.
- Monotonically increasing match ID.
- Coordinated scene change.
- Per-peer scene-ready tracking.
- Late-join refusal while a match is active.
- Coordinated lobby/main-menu returns.

The all-peer readiness handshake replaced an earlier fixed load delay and explains faster, more deterministic map entry.

### Authority model

- Human movement: owning peer.
- Remote human presentation: synchronized puppet.
- Bot AI/movement: host only.
- Gun pickup/fire/reload/bullets: host-resolved.
- Melee actions/hits/effects: host-resolved.
- Item pickup/deploy/effects: host-resolved.
- Powerup collection/consumption: host-resolved.
- Round, alive state, score, reset, and match end: host-resolved.

### Known limitations

- No online teams or friendly fire configuration.
- No host migration.
- No reconnect/resume.
- No general in-progress late join.
- No client movement prediction reconciliation or remote interpolation layer.
- No shot prediction for high latency.
- Owner-authoritative movement is not hardened against cheating.
- Some death-drop positions can differ slightly between peers; gun drops do not receive the same eventual resync behavior as melee.
- No public lobby/rendezvous service.
- Loopback smoke coverage does not replace real Tailscale testing.

## System-preservation checklist

Future work should keep these contracts unless a separate redesign is approved:

- Match settings flow through `GameConfig`.
- Cross-system match events flow through `GameEvents`.
- Human input actions use the player prefix convention.
- Pickups self-register through overlap and return pickup success.
- Current map markers and melee placements remain authored content.
- Online actor identity stays separate from controlling peer identity.
- Host remains authority for gameplay outcomes.
- Online-only behavior remains gated so local play is not changed accidentally.
