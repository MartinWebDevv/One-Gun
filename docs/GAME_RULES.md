# One Gun — Game Rules

> Source of truth: this document describes mechanics as implemented in the codebase as of 2026-07-13. Numbers are pulled directly from `character_body_3d.gd`, `game_config.gd`, `melee_weapon_registry.gd`, `round_manager.gd`, `gun.gd`, `powerup.gd`, `item.gd`, and `dummy.gd`. Where a value is configurable per-match, the default is listed and the setting name is noted.

## 1. Overview

One Gun is a local (couch) arena shooter for 1–8 competitors (humans + bots), playable single-player or 2-player splitscreen. Exactly **one gun** and **one melee weapon** exist per match — everyone else fights over item pickups, powerups, and whatever they can improvise. Matches are structured as **rounds → sets → match**, elimination-based, last-one-standing per round.

## 2. Match Structure

- A **round** ends when ≤1 player (or ≤1 team, in team mode) remains alive, or in a simultaneous-elimination draw.
- Winning a round adds 1 to that player's `round_wins`. Reaching `rounds_per_set` (default **3**) wins the **set** and adds 1 `match_points`.
- Reaching `sets_per_match` (default **3**) wins the **match**, returning everyone to the lobby.
- Display timings: countdown before round start **3s**, round-end banner **3s**, set-end banner **4s**, match-end banner **6s** (all configurable on `RoundManager`).
- Player/team cap: **8 total**. Solo mode allows up to 7 bots; splitscreen (2 humans) allows up to 6 bots.
- A round defaults to a host-adjustable **5:00** limit (`round_time_limit`). It can be adjusted in one-second increments down to **1s**; **0** disables the timer. When it expires with multiple survivors, the round enters unlimited-count-up **Overtime** instead of ending.
- OT fire begins just outside that map's authored combat footprint, starts advancing immediately, and reaches the playable edge after **5s**. It never pauses after that and fully engulfs the arena at approximately **2:00** of OT. The unsafe region is rendered continuously across the map's baked playable navigation surface, with dense, fast-rising flame particles emitted only from unsafe polygons. This keeps the effect grounded across imported meshes, CSG, Terrain3D and elevated routes. It affects players at any height above unsafe ground. The visible fire leads the lethal boundary by 0.35 units.
- Fire exposure eliminates after **5s** in zone 1, **4s** in zone 2, and **3s** from zone 3 onward. A player must stay safe for **1s** to reset accumulated exposure. Each new zone pulses all survivors through walls for **1s**.
- Standard OT preserves the one-gun contest. Enabling `chaos_overtime_enabled` arms every survivor and retires the original shared gun. OT time shown in the HUD uses minutes/seconds; milliseconds remain internal for simultaneous-elimination tiebreaks.

## 3. Movement

| Stat | Value |
|---|---|
| Walk speed | 10.0 m/s |
| Sprint speed | 18.0 m/s |
| Jump velocity | 7.0 m/s (exported `jump_velocity`) |
| Post-landing jump cooldown | 0.4s (exported `jump_landing_cooldown`, no HUD indicator) |
| Max stamina | 100 |
| Stamina drain (sprinting) | 25/sec |
| Stamina regen (at rest) | 20/sec, after a 1.0s delay following sprint |

**Dash**: 30 m/s burst for 0.2s. Default **2 charges**, each recharging in 3.0s independently. Max charges configurable 0–6 (`max_dash_charges`, hard ceiling enforced in code).

**Step-up**: players and bots automatically walk over ledges up to **0.55 m** (knee height) — stair steps, boardwalks, small rocks — with no jump needed. Taller obstacles still require a jump or block movement. (`STEP_HEIGHT` in `character_body_3d.gd` and, duplicated by convention, `dummy.gd`.)

**Traffic hazard (Maple & 3rd only)**: cars drive the block on loops; getting clipped applies a melee-style knockback shove (never lethal, ~1.5s per-player cooldown) via the same `apply_knockback()` path melee uses. Cars stop for the red light at the intersection.

**Manhole steam boost (Maple & 3rd only)**: jumping while inside the visible steam column launches the player upward at 14.0 m/s. Walking through the steam does nothing. Normal gravity applies on ascent. Once a steam-launched player has cleared the 2.0m height gate and begins descending, gravity increases to 3× until landing so the boosted arc does not linger. Tune `lift_strength`, `descent_height_gate`, and `descent_gravity_multiplier` on `ManholeSteamBoost`; ordinary jumps and spring pads are unaffected.

**Knockback / stagger** (inflicted by melee hits — see §5): freezes horizontal velocity (knockback, 0.2s) or all movement (stagger, duration scales with weapon tier) and grants temporary bullet immunity afterward so a disarmed/staggered player isn't instantly finished off.

**Aiming**: ADS (aim-down-sights) transitions over 0.2s, tightens FOV by 0.9×, and pulls the camera boom in to 0.3 (from the default 4.0). ADS halves look sensitivity by default (configurable, `ads_sensitivity_multiplier`).

**Camera collision**: the normal third-person camera boom retracts when layer-1 map geometry blocks it, preventing walls and floors from passing between the player and camera. It ignores players and pickups. Spectator follow cameras inherit the same behavior, while free spectator movement uses a small collision sphere against the same map-geometry layer. Opening the pause menu freezes both player-look and spectator-camera input, including online menus where the scene itself keeps running.

## 4. The Gun

- **One gun spawns per match** — no ammo pickups, no second gun.
- Semi-automatic: one shot per trigger pull, then a reload.
- Reload time: 2.0s.
- Bullet speed: 200 m/s, still a physically simulated projectile with a 10s emergency lifetime.
- A bullet hit is an **instant elimination** — there is no health pool or damage falloff.
- Getting disarmed (see below) locks the ex-holder out of re-picking up the gun for **`disarm_lock_time`** seconds (default 3.0), giving the disarmer a window to grab it.
- Gun spawn location each round: `gun_spawn_mode` = `"center"` (fixed point) or `"random"` (from `gun_spawn_point` group markers).

## 5. Melee Weapons

Exactly **one melee weapon** is active on the map per match, randomly assigned one of 5 weapon types and one of 3 tiers each time it spawns/respawns.

### Weapon types (`melee_weapon_registry.gd`)

| Weapon | Reach ×base | Windup | Active | Recovery | Stamina | Character |
|---|---|---|---|---|---|---|
| Sword | 1.5 | 0.08s | 0.18s | 0.25s | 15 | long reach, fast, disarm-safe poking |
| Baseball Bat | 1.3 | 0.12s | 0.22s | 0.35s | 15 | wide arc, knockback specialist |
| Stick | 0.75 | 0.04s | 0.12s | 0.14s | 8 | shortest windup, cheapest, aggressive rush |
| Crowbar | 1.1 | 0.08s | 0.18s | 0.26s | 14 | balanced all-rounder |
| Frying Pan | 0.7 | 0.32s | 0.28s | 0.55s | 22 | slow, very wide, devastating in corridors |

### Tiers (roll each spawn: T1 60% / T2 30% / T3 10%)

Tiers only affect **speed and stamina efficiency**, never damage — by design, so a lucky high-tier drop feels snappy rather than "I win" powerful.

| | T1 | T2 | T3 |
|---|---|---|---|
| Windup multiplier | 1.0× | 0.82× | 0.65× |
| Recovery multiplier | 1.0× | 0.80× | 0.60× |
| Stamina cost multiplier | 1.0× | 0.82× (min 0.6×) | 0.65× (min 0.6×) |
| Active (hit-window) time | unchanged at all tiers | | |

### Effects (randomly rolled per weapon instance, one of four, equal odds)

- **Normal**: no status effect; a hit on the gun holder disarms them (see below).
- **Knockback**: shoves the target back; distance and post-hit bullet-immunity scale with tier (2.0 / 3.0 / 4.0 units; 1.5s / 1.0s / 0s immunity).
- **Stagger**: freezes the target; duration and immunity scale with tier (1.0s / 1.5s / 2.0s stagger; matching immunity window). Higher tier = longer escape window for the staggered player.
- **Slow**: slows the target to 85% speed for 3.0s. Flat regardless of tier (tier only affects windup/recovery/stamina, as always) and grants no bullet immunity afterward — it's a minor effect, not disruptive enough to warrant a safety window.

**Who effects hit**: by default (`melee_effects_hit_anyone = true`), Knockback/Stagger/Slow apply to *any* player struck, not just the gun holder — this is a lobby-configurable match setting (see §11). The gun-holder-only *disarm* behavior below is separate and always applies regardless of this setting.

### Swing lifecycle

Windup (wind-up pose, no hit) → Active (hitbox live) → Recovery (weapon resets). Stamina cost is paid **upfront** at swing start. Swinging while in stamina deficit twice in a row **breaks the weapon** for 5.0s (it respawns at its spawn point) — this can be disabled via `melee_weapon_breaking`.

### Elimination rules (match settings)

- By default, melee **cannot** eliminate — it only disarms the gun holder or bumps/knocks back others.
- `melee_eliminates_gunholder`: a melee hit on the current gun holder eliminates them outright instead of disarming.
- `melee_eliminates_anyone`: melee eliminates any target it connects with, gun holder or not (overrides the gunholder-only rule).

### Throwing

Melee weapons can be thrown (secondary input) with an 8.0 impulse toward the aim direction, plus a fixed upward boost so the throw arcs instead of flying flat (the same arc physics used for item throws — see §7). A 0.15s grace period prevents hitting yourself on release. A thrown weapon that lands still applies its effect at **50% magnitude** (and, for Stagger specifically, 50% of its bullet-immunity window too). After landing, it's on a 1.0s cooldown before it can be picked back up.

### Death drops & respawn

A weapon dropped by an eliminated holder despawns and returns to its spawn point after `dropped_melee_despawn_time` (default 3.0s; ≤0 disables despawn, meaning it stays on the ground indefinitely). `melee_spawn_delay` (default 0) can delay pickup availability at round start.

## 6. Disarming

A melee hit against the **gun holder** (when neither elimination rule above is active) disarms them: the gun is knocked loose, drops to the ground, and the disarmer gets credit (`player_disarmed` event, scoreboard "Disarms" stat). The disarmed player cannot re-pick the gun for `disarm_lock_time` seconds.

Online matches use the same melee rules. The host validates pickup distance, holder ownership, alive/round state, swings, throws, hit targets, disarms, effects, breaking and despawn/reset outcomes. The host also rolls the weapon type/effect/tier once per round and sends that identity to every peer, so all machines show and simulate the same weapon.

## 7. Items & Hazards

Held across **two item slots** (slots 2 and 3 — see §9), separate from the weapon slot, so you can carry a weapon *and* up to two items simultaneously. Item throws use the same aim-based-plus-upward-arc physics as melee throws (impulse 10.0 forward, plus a fixed upward boost), with the same 0.15s self-hit grace period.

- **Bubble Gum Trap**: thrown, deploys the instant it hits anything (world or player), slows anyone who walks into its area to 0.5× speed for 2.0s. Redeploys/respawns 12.0s after being triggered.
- **Grenade**: thrown with a **2.5s fuse** that starts the moment it leaves your hand — it keeps flying/bouncing until the fuse runs out, then detonates wherever it currently is (not on first contact). On detonation, everyone within a **6.0m radius** — including the thrower — gets knocked back at a flat strength of 4.0 (same scale as melee's strongest Knockback tier). Unlike melee knockback, it grants **no bullet-immunity window** afterward — it's meant to be riskier than a melee hit, not safer. Respects friendly-fire/team rules the same as other hazards. Respawns 12.0s after use. Uses a real model now; the detonation itself is still just a simple flash effect pending final VFX/SFX.
- `hazards_enabled` / `consumables_enabled` are master toggles; `item_registry` provides per-item enable switches on top of those (both Bubble Gum Trap and Grenade are categorized as hazards).
- The two currently exist as **separate, independent pickups** on the map (not a shared/rotating spawn) — both are placed on the Coliseum and NukeTown maps.
- **Bots do not pick up items** — only humans currently interact with the item slot (see [TODO.md](TODO.md)).

### New items (2026-07-11)

| Item | Type | Behavior |
|---|---|---|
| Smoke Bomb | consumable | 1.2s fuse; deploys a ~4m vision-blocking cloud for 6s. No damage. |
| Bear Trap | hazard | Deploys where it lands, sits open up to 20s; first player in gets rooted 1.5s (stagger), trap snaps shut. One use. Owner-safe per `can_affect`. |
| Decoy | consumable | Deploys one fake player for up to 10s. It runs straight forward by default; the owner can press **C** to toggle mirrored movement control (gamepad is unbound by default). Bots target it like a real player, while attacks and hostile traps affect or pop it. The owner and protected teammates cannot destroy it. An enemy gunshot pop briefly outlines the shooter for 0.5s; trap-triggered pops do not. It awards no kill credit. |
| Boomerang | consumable | Flies ~10m out and returns over ~1.7s; disarms a gun holder on hit (respects melee shields, grants the victim 1s immunity), knocks back anyone else. Auto-caught on return if a slot is free. |
| Spring Pad | hazard | Deploys where it lands, lives 30s; launches anyone who steps on (players AND bots), 0.5s per-body cooldown. |

**Sounds** (2026-07-11): gunshot on fire; Swing_Sound on every melee swing; per-weapon hit sounds (Sword_Clash / Stick_Hitting / Crow_Bar_Hit / BaseballBat_hit / Frying_Pan); footsteps per stride (0.38s walk / 0.26s sprint cadence, grounded only, muted by Silent Steps).

Online matches use the same marker placements, item pools, two-slot inventory rules, fuses and respawn/reroll timings. The host validates pickup range/ownership, drops, throw direction, deployment, collisions and gameplay effects, then broadcasts the resulting pickup/deployed object/effect to every peer. Loose-item movement from Magnet Hands is also host-resolved. Visual thrown-object physics may differ slightly in flight under latency, but the host's final deployment position is authoritative.

## 8. Powerups

Powerups spawn at map markers as bobbing/rotating pickups. Each orb has a camera-facing world label above it showing its current name, colored to match the orb. Its type is **fixed at spawn** and changes only when that powerup respawns after collection.

| Powerup | Effect |
|---|---|
| Extra Dash | +1 dash charge for 5.0s |
| Extra Melee Shield | Blocks the next disarm attempt (single use, no timer) |

Respawns 15.0s after being collected.

### New powerups (2026-07-11)

| Powerup | Effect | Bots? |
|---|---|---|
| Speed Surge (green) | ×1.4 move speed for the duration | yes |
| Silent Steps (slate) | footsteps muted for the duration | n/a (bots have no footsteps) |
| Vampire Touch (red) | landed melee hits refund 30 stamina | yes |
| Second Wind (orange) | survive one elimination with 2s bullet immunity (one charge, shows as ∞ until used) | yes |
| Magnet Hands (violet) | loose items within 4m get pulled to you | no |

Powerup type is **fixed at spawn** and re-rolls only when the orb respawns after being collected. Items and powerups now spawn at map-placed `item_spawn_point` / `powerup_spawn_point` markers each round — a random enabled item per item marker (pool = `GameConfig.ITEM_SCENES` filtered by `is_item_enabled`). **Marker items also re-roll into a new random type each time they respawn mid-round** (after being used/deployed), the same way powerups re-roll — so a grenade spot might become a bear trap next respawn. Marker-spawned nodes are tracked via the `marker_spawned` group and freed/re-spawned each round reset.

Online powerup collection is host-validated and applied on every peer. Persistent defensive state is resolved by the host: Second Wind prevents the authoritative elimination before scores/deaths change, and the disarm shield is consumed authoritatively. The disarm shield blocks exactly one melee/boomerang disarm against a gun holder; it never blocks bullets or grants bullet immunity. Temporary immunity caused by a knockback/stagger melee effect remains a separate mechanic and expires authoritatively even when the affected actor belongs to a client. The online HUD shows the local player's three inventory slots, active item and active powerup timers.

## 9. Inventory, Picking Up, and Dropping

Three slots total: **slot 1** is the weapon slot (gun or melee weapon, mutually exclusive), **slots 2 and 3** are item slots.

- **Tap interact**: instantly picks up a nearby object into an empty slot, or **swaps** it for whatever's currently occupying that slot's category — melee-for-melee, item-for-item, or melee-for-gun. The item you swap away is left exactly where the new one was sitting (not dropped at your feet).
- **Hold interact for 0.5s**: drops whatever's in the *currently active* slot. This only kicks in if the initial tap didn't already resolve as a pickup or swap — so standing next to a valid swap target and tapping always swaps; it never accidentally drops first.
- **The gun is the one exception to tap-swapping**: it's never swapped away by a tap. A gun holder must hold interact for the full 0.5s to voluntarily give it up before they can pick up a melee weapon. Picking the gun *up* (from a melee weapon or empty-handed) is always an instant tap, same as everything else.
- **Cycling** (Q/E, or bumpers) moves between *occupied* slots only, skipping empty ones: weapon → item slot 2 → item slot 3 → back to weapon. Fire/swing only act on the weapon slot; **throw acts on whichever slot is currently active** — throwing something sitting in slot 3 means cycling to it first.
- When both item slots are full and you interact with a new item on the ground, it swaps into whichever item slot is currently active (not automatically the oldest or newest).
- Dying drops everything you're holding — gun, melee weapon, and both items — at your position.

## 10. Controls

Two independent input sets exist for splitscreen (`p1_*` / `p2_*` action prefixes) plus a shared single-player set. Keyboard/mouse (P1 default) and gamepad (P2 default in splitscreen, either can use gamepad) are both fully supported, including gamepad look with a configurable response curve.

Core actions: move (WASD / stick), look (mouse / right stick), jump (Space / A/Cross), sprint (Shift, hold-or-toggle configurable), dash (Ctrl), fire (LMB / RT-analog), swing melee (LMB), ADS (RMB / LT-analog), interact/pickup/drop (E or F depending on binding / gamepad face button — tap vs. hold, see §9), throw (G / button, acts on the active slot), cycle slots (Q/E or bumpers).

## 11. Match Settings (configurable per-lobby, save/load-able as presets)

All of the following are toggled in the lobby (`game_setup.gd`) and stored on the `GameConfig` autoload; up to 5 full presets ("house rules") can be saved to disk and reloaded:

The list includes the host-adjustable `round_time_limit` and `chaos_overtime_enabled` rules in addition to the combat, item, bot, and scoring settings below.

`teams_enabled`, `friendly_fire_enabled`, `melee_eliminates_gunholder`, `melee_eliminates_anyone`, `melee_effects_hit_anyone` (default **true** — see §5), `melee_spawn_delay`, `gun_spawn_mode`, `disarm_lock_time`, `max_dash_charges`, `dropped_melee_despawn_time`, `melee_weapon_breaking`, `rounds_per_set`, `sets_per_match`, `hazards_enabled`, `consumables_enabled`, `item_registry`, `bot_configs` (per-bot difficulty + team).

## 12. Bots

Bots (`dummy.gd`) fight for the gun, melee, and powerups using the same rules as humans (minus item usage — see §7). Bots keep their own simplified single-item pickup logic rather than the two-slot tap/swap/hold system above — see [ARCHITECTURE.md](ARCHITECTURE.md). Four difficulty tiers change reaction time, aim cone, move speed, fire cooldown, and tactical options:

| | Easy | Medium | Hard | Expert |
|---|---|---|---|---|
| Reaction time | 0.4–0.8s | 0.25–0.45s | 0.1–0.2s | 0.05–0.12s |
| Gun aim cone | 12.0° | 6.0° | 2.5° | 0.5° |
| Move speed mult | 0.85× | 1.0× | 1.1× | 1.15× |
| Fire cooldown mult | 1.2× | 1.0× | 0.85× | 0.7× |
| Can retreat | No | No | Yes | Yes |
| Can dash | No | Yes (defensive) | Yes (defensive+aggressive) | Yes (defensive+aggressive) |
| Prefers high melee tier | No | No | No | Yes |

Bot objectives (`idle`, `get_gun`, `gunner_position`, `get_melee`, `get_powerup`, `chase_holder`, `retreat`) are re-evaluated on a reaction-time timer per difficulty.

## 13. Scoring / Scoreboard (TAB)

Tracked per player for the whole match: kills, deaths, disarms, gun pickups, melee hits landed, plus set/round wins. Sorted by sets won, then rounds won (not kills). Top 3 highlighted gold/silver/bronze; eliminated players greyed out.
