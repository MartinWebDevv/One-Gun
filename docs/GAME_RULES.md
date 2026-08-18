# One Gun — Game Rules

> Source of truth: this document describes mechanics as implemented in the codebase as of 2026-08-14. Numbers are pulled directly from the gameplay, configuration, registry, round, weapon, item, and bot scripts. Where a value is configurable per match, the default is listed.

## 1. Overview

One Gun is an arena shooter for up to 10 competitors (humans + bots), playable solo, in local 2-player splitscreen, or online with one human per connected computer. The default One Gun mode has exactly one shared gun; All Gun and One of Us intentionally replace that scarcity rule. One Gun and All Gun remain structured as rounds -> sets -> match, while One of Us is a single winner-takes-all round.

### Game modes

- **One Gun**: the default scarcity mode. One shared gun is contested while ground melee, items, and powerups follow the configured spawn pools. Normal first-round map intro and standard/Chaos overtime rules apply.
- **All Gun**: every player starts every round with a personal gun and three heart pips. The three filled/empty hearts are also rendered depth-tested above every living actor for all players and spectators. Only gunshots remove hearts, one at a time, with 0.75s post-hit protection. Melee weapons never spawn; items and collectible powerups remain, except Extra Life. A disarm effect forces the target gun through a full reload instead of dropping it, while Sticky Hands consumes itself to block that forced reload. The mode supports teams and remains last-player/last-team-standing. When the normal timer reaches overtime, the advancing fire removes all remaining hearts immediately for sudden death.
- **One of Us**: each human may privately choose RESIST or LET IT IN before launch. The host randomly chooses the first infected from the volunteer pool; if nobody volunteers, every match participant is eligible. Preferences never enter the shared roster. Them receive +15% movement speed, four base dashes, and a personal Frying Pan using the universal 5.2m melee length. Us receive three base dashes and personal One Gun guns. Them respawn after 2.0s when shot. A Them melee hit converts an Us player after a 1.5s spectator window, and both temporary waits use role-filtered spectating. The last Us receives one additional single-use dash. Them win by converting every Us before 3:00; Us win if at least one survivor remains when the fixed timer expires. That winner takes the whole match immediately: One of Us has exactly one three-minute round, no sets, and no overtime. Ground melee never spawns, Sticky Hands and Extra Life are excluded from collectible powerups, and a runtime-only darker, desaturated, cool-fog environment grade gives every map a dingy survival treatment without modifying its authored environment or affecting other modes.
- In One of Us, the normal map-orbit intro is replaced by a synchronized 7.35s hunt cinematic. Input is locked while a temporary camera dives from above the arena, scans deterministic player targets, reveals and orbits the server-selected first infected during their transformation, then takes a role-specific route back to each local gameplay camera. The first infected sees `YOU ARE THE FIRST.` then `MAKE THEM ONE OF US.`; every Us player sees `ONE OF THEM HAS TURNED.` then `RUN.`. All clients regain control on the shared cinematic deadline. Other game modes keep their existing first-round intro.

### The Playpen

The Playpen is an online-only, retro-space practice room reached from the lobby. Every player enters and leaves independently, entry never asks about or changes lobby Ready state, and a guest may open the room before the host enters. In that guest-first case the listen host silently loads and continues authoritatively serving the practice scene while remaining on its lobby overlay. If the host leaves later, the authoritative practice scene likewise keeps running for its remaining members and the host may re-enter without reloading the room. Practice has no scores, round timer, or bots, and eliminated players respawn after 2.0s. Its pause menu exposes `LEAVE PLAYPEN` to everyone and gives the host a separate `START MATCH`/`FORCE START MATCH` action; ordinary match pause menus are unchanged.

Three fixed armory bays remove random scavenging from practice. Every bay contains exactly two gun spawns, one of each of the five melee types, all nine item types, and all seven collectible powerups. Each dedicated pickup refills after 2.0s. Loose guns, melee weapons, and items dropped from a player's inventory retire after 2.0s so the dedicated supplies stay available without floor clutter. Only peers currently inside The Playpen see and fight one another.

## 2. Match Structure

- A **round** ends when ≤1 player (or ≤1 team, in team mode) remains alive, or in a simultaneous-elimination draw.
- Winning a round adds 1 to that player's `round_wins`. Reaching `rounds_per_set` (default **3**) wins the **set** and adds 1 `match_points`.
- Reaching `sets_per_match` (default **3**) wins the **match**, returning everyone to the lobby.
- Display timings: countdown before round start **3s**, round-end banner **3s**, set-end banner **4s**, match-end banner **6s** (all configurable on `RoundManager`).
- Before the countdown of the **first round only**, each player gets a frozen 3s camera introduction: a map-authored `round_intro_camera_point` begins above the arena, orbits 180° toward that player's spawn, then fades into their gameplay camera. Reduced Motion replaces the orbit with a simple fade.
- Actor cap: **10 active humans and bots**. Solo mode allows up to 9 bots; local splitscreen allows up to 8 bots. An online host chooses a 2–10 human lobby limit and may fill unused match slots with bots; incoming humans trim excess bots before launch. Online splitscreen is never supported. A person who joins during a live match stays outside its active roster and may either wait in the lobby or enter pure spectator mode for every remaining round, with scoreboard access, until the match returns to the lobby.
- Each map declares its supported player capacity and must author at least that many `spawn_point` markers. A roster larger than the selected map is blocked in the lobby with a clear message; Random Rotation selects only compatible maps. `RoundManager` performs the same actual-marker check after loading and never reuses a marker for overlapping actors.
- Team mode supports **2–4 teams**, uneven teams, and no per-team cap beyond the ten-actor global limit. The lobby shows an uneven-team warning instead of blocking launch. Friendly fire is off by default but host-configurable; self-inflicted effects still apply. Team scoreboards group each team's players and their individual stats under a team heading.
- Online players choose Ready individually. Once everyone is ready the host may start, or the host may use Force Start to override unreadied players. Either path places a synchronized **3, 2, 1** countdown inside every player's Ready button (and the host's Start button) before loading the match.
- A round defaults to a host-adjustable **5:00** limit (`round_time_limit`). It can be adjusted in one-second increments down to **1s**; **0** disables the timer. When it expires with multiple survivors, the round enters unlimited-count-up **Overtime** instead of ending.
- OT fire begins just outside that map's authored combat footprint, starts advancing immediately, and reaches the playable edge after **5s**. It never pauses after that and fully engulfs the arena at approximately **2:00** of OT. The unsafe region is rendered continuously across the map's baked playable navigation surface, with dense, fast-rising flame particles emitted only from unsafe polygons. This keeps the effect grounded across imported meshes, CSG, Terrain3D and elevated routes. It affects players at any height above unsafe ground. The visible fire leads the lethal boundary by 0.35 units. Every shipped map must retain a non-empty navigation bake; an emergency projected-floor fallback keeps this critical warning visible if a bake is ever missing.
- Fire exposure eliminates after **5s** in zone 1, **4s** in zone 2, and **3s** from zone 3 onward. A player must stay safe for **1s** to reset accumulated exposure. Each new zone pulses all survivors through walls for **1s**.
- Standard OT preserves the one-gun contest. Enabling `chaos_overtime_enabled` arms every survivor and retires the original shared gun. Both modes preserve melee weapons already held at the transition; Chaos clears carried items/powerups but not held melee. All regular pickup placements close, then exactly one randomized melee marker remains active on its independent 5s refill cycle. OT time shown in the HUD uses minutes/seconds; milliseconds remain internal for simultaneous-elimination tiebreaks.

## 3. Movement

| Stat | Value |
|---|---|
| Walk speed | 10.0 m/s |
| Sprint speed | 18.0 m/s |
| Jump velocity | 7.0 m/s (exported `jump_velocity`) |
| Post-landing jump cooldown | None; a grounded player may jump immediately |
| Max stamina | 100 |
| Stamina drain (sprinting) | 25/sec |
| Stamina regen (at rest) | 20/sec, after a 1.0s delay following sprint |

Sprinting is a match-wide setting (`GameConfig.sprinting_enabled`) that applies to humans and bots and defaults to **false**. Dashing remains the default burst-movement mechanic.

**Dash**: 30 m/s burst for 0.2s. Default **3 charges**, each recharging in 3.0s independently. Max charges configurable 0–6 (`max_dash_charges`, hard ceiling enforced in code).

**Step-up**: players and bots automatically walk over ledges up to **0.55 m** (knee height) — stair steps, boardwalks, small rocks — with no jump needed. Taller obstacles still require a jump or block movement. (`STEP_HEIGHT` in `character_body_3d.gd` and, duplicated by convention, `dummy.gd`.)

**Traffic hazard (Maple & 3rd only)**: cars drive the block on loops; getting clipped applies a melee-style knockback shove (never lethal, ~1.5s per-player cooldown) via the same `apply_knockback()` path melee uses. Cars stop for the red light at the intersection.

**Manhole steam boost (Maple & 3rd only)**: jumping while inside the visible steam column launches the player upward at 14.0 m/s. Walking through the steam does nothing. Normal gravity applies on ascent. Once a steam-launched player has cleared the 2.0m height gate and begins descending, gravity increases to 3× until landing so the boosted arc does not linger. Tune `lift_strength`, `descent_height_gate`, and `descent_gravity_multiplier` on `ManholeSteamBoost`; ordinary jumps and spring pads are unaffected.

**Fire-hydrant water jet (Maple & 3rd only)**: a player or bot can stand immediately in front of the bursting hydrant and press Jump—with no directional input—to receive a 15.0 m/s impulse straight away from the nozzle along the authored `LaunchDirection`. The water adds its horizontal force instead of replacing existing movement: cross-stream momentum is fully preserved, movement already traveling with the water is preserved, and movement opposing the stream is reduced to 25% before the water force is added. While that water launch remains airborne, opposing steering cannot reduce with-stream speed below 40% of the original horizontal water impulse; this makes the hydrant visibly win a head-on contest without removing lateral control. The water establishes at least its authored upward velocity rather than stacking vertically with the ordinary jump. Walking through the activation zone does nothing. The separately authored collision box controls where the water catches a player and is never rebuilt at runtime. The launch otherwise retains 60% air steering, and an airborne dash replaces the remaining water momentum. Online launches are host-resolved.

**Spring pads** launch at 13.0 m/s vertically. The first directional input made within 1.0s commits a 4.0 m/s horizontal boost in that direction; players retain 60% normal air-strafe control until landing. With no input the launch remains vertical. Dashing while still in a pad launch cancels all remaining pad momentum, including vertical velocity, so only the horizontal dash force is active during the dash. Bots and online actors follow the same movement rule; decoys use the pad launch and steering contract but cannot dash.

**Knockback / stagger** (inflicted by melee hits — see §5): freezes horizontal velocity (knockback, 0.2s) or all movement (stagger, 1.0s) and grants temporary bullet immunity afterward so a disarmed/staggered player isn't instantly finished off.

**Aiming**: ADS (aim-down-sights) transitions over 0.2s, tightens FOV by 0.9×, and pulls the camera boom in to 0.3 (from the default 4.0). ADS halves look sensitivity by default (configurable, `ads_sensitivity_multiplier`).

**Camera collision**: the normal third-person camera boom retracts when layer-1 map geometry blocks it, preventing walls and floors from passing between the player and camera. It ignores players and pickups. Spectator follow cameras inherit the same behavior, while free spectator movement uses a small collision sphere against the same map-geometry layer. Opening the pause menu freezes both player-look and spectator-camera input, including online menus where the scene itself keeps running.

## 4. The Gun

- **One gun spawns per match** — no ammo pickups, no second gun.
- Semi-automatic: one shot per trigger pull, then a reload.
- Reload time: 2.0s.
- Bullet speed: 200 m/s, still a physically simulated projectile with a 10s emergency lifetime.
- A bullet hit is an **instant elimination** — there is no health pool or damage falloff.
- Getting disarmed (see below) locks the ex-holder out of re-picking up the gun for **`disarm_lock_time`** seconds (default 3.0), giving the disarmer a window to grab it.
- A visible gun holder receives a pulsing red/orange rim and an obvious `GUN HOLDER` marker. The marker is line-of-sight gated and shown only to other players, never to the holder.
- Gun spawn location each round: `gun_spawn_mode` = `"center"` (fixed point) or `"random"` (from `gun_spawn_point` group markers).

## 5. Melee Weapons

Each round starts with **one randomized melee weapon at every authored `melee_spawn_point`**. Picking one up starts that marker's independent **5.0s refill**; the refill rolls a fresh weapon type and effect while the picked-up weapon remains with its player. Repeated pickups can therefore put multiple melee weapons into play. Pending regular refills are cancelled by round reset or overtime; OT activates one selected melee marker with the same independent refill behavior.

The Spawns settings expose a collapsible **Melee Weapons** pool. Sword, Baseball Bat, Stick, Crowbar, and Frying Pan can each be enabled or disabled for local and online spawn rolls. The UI and `GameConfig` both enforce a minimum of one enabled melee weapon.

### Weapon types (`melee_weapon_registry.gd`)

| Weapon | Universal reach | Windup | Active | Recovery | Stamina | Character |
|---|---|---|---|---|---|---|
| Sword | 5.2m | 0.08s | 0.18s | 0.25s | 15 | fast, responsive handling |
| Baseball Bat | 5.2m | 0.12s | 0.22s | 0.35s | 15 | deliberate handling |
| Stick | 5.2m | 0.04s | 0.12s | 0.14s | 8 | shortest windup, cheapest |
| Crowbar | 5.2m | 0.08s | 0.18s | 0.26s | 14 | balanced all-rounder |
| Frying Pan | 5.2m | 0.32s | 0.28s | 0.55s | 22 | heavy, committed handling |

Weapon tiers have been removed. Weapon type and effect are the complete randomized identity; there are no T1/T2/T3 timing, stamina, effect, display, bot-priority, or networking modifiers.

### Effects (randomly rolled per weapon instance, one of four, equal odds)

- **Normal**: no status effect; a hit on the gun holder disarms them (see below).
- **Knockback**: shoves the target 2.0 units and grants 1.5s post-hit bullet immunity.
- **Stagger**: freezes the target for 1.0s and grants a matching 1.0s bullet-immunity window.
- **Slow**: slows the target to 85% speed for 3.0s and grants no bullet immunity afterward.

**Who effects hit**: by default (`melee_effects_hit_anyone = true`), Knockback/Stagger/Slow apply to *any* player struck, not just the gun holder — this is a lobby-configurable match setting (see §11). The gun-holder-only *disarm* behavior below is separate and always applies regardless of this setting.

### Swing lifecycle

All five melee models are normalized to a 1m longest held dimension, so their visual size is consistent even though their imported source files use very different units. Legacy model-local hit-shape helpers are ignored: every weapon uses the same forward-facing runtime capsule, with a 0.45m radius, anchored at the paw. Its length is **5.2m in every game mode**. The Reach powerup temporarily stretches the capsule to **7.0m**.

Windup (wind-up pose, no hit) → Active (hitbox live) → Recovery (character returns to locomotion). The authored character melee animation owns the visible attack; held weapon objects remain fixed to their paw socket instead of adding a second, smaller rotation tween. Runtime swing phases use 85% of the data-authored duration (15% faster). Stamina cost is paid **upfront** at swing start. Swinging while in stamina deficit twice in a row **breaks the weapon** for 5.0s (it respawns at its spawn point) — this can be disabled via `melee_weapon_breaking`.

### Elimination rules (match settings)

- By default, melee **cannot** eliminate — it only disarms the gun holder or bumps/knocks back others.
- `melee_eliminates_gunholder`: a melee hit on the current gun holder eliminates them outright instead of disarming.
- `melee_eliminates_anyone`: melee eliminates any target it connects with, gun holder or not (overrides the gunholder-only rule).

### Throwing

Holding the throw input on a melee weapon previews a short dotted, collision-aware arc; releasing commits the throw. Melee weapons and throwable items share the same launch: 15.0 m/s forward plus 5.0 m/s upward, from 0.6m ahead and 1.0m above the character. The preview deliberately shows only the arc, with no landing marker. A melee weapon resets its rigid-body root scale after leaving the animated paw, uses the same compact 0.3×0.1×0.16m flight collider as an item, receives the launch as deterministic velocity, and keeps a 0.40s collision-exception grace so it clears and cannot affect its thrower. A thrown weapon that lands still applies its effect at 50% magnitude (and, for Stagger specifically, 50% of its bullet-immunity window too). After landing, it has a 1.0s cooldown before it can be picked back up.

### Death drops & respawn

A weapon dropped by an eliminated holder despawns and returns to its spawn point after `dropped_melee_despawn_time` (default 3.0s; ≤0 disables despawn, meaning it stays on the ground indefinitely). This is independent of the 5.0s marker refill already started by its pickup. `melee_spawn_delay` (default 0) can delay pickup availability at round start.

## 6. Disarming

A melee hit against the **gun holder** (when neither elimination rule above is active) disarms them: the gun is knocked loose, drops to the ground, and the disarmer gets credit (`player_disarmed` event, scoreboard "Disarms" stat). The disarmed player cannot re-pick the gun for `disarm_lock_time` seconds.

Online matches use the same melee rules. The host validates pickup distance, holder ownership, alive/round state, swings, throws, hit targets, disarms, effects, breaking and despawn/reset outcomes. The host assigns every refill a fresh network candidate ID, rolls its weapon type/effect once, and sends that identity to every peer so all machines show and simulate the same supply.

## 7. Items & Hazards

Held across two item slots (slots 2 and 3 - see section 9), separate from the weapon slot, so a player can carry a weapon and up to two items. For throwable items, holding Fire previews the same short dotted, collision-aware arc and releasing throws using the shared 15.0 m/s forward plus 5.0 m/s upward launch. Flash Camera and Double Jump Shoes are use-in-place exceptions and do not show a throw arc.

- **Bubble Gum Trap**: thrown, deploys on first contact as an irregular chewed-gum splat roughly 4.5m by 4.5m, slows anyone who walks into its area to 0.5x speed for 2.0s, and removes itself from play after 5.0s. Its pickup marker independently refills 8.0s after collection.
- **Grenade**: pressing Fire irrevocably starts a **3.0s fuse** and the circular crosshair progress ring; holding cooks it and releasing throws it. If the fuse expires in hand it detonates at the holder. The blast affects everyone allowed by the match rules, including its owner, within **7.5m** and retains the normal gun-holder disarm behavior. Knockback falls linearly from 4.0 at the center to 2.0 at the edge and grants no bullet-immunity window. Its pickup marker independently refills 8.0s after collection.
- The Spawns tab's collapsible **Items** group contains every throwable/usable item: Bubble Gum, Grenade, Bear Trap, Spring Pad, Smoke Bomb, Decoy, Boomerang, Flash Camera, and Double Jump Shoes. Its master switch gates the full item pool while `item_registry` preserves every individual selection underneath.
- The collapsible **Power Ups** group contains only collectible powerups. Its master switch maps exclusively to `powerups_enabled`, while `powerup_registry` preserves every individual selection underneath.
- Bots can collect and use enabled items through a simplified one-item inventory. Their throw decisions run on difficulty-tuned real-time intervals rather than per-frame random checks.

### New items (2026-07-11)

| Item | Type | Behavior |
|---|---|---|
| Smoke Bomb | consumable | 1.2s post-throw fuse; expands for 1.5s into an irregular 5m-radius smoke field with a 4.2m concealment half-height, stays full for 6s, then collapses for 1.5s. Its overlapping inner wisps are opaque while animated outer wisps soften the silhouette; it is not a solid dome and scenery cannot be seen through its center. Bullets pass through. Bots remember a recently seen target and may risk a shot through smoke, but otherwise wait for a clearer opportunity. |
| Bear Trap | hazard | Deploys where it lands, sits open up to 20s; first player in gets rooted 1.5s (stagger), trap snaps shut. One use. Owner-safe per `can_affect`. |
| Decoy | consumable | Deploys one fake player for up to 10s. It runs straight forward by default; the owner can press **C** to toggle mirrored movement control (gamepad is unbound by default). Bots target it like a real player, while attacks and hostile traps affect or pop it. The owner and protected teammates cannot destroy it. An enemy gunshot pop briefly outlines the shooter for 0.5s; trap-triggered pops do not. It awards no kill credit. |
| Boomerang | consumable | Flies ~10m out and returns over ~1.7s; disarms a gun holder on hit (respects melee shields, grants the victim 1s immunity), knocks back anyone else. Auto-caught on return if a slot is free. |
| Spring Pad | hazard | Deploys where it lands, lives 30s; launches players, bots, and decoys using the committed-boost rule in §3, with a 0.5s per-body cooldown. |
| Flash Camera | consumable | First Fire raises a 60° camera frame; Fire again takes the photo. ADS or switching slots cancels. Lateral movement is 30% slower while framed. A target within 30m must be in-frame, visible, and looking toward the camera. The effect lasts 6s at point-blank down to 3s at 30m: the first 2s are fully opaque white, then the screen fades linearly back to gameplay over the remaining time. Teammates are protected unless friendly fire is enabled. |
| Double Jump Shoes | consumable | Activates in place, immediately frees its inventory slot, and shows one spring shoe on each foot to every player. It grants one mid-air jump at 100% of the normal jump velocity, then removes the shoes and plays the boing sound. Only one charge can be active, but another pair may be carried in inventory for later. Death/round reset clears an unused active charge. |

**Sounds** (2026-07-11): gunshot on fire; Swing_Sound on every melee swing; per-weapon hit sounds (Sword_Clash / Stick_Hitting / Crow_Bar_Hit / BaseballBat_hit / Frying_Pan); footsteps per stride (0.38s walk / 0.26s sprint cadence, grounded only, muted by Silent Steps).

Online matches use the same marker placements, item pools, two-slot inventory rules, fuses and respawn/reroll timings. The host validates pickup range/ownership and line of sight, grenade priming, drops, throw direction, deployment, Flash Camera targets, collisions and gameplay effects, then broadcasts the result to every peer. Visual thrown-object physics may differ slightly in flight under latency, but the host's final deployment position is authoritative.

## 8. Powerups

Powerups spawn at map markers as bobbing/rotating pickups. Each orb has a camera-facing world label above it showing its current name, colored to match the orb. Its type is **fixed at spawn** and changes only when that powerup respawns after collection.

| Powerup | Effect |
|---|---|
| Extra Dash | +1 dash charge for 5.0s |
| Sticky Hands | Blocks the next gun disarm attempt (single use, no timer) |

Respawns **8.0s** after being collected.

### New powerups (2026-07-11)

| Powerup | Effect | Bots? |
|---|---|---|
| Speed Surge (green) | ×1.4 move speed for the duration | yes |
| Silent Steps (slate) | footsteps muted for the duration | n/a (bots have no footsteps) |
| Vampire Touch (red) | landed melee hits refund 30 stamina | yes |
| Extra Life (orange) | survive one lethal blow with 1s general damage immunity (one charge, shows as ∞ until used) | yes |
| Reach (green) | for 5s, increases visible pickup range to 7m, auto-collects powerups, and stretches every 5.2m melee active hitbox to a 7m maximum; the owner alone sees a 7m green range ring | yes |

Powerup type is **fixed at spawn** and re-rolls only when the orb respawns after being collected. Items and powerups spawn at map-placed `item_spawn_point` / `powerup_spawn_point` markers each round. Every item marker rolls a random enabled type (pool = `GameConfig.ITEM_SCENES` filtered by `is_item_enabled`) and starts an independent **8.0s refill when that item is picked up**; the carried object remains usable, then retires after use instead of creating a second refill. Powerups likewise re-roll after their 8.0s post-collection delay. Marker-spawned nodes are tracked via the `marker_spawned` group and freed/re-spawned each round reset.

`powerups_enabled` is the collectible-powerup master gate, and `powerup_registry` controls Extra Dash, Sticky Hands, Speed Surge, Silent Steps, Vampire Touch, Extra Life, and Reach individually. An empty enabled powerup pool creates no powerup placements; this is allowed, unlike the melee pool. Mode rules filter the enabled registry at spawn time: All Gun excludes Extra Life, while One of Us excludes both Extra Life and Sticky Hands.

Online powerup collection is host-validated and applied on every peer. Persistent defensive state is resolved by the host: Extra Life prevents an authoritative lethal blow before scores/deaths change, and Sticky Hands is consumed by one gun-disarm attempt. The protections can be held together but cannot stack with themselves, and current protection/immunity state is included in late-spectator synchronization. Temporary immunity caused by a knockback/stagger melee effect remains separate and expires authoritatively even when the affected actor belongs to a client. During follow spectating, the complete inventory, stamina, dash, active-effect, reload/cook, and throw-preview HUD is rebound read-only to the followed actor.

## 9. Inventory, Picking Up, and Dropping

Three slots total: **slot 1** is the weapon slot (gun or melee weapon, mutually exclusive), **slots 2 and 3** are item slots.

- **Tap interact**: instantly picks up a nearby object into an empty slot, or **swaps** it for whatever's currently occupying that slot's category — melee-for-melee, item-for-item, or melee-for-gun. The item you swap away is left exactly where the new one was sitting (not dropped at your feet).
- **Hold interact for 0.5s**: drops whatever's in the *currently active* slot. This only kicks in if the initial tap didn't already resolve as a pickup or swap — so standing next to a valid swap target and tapping always swaps; it never accidentally drops first.
- **The gun is the one exception to tap-swapping**: it's never swapped away by a tap. A gun holder must hold interact for the full 0.5s to voluntarily give it up before they can pick up a melee weapon. Picking the gun *up* (from a melee weapon or empty-handed) is always an instant tap, same as everything else.
- **Cycling** (Q/E, or bumpers) moves between *occupied* slots only, skipping empty ones: weapon → item slot 2 → item slot 3 → back to weapon. Fire performs the active slot's primary action (gunshot/melee swing, or item preview/use); the dedicated Throw input previews/releases a melee weapon while the weapon slot is active.
- **Only Interact can pick up**: entering a pickup radius only registers the nearby object and cannot equip or swap it. Human gun/melee/item pickups require the controller's current explicit Interact transaction. Fire never runs the pickup path; if an old/conflicting keybind maps Fire and Interact to the same physical input, the primary attack takes priority and no nearby object is collected.
- When both item slots are full and you interact with a new item on the ground, it swaps into whichever item slot is currently active (not automatically the oldest or newest).
- Dying drops everything you're holding — gun, melee weapon, and both items — at your position.

## 10. Controls

Two independent input sets exist for splitscreen (`p1_*` / `p2_*` action prefixes) plus a shared single-player set. Keyboard/mouse (P1 default) and gamepad (P2 default in splitscreen, either can use gamepad) are both fully supported, including gamepad look with a configurable response curve.

Core actions: move (WASD / stick), look (mouse / right stick), jump (Space / A/Cross), dash (Ctrl), Fire/use (LMB / RT-analog: gun, melee swing, or active item), ADS/cancel camera (RMB / LT-analog), interact/pickup/drop (E or F depending on binding / gamepad face button — tap vs. hold, see §9), melee throw preview/release (G / button), cycle slots (Q/E or bumpers), and decoy-control toggle (C, unbound on gamepad by default). Sprint bindings remain configurable but do nothing while the global sprint gate is disabled.

Spectating uses LMB/RMB (LB/RB) to cycle living players and Space (A/Cross) to switch between follow and free cameras. Free camera uses WASD/right stick and mouse/stick look, Shift/RT to rise, Ctrl/LT to descend, and **F** to move fast.

### Character customization

Human players use the shared V2 rig and may choose any of 13 color textures: Black, Blue, Brown, Cyan, Green, Grey, Orange, Pink, Purple, Red, Salmon, White, or Yellow. The selector is available from both the main menu and lobby, wraps at either end, allows duplicate colors, and includes a slowly rotating 3D preview that can also be dragged with the mouse (P1) or turned with P2's right stick. P1's choice persists in `PlayerPrefs`; local P2's choice is session-only. Online peers synchronize their selected color through the lobby and match spawn data. Bots retain their existing model and appearance. A deployed decoy uses the V2 human model and copies its owner's selected color.

## 11. Match Settings (configurable per-lobby, save/load-able as presets)

All of the following are toggled in the lobby (`game_setup.gd`) and stored on the `GameConfig` autoload; up to 5 full presets ("house rules") can be saved to disk and reloaded:

The lobby exposes one transactional **Settings** cabinet with a vertical Overview / Match Flow / Combat / Spawns / Bots / Presets / Testing rail. Overview is read-only, Bots is part of the same pending transaction, Close discards, and Apply Changes commits the complete snapshot.

The list includes the host-adjustable `round_time_limit` and `chaos_overtime_enabled` rules in addition to the combat, item, bot, and scoring settings below.

`game_mode` (`one_gun`, `all_gun`, or `one_of_us`), `teams_enabled`, `team_count` (2-4), local player/bot team assignments, `friendly_fire_enabled`, `sprinting_enabled`, `melee_eliminates_gunholder`, `melee_eliminates_anyone`, `melee_effects_hit_anyone`, `melee_spawn_delay`, `gun_spawn_mode`, `disarm_lock_time`, `max_dash_charges`, `dropped_melee_despawn_time`, `melee_weapon_breaking`, `rounds_per_set`, `sets_per_match`, `hazards_enabled`, `consumables_enabled`, `powerups_enabled`, `item_registry`, `powerup_registry`, `melee_weapon_registry`, `bot_configs` (per-bot difficulty + team).

The host-only **Testing** tab contains `Visible Hitboxes` (default off): cyan character collision, yellow idle melee hitboxes, and red active melee hitboxes. It synchronizes to online peers for multiplayer testing but is intentionally excluded from saved presets.

## 12. Bots

Bots (`dummy.gd`) fight for the gun, melee, powerups, and items using the same match rules as humans. They keep a simplified one-item pickup model rather than the human two-slot tap/swap/hold system — see [ARCHITECTURE.md](ARCHITECTURE.md). Four difficulty tiers use the same base movement speed and instead change reaction/decision timing, aim cone, fire cadence, target commitment, and tactical options:

| | Easy | Medium | Hard | Expert |
|---|---|---|---|---|
| Reaction time | 0.55–0.85s | 0.35–0.55s | 0.2–0.35s | 0.12–0.25s |
| Gun aim cone | 10.0° | 6.0° | 3.0° | 1.5° |
| Move speed mult | 1.0× | 1.0× | 1.0× | 1.0× |
| Fire cooldown mult | 1.2× | 1.0× | 0.85× | 0.7× |
| Can retreat | No | No | Yes | Yes |
| Can dash | Yes (basic) | Yes (defensive) | Yes (defensive+aggressive) | Yes (defensive+aggressive) |

Bot objectives (`idle`, `get_gun`, `gunner_position`, `get_melee`, `get_item`, `get_powerup`, `chase_holder`, `retreat`) are re-evaluated on difficulty-tuned timers. Bots filter unreachable objectives, respect team/friendly-fire targeting, perceive combat noise, treat decoys as real targets, understand smoke concealment, and treat OT fire as a survival constraint. They may pursue a kill briefly into fire but commit to escape before their remaining exposure margin is exhausted.

## 13. Scoring / Scoreboard (TAB)

Tracked per actor ID for the whole match: kills, deaths, disarms, gun pickups, melee hits landed, plus set/round wins. Sorted by sets won, then rounds won (not kills). Top 3 highlighted gold/silver/bronze; eliminated players greyed out. Duplicate display names receive an ID suffix only where ambiguity exists. Human match IDs are assigned sequentially by lobby join order; a leaver's ID expires and is not reused, while bots start at ID 10000. Network peer ownership remains a separate identity.
