# One Gun — Design Notes

> This document infers design intent from the current implementation (code comments, tuning values, and structural choices). It's a snapshot of what the game *is*, written so future work stays consistent with decisions already made — not a pitch document.

## 1. Core Premise

There is only **one gun** and **one melee weapon** per match, shared by everyone. Whoever holds the gun has the power to one-shot anyone; everyone else's job is to take it from them, avoid it, or beat the holder to death first. This scarcity is the entire design pillar — the game is built around constant tension over who has the gun, not around loadouts or weapon variety.

## 2. Design Pillars (as evidenced by the code)

**Scarcity creates drama.** One gun, one melee weapon, one powerup on the map at a time. `powerup.gd`'s type-cycling-until-grabbed mechanic and the melee weapon's random tier/effect roll both exist to make the *single* pickup feel eventful rather than static loot.

**Melee is a disarm tool, not a kill tool, by default.** `melee_eliminates_gunholder` and `melee_eliminates_anyone` both default to `false` in `game_config.gd`. The base design intends melee to threaten the gun holder's *possession* of the gun, not their life — killing with melee is an optional house rule, not the default loop. This is reinforced by `melee_weapon_registry.gd`'s comment that weapon tiers change speed/stamina, "never damage," explicitly to avoid a tier feeling like a power spike in a fight that's mostly about disarming.

**Speed and stamina are the resource layer, not health.** There's no health/damage system anywhere — elimination is binary (bullet = dead, melee = disarm/knockback/stagger unless house rules say otherwise). The tension budget instead lives in stamina (sprint and swings cost it) and dash charges (finite, recharging). This keeps the skill expression in *positioning and timing*, not damage-race math.

**Bullet immunity windows exist so tension doesn't collapse instantly.** After a stagger or knockback, the victim gets a brief window of bullet immunity (scaling 0–2s by melee tier). Without this, "get staggered → get shot" would be an unavoidable death loop; the immunity window preserves a chance to scramble away, which matters more as melee tier (and thus stagger duration) goes up.

**Rounds > kills for scoring.** The scoreboard sorts by sets won, then rounds won — not kill count. Individual kills/deaths/disarms/pickups/melee-hits are tracked and shown, but they're flavor stats, not the win condition. The game rewards *surviving/winning rounds*, consistent with a last-one-standing structure where a single elimination can end your round regardless of your kill count.

## 3. Structural Choices

**Everything is a rule toggle.** `GameConfig` centralizes ~16 fields that reshape the ruleset (teams, friendly fire, melee lethality, dash charges, despawn timers, item categories, bot configs), and these can be saved/loaded as up to 5 named presets. This suggests the game is designed to be tuned live by a group of friends setting "house rules" before a session, similar to board-game variant rules — not a fixed competitive ruleset.

**Bots exist to fill an asymmetric local multiplayer gap.** Because splitscreen only supports 2 human players but the match supports up to 8 combatants, bots (with 4 difficulty tiers) are the mechanism for scaling a 1–2 person session into a full arena match. Their behavior mirrors human capabilities (dash, retreat, melee tier preference at Expert) rather than being a separate simplified system.

**Spectating keeps eliminated players engaged.** `spectator_controller.gd` gives eliminated players a follow-cam (cycle through living players) or a free-fly cam rather than booting them to a menu — a deliberate choice for local multiplayer sessions where a friend shouldn't be staring at a black screen for the rest of the round.

## 4. Tone & Presentation

**Irreverent/scrappy weapon theming.** The melee weapon roster (Sword, Baseball Bat, Stick, Crowbar, Frying Pan) and the visible asset pool (elemental-themed sword variants, a literal "cat" character model orange running animation, a water gun model) point to a comedic, low-stakes "friends messing around" tone rather than a grim shooter aesthetic. The kill feed uses emoji icons (⚔ 🪃 🪵 🔧 🍳 💀 🔫) rather than a serious combat log style, reinforcing this.

**UI leans into escalating drama as players die.** `match_hud.gd`'s remaining-player counter changes presentation as the round thins out: small/muted at >5 alive, larger and pulsing at 3–5, "FINAL TWO" at 2, "LAST ONE STANDING" at 1 — each stage bigger, more central, and more animated than the last. This is a deliberate pacing device to build tension as a round approaches its end, independent of what's happening in 3D.

**Menu presentation invests in juice.** `main_menu.gd` has a bouncing/overshooting title animation, a pulsing gold glow, staggered button fade-ins, and a live 3D background viewport with idle character models and a panning camera — more visual polish than the strictly functional lobby/settings screens, suggesting first impressions were prioritized early.

## 5. Open Design Questions (not yet resolved in code)

- **Online play** is stubbed (menu button present, disabled) — the game is currently local-only by design or by not-yet-implemented status; worth clarifying which.
- **Player cosmetics/customization** has no implementation despite an apparent intent (see [TODO.md](TODO.md)) — unclear how far this is meant to go (recolors vs. full outfits).
- **Bots and items**: bots never pick up consumable items, meaning hazards like the bubble gum trap are currently a human-vs-human (or human-vs-environment) tool only. Worth deciding if this is intentional balance (bots don't get "unfair" hazard advantages) or an unfinished feature.
- **Audio identity is unset**: no in-match music or SFX are wired up yet (menu music/UI SFX only), so the moment-to-moment feel of combat currently has no audio feedback for shooting, hits, disarms, or eliminations.
