# One Gun — Design Notes

> This document infers design intent from the current implementation (code comments, tuning values, and structural choices). It's a snapshot of what the game *is*, written so future work stays consistent with decisions already made — not a pitch document.

## 1. Core Premise

There is only **one gun** per match, shared by everyone. Whoever holds it has the power to one-shot anyone; everyone else's job is to take it from them, avoid it, or use the replenishing melee/item supply to create an opening. The gun's scarcity is the central design pillar — the game is built around constant tension over who controls it, not around gun loadouts or ammo economy.

## 2. Design Pillars (as evidenced by the code)

**Scarcity creates drama, supply keeps everyone active.** The gun remains singular. Every authored melee marker begins populated and independently replenishes 5s after pickup; every item and powerup marker is likewise populated and replenishes on an 8s pickup/collection cycle. Random type/effect/tier rolls keep those counterplay tools eventful without diluting the one-gun objective.

**Melee is a disarm tool, not a kill tool, by default.** `melee_eliminates_gunholder` and `melee_eliminates_anyone` both default to `false` in `game_config.gd`. The base design intends melee to threaten the gun holder's *possession* of the gun, not their life — killing with melee is an optional house rule, not the default loop. This is reinforced by `melee_weapon_registry.gd`'s comment that weapon tiers change speed/stamina, "never damage," explicitly to avoid a tier feeling like a power spike in a fight that's mostly about disarming.

**Speed and stamina are the resource layer, not health.** There's no health/damage system anywhere — elimination is binary (bullet = dead, melee = disarm/knockback/stagger unless house rules say otherwise). The tension budget instead lives in stamina (sprint and swings cost it) and dash charges (finite, recharging). This keeps the skill expression in *positioning and timing*, not damage-race math.

**Bullet immunity windows exist so tension doesn't collapse instantly.** After a stagger or knockback, the victim gets a brief window of bullet immunity (scaling 0–2s by melee tier). This is transient combat protection rather than an unearned Sticky Hands or Extra Life charge. Without it, "get staggered → get shot" would be an unavoidable death loop; the immunity window preserves a chance to scramble away, which matters more as melee tier (and thus stagger duration) goes up.

**Rounds > kills for scoring.** The scoreboard sorts by sets won, then rounds won — not kill count. Individual kills/deaths/disarms/pickups/melee-hits are tracked and shown, but they're flavor stats, not the win condition. The game rewards *surviving/winning rounds*, consistent with a last-one-standing structure where a single elimination can end your round regardless of your kill count.

## 3. Structural Choices

**Everything is a rule toggle.** `GameConfig` centralizes ~16 fields that reshape the ruleset (teams, friendly fire, melee lethality, dash charges, despawn timers, item categories, bot configs), and these can be saved/loaded as up to 5 named presets. This suggests the game is designed to be tuned live by a group of friends setting "house rules" before a session, similar to board-game variant rules — not a fixed competitive ruleset.

**Bots exist to fill an asymmetric local multiplayer gap.** Because splitscreen only supports 2 human players but the match supports up to 8 combatants, bots (with 4 difficulty tiers) are the mechanism for scaling a 1–2 person session into a full arena match. Their behavior mirrors human capabilities (dash, retreat, melee tier preference at Expert) rather than being a separate simplified system.

**Spectating keeps eliminated players engaged.** `spectator_controller.gd` gives eliminated players a follow-cam (cycle through living players) or a free-fly cam rather than booting them to a menu. Follow mode also mirrors the target's complete HUD read-only, preserving tactical context after death instead of leaving the spectator detached from the round.

## 4. Tone & Presentation

**Irreverent/scrappy weapon theming.** The melee weapon roster (Sword, Baseball Bat, Stick, Crowbar, Frying Pan) and the visible asset pool (elemental-themed sword variants, a literal "cat" character model orange running animation, a water gun model) point to a comedic, low-stakes "friends messing around" tone rather than a grim shooter aesthetic. The kill feed uses emoji icons (⚔ 🪃 🪵 🔧 🍳 💀 🔫) rather than a serious combat log style, reinforcing this.

**Elimination is celebratory rather than gory.** Players, bots, and decoys share the same bright confetti burst and party-favor pop, keeping even a lethal round beat aligned with the game's playful tone. Accessibility settings soften its emission/flash intensity without changing the event itself.

**Color customization identifies players without changing power.** Human competitors choose among texture-only color variants on one shared V2 model and rig. Duplicate colors are allowed because cosmetics are expressive rather than team/identity enforcement; names, team chips, and combat indicators remain the authoritative gameplay signals. Selection is intentionally preview-first and requires Confirm, preventing an accidental hover/cycle from silently changing a persistent or network identity. Each color's three-quarter headshot follows that confirmed identity through the main-menu profile and every local/online human lobby row. Decoys copying the owner's color is part of their deception rather than a separate cosmetic choice.

**UI leans into escalating drama as players die.** `match_hud.gd`'s remaining-player counter changes presentation as the round thins out: small/muted at >5 alive, larger and pulsing at 3–5, "FINAL TWO" at 2, "LAST ONE STANDING" at 1 — each stage bigger, more central, and more animated than the last. This is a deliberate pacing device to build tension as a round approaches its end, independent of what's happening in 3D.

**Menu presentation invests in juice.** `main_menu.gd` has a bouncing/overshooting title animation, a pulsing gold glow, staggered button fade-ins, and a live 3D background viewport with idle character models and a panning camera — more visual polish than the strictly functional lobby/settings screens, suggesting first impressions were prioritized early.

## 5. Open Design Questions (not yet resolved in code)

- **Online play** is stubbed (menu button present, disabled) — the game is currently local-only by design or by not-yet-implemented status; worth clarifying which.
- **Future cosmetic scope** is unresolved beyond the implemented color/texture selector — outfits, accessories, and alternate models have no current rules or pipeline contract.
- **Bots and items**: bots never pick up consumable items, meaning hazards like the bubble gum trap are currently a human-vs-human (or human-vs-environment) tool only. Worth deciding if this is intentional balance (bots don't get "unfair" hazard advantages) or an unfinished feature.
- **Audio identity is unset**: no in-match music or SFX are wired up yet (menu music/UI SFX only), so the moment-to-moment feel of combat currently has no audio feedback for shooting, hits, disarms, or eliminations.
