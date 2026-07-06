# One Gun — Game Rules

> Source of truth: this document describes mechanics as implemented in the codebase as of 2026-07-06. Numbers are pulled directly from `character_body_3d.gd`, `game_config.gd`, `melee_weapon_registry.gd`, `round_manager.gd`, `gun.gd`, `powerup.gd`, `item.gd`, and `dummy.gd`. Where a value is configurable per-match, the default is listed and the setting name is noted.

## 1. Overview

One Gun is a local (couch) arena shooter for 1–8 competitors (humans + bots), playable single-player or 2-player splitscreen. Exactly **one gun** and **one melee weapon** exist per match — everyone else fights over item pickups, powerups, and whatever they can improvise. Matches are structured as **rounds → sets → match**, elimination-based, last-one-standing per round.

## 2. Match Structure

- A **round** ends when ≤1 player (or ≤1 team, in team mode) remains alive, or in a simultaneous-elimination draw.
- Winning a round adds 1 to that player's `round_wins`. Reaching `rounds_per_set` (default **3**) wins the **set** and adds 1 `match_points`.
- Reaching `sets_per_match` (default **3**) wins the **match**, returning everyone to the lobby.
- Display timings: countdown before round start **3s**, round-end banner **3s**, set-end banner **4s**, match-end banner **6s** (all configurable on `RoundManager`).
- Player/team cap: **8 total**. Solo mode allows up to 7 bots; splitscreen (2 humans) allows up to 6 bots.

## 3. Movement

| Stat | Value |
|---|---|
| Walk speed | 10.0 m/s |
| Sprint speed | 18.0 m/s |
| Jump velocity | 4.5 m/s (impulse) |
| Max stamina | 100 |
| Stamina drain (sprinting) | 25/sec |
| Stamina regen (at rest) | 20/sec, after a 1.0s delay following sprint |

**Dash**: 30 m/s burst for 0.2s. Default **2 charges**, each recharging in 3.0s independently. Max charges configurable 0–6 (`max_dash_charges`, hard ceiling enforced in code).

**Knockback / stagger** (inflicted by melee hits — see §5): freezes horizontal velocity (knockback, 0.2s) or all movement (stagger, duration scales with weapon tier) and grants temporary bullet immunity afterward so a disarmed/staggered player isn't instantly finished off.

**Aiming**: ADS (aim-down-sights) transitions over 0.2s, tightens FOV by 0.9×, and pulls the camera boom in to 0.3 (from the default 4.0). ADS halves look sensitivity by default (configurable, `ads_sensitivity_multiplier`).

## 4. The Gun

- **One gun spawns per match** — no ammo pickups, no second gun.
- Semi-automatic: one shot per trigger pull, then a reload.
- Reload time: ~1.0s.
- Bullet speed: 60 m/s, hitscan-adjacent (fast projectile, camera-aimed).
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

### Effects (randomly rolled per weapon instance, one of three)

- **Normal**: no status effect; a hit on the gun holder disarms them (see below).
- **Knockback**: shoves the target back; distance and post-hit bullet-immunity scale with tier (2.0 / 3.0 / 4.0 units; 1.5s / 1.0s / 0s immunity).
- **Stagger**: freezes the target; duration and immunity scale with tier (1.0s / 1.5s / 2.0s stagger; matching immunity window). Higher tier = longer escape window for the staggered player.

### Swing lifecycle

Windup (wind-up pose, no hit) → Active (hitbox live) → Recovery (weapon resets). Stamina cost is paid **upfront** at swing start. Swinging while in stamina deficit twice in a row **breaks the weapon** for 5.0s (it respawns at its spawn point) — this can be disabled via `melee_weapon_breaking`.

### Elimination rules (match settings)

- By default, melee **cannot** eliminate — it only disarms the gun holder or bumps/knocks back others.
- `melee_eliminates_gunholder`: a melee hit on the current gun holder eliminates them outright instead of disarming.
- `melee_eliminates_anyone`: melee eliminates any target it connects with, gun holder or not (overrides the gunholder-only rule).

### Throwing

Melee weapons can be thrown (secondary input) with an 8.0 impulse toward the aim direction. A 0.15s grace period prevents hitting yourself on release. A thrown weapon that lands still applies its effect at **50% magnitude**. After landing, it's on a 1.0s cooldown before it can be picked back up.

### Death drops & respawn

A weapon dropped by an eliminated holder despawns and returns to its spawn point after `dropped_melee_despawn_time` (default 3.0s; ≤0 disables despawn, meaning it stays on the ground indefinitely). `melee_spawn_delay` (default 0) can delay pickup availability at round start.

## 6. Disarming

A melee hit against the **gun holder** (when neither elimination rule above is active) disarms them: the gun is knocked loose, drops to the ground, and the disarmer gets credit (`player_disarmed` event, scoreboard "Disarms" stat). The disarmed player cannot re-pick the gun for `disarm_lock_time` seconds.

## 7. Items & Hazards

Held in a separate **item slot** (distinct from the weapon slot — you can carry a weapon *and* an item simultaneously).

- **Bubble Gum Trap** (currently the only implemented consumable): thrown, deploys on impact, slows anyone who walks into its area to 0.5× speed for 4.0s. Redeploys/respawns 12.0s after being triggered.
- Item throw impulse: 10.0, with the same 0.15s self-hit grace period as melee throws.
- `hazards_enabled` / `consumables_enabled` are master toggles; `item_registry` provides per-item enable switches on top of those.
- **Bots do not pick up items** — only humans currently interact with the item slot (see [TODO.md](TODO.md)).

## 8. Powerups

One powerup spawns on the map (bobbing/rotating pickup). Its type **cycles every 1.5s** until collected, so players must react to grab the type they want.

| Powerup | Effect |
|---|---|
| Extra Dash | +1 dash charge for 5.0s |
| Extra Melee Shield | Blocks the next disarm attempt (single use, no timer) |

Respawns 15.0s after being collected.

## 9. Controls

Two independent input sets exist for splitscreen (`p1_*` / `p2_*` action prefixes) plus a shared single-player set. Keyboard/mouse (P1 default) and gamepad (P2 default in splitscreen, either can use gamepad) are both fully supported, including gamepad look with a configurable response curve.

Core actions: move (WASD / stick), look (mouse / right stick), jump (Space / A/Cross), sprint (Shift, hold-or-toggle configurable), dash (Ctrl), fire (LMB / RT-analog), swing melee (LMB), ADS (RMB / LT-analog), interact/pickup (E or F depending on binding / gamepad face button), throw (G / button), cycle weapon-item slot (Q/E or bumpers).

## 10. Match Settings (configurable per-lobby, save/load-able as presets)

All of the following are toggled in the lobby (`game_setup.gd`) and stored on the `GameConfig` autoload; up to 5 full presets ("house rules") can be saved to disk and reloaded:

`teams_enabled`, `friendly_fire_enabled`, `melee_eliminates_gunholder`, `melee_eliminates_anyone`, `melee_spawn_delay`, `gun_spawn_mode`, `disarm_lock_time`, `max_dash_charges`, `dropped_melee_despawn_time`, `melee_weapon_breaking`, `rounds_per_set`, `sets_per_match`, `hazards_enabled`, `consumables_enabled`, `item_registry`, `bot_configs` (per-bot difficulty + team).

## 11. Bots

Bots (`dummy.gd`) fight for the gun, melee, and powerups using the same rules as humans (minus item usage — see §7). Four difficulty tiers change reaction time, aim cone, move speed, fire cooldown, and tactical options:

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

## 12. Scoring / Scoreboard (TAB)

Tracked per player for the whole match: kills, deaths, disarms, gun pickups, melee hits landed, plus set/round wins. Sorted by sets won, then rounds won (not kills). Top 3 highlighted gold/silver/bronze; eliminated players greyed out.
