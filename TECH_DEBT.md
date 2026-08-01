# One Gun Technical Debt

This document records observed debt and risk only. It does not authorize refactoring, cleanup, deletion, rebaking, optimization, or gameplay changes.

## Priority definitions

- **Critical**: can invalidate the current playable/network baseline or block reliable testing.
- **High**: likely to cause bugs, data loss, broken builds, or expensive future changes.
- **Medium**: maintainability, performance, or workflow debt with bounded current impact.
- **Low**: cleanup or consistency issue with limited immediate risk.

## Critical findings

### TD-001: Full online smoke is not stable across current maps

Evidence:

- CityMap online-bot mode passed on host and client.
- ForestMap full match failed once at `Magnet Hands did not move a loose item host-authoritatively`, then passed once on repeat.
- WesternV2Map full match failed twice at the same Magnet Hands assertion.
- After host failure, the client cascaded into a match-completion timeout.

Risk:

- A current authoritative powerup can behave differently by map or timing.
- A failing host-side test tears down the session before the client can report the original state cleanly.
- Existing historical claims that all three maps pass are not true for this audited working tree/run.

Future evidence needed:

- Interactive host/client reproduction with item position logs.
- Determine whether the fault is gameplay, marker/physics/map-scale behavior, or a brittle smoke assertion.
- Add a test that reports the loose item's start/end position and ownership instead of only the final assertion.

### TD-002: Current selectable map navigation data appears absent

Evidence:

- Forest, Western V2, and City each declare a NavigationMesh and agent settings.
- None of their `.tscn` files serializes navigation vertices or polygons.
- No external navigation resource is referenced.
- Legacy `node_3d`, NukeTown, and title background scenes do serialize 209 polygons.
- Older docs claim Forest/Western baked counts that are not present now.

Risk:

- Bots may move directly without obstacle-aware paths, fail on elevation/interiors, or rely on a state not stored in source control.
- A developer may assume older navigation verification still applies.

Future evidence needed:

- Inspect polygon counts in the live editor.
- Visualize navigation for all three maps.
- Run route tests before any rebake/save decision.

## High-priority findings

### TD-003: Documentation drift changes the apparent product state

Conflicts include:

- Online described as stubbed despite phases 1-2e being implemented.
- Bots described as unable to use items despite item AI.
- One melee described despite 6-8 authored melee placements per current map.
- Powerups described both as cycling and fixed.
- TODO items listed as missing at the top and resolved later in the same file.
- Current map/navigation claims that do not match scene serialization.
- Coding standards called empty despite a substantial file.

Risk:

- Future work may reimplement completed systems, remove intentional behavior, or tune against false rules.

### TD-004: Core scripts combine too many responsibilities

Approximate line counts:

| Script | Lines | Responsibilities concentrated there |
|---|---:|---|
| `round_manager.gd` | 1,543 | Local match, online match, spawn/reset, score, actors, melee/items/powerups, deployed effects, RPCs |
| `character_body_3d.gd` | 1,194 | Movement, camera, input, inventory, combat, effects, animation, networking, elimination |
| `dummy.gd` | 1,110 | AI, navigation, movement, all combat/items/effects, online puppet behavior |
| `game_setup.gd` | 1,019 | Local/online lobby, map preview, bots, every rule widget, presets, ready/name flow |
| `melee_weapon.gd` | 973 | Identity, pickup, swing, throw, effects, disarm, local/online presentation |
| `main_menu.gd` | 612 | Runtime UI, viewport, navigation, online panel/discovery |
| `network_manager.gd` | 545 | Discovery, ENet, roster, scene/config/readiness/exit flow |
| `item.gd` | 538 | Generic item lifecycle plus online hooks |

Risk:

- Small changes cross local/online/bot/UI responsibilities.
- Review and testing scope is difficult to bound.
- Merge conflicts are likely during concurrent development.

No refactor is recommended until the current behavior baseline is locked with tests.

### TD-005: Human and bot gameplay logic is duplicated

Duplicated areas include:

- Movement/stamina/dash constants.
- Step-up casts.
- Knockback/stagger/slow/immunity state.
- Weapon/item state.
- Powerup effects.
- Animation mapping.
- Online synchronization fields.

Values already differ, for example human and bot speed/stamina/dash tuning.

Risk:

- Bug fixes and balance changes can reach one actor type but not the other.
- Online host bot behavior can diverge from human gameplay semantics.

### TD-006: `GameConfig` default item registry is incomplete

The live registry contains seven items. `DEFAULT_VALUES.item_registry` contains only bubble gum and grenade.

Risk:

- Reset to defaults replaces the registry with two entries.
- Five items fall through `is_item_enabled()` as unknown and therefore enabled.
- Category/per-item UI may no longer control those items as expected after reset/load.

This is a data-integrity bug in the configuration baseline, not just code style.

### TD-007: Online networking is robust for a private playtest but incomplete for adverse conditions

Known limitations:

- No host migration.
- No reconnect/resume.
- No in-progress late join.
- No interpolation/lag smoothing.
- No client-side shot prediction.
- Owner-authoritative movement has no anti-cheat validation.
- No public lobby/rendezvous service.
- Named discovery relies on the local Tailscale CLI and host peer list.
- Teams/friendly fire are unavailable online.
- Some death-drop positions can drift; gun has no eventual drop resync.
- Melee/item pickup proximity validation is weaker than gun pickup validation according to prior review notes.

Risk:

- Real latency and disconnect behavior can differ substantially from loopback tests.

### TD-008: Godot/Terrain3D editor pipeline is not cleanly verified

Evidence:

- Terrain3D 1.0.2 is enabled.
- No current scene references a Terrain3D node.
- `desertTerrain/` resources have no live references.
- Headless editor initialization reached a completed file scan/layout, but the Terrain3D debug DLL hot-reload/copy failed while another editor process held the DLL.
- A transient untracked `~libterrain...TMP` file was visible.
- Restricted audit AppData permissions also produced editor-cache errors; those specific errors are environment-related and should not be treated as project defects.

Risk:

- Native add-on state can prevent a clean editor/import/export run.
- The project ships platform binaries for an apparently unused plug-in.

Future evidence needed:

- Close all Godot processes, reopen once normally, and verify Terrain3D loads without temp artifacts.
- Confirm whether the plug-in/data are still intentionally required before any removal decision.

### TD-009: Windows export preset is inconsistent

Evidence:

- Platform is Windows Desktop.
- Export path ends in `ONEGUNtest.zip`, while normal Windows export expects an executable path.
- Version fields disagree: preset name `v0.0.1`, file version `0.0.1`, product version `0.01`, UI `v0.9 • playtest build`.
- No application icon is configured in export options.
- `export_filter="all_resources"` includes legacy, tool, and candidate-unused content.

Risk:

- Export may fail, produce a misleading zero-byte file, or require undocumented manual packaging.
- Players cannot reliably identify matching builds.

### TD-010: Imported asset source and licensing are incomplete

Evidence:

- No `.blend` files.
- No licenses/attribution/source manifest.
- Character, animation, weapon, music/SFX, environment, and legacy Western sources are not fully recorded.
- Pre-optimization Tripo originals are stored outside the repository.

Risk:

- Public distribution rights may be unclear.
- Assets may be impossible to reproduce or safely modify on another machine.

### TD-011: Orange bot model is far over budget

Verified approximately:

- 24.67 MB GLB.
- 660,636 triangles.
- 337,130 vertices.
- Four 2048x2048 images.

Risk:

- Multiple bots multiply rendering, skinning, memory, import, and load costs.
- This violates the project's own >10 MB intake warning.

## Medium-priority findings

### TD-012: No automated local gameplay tests

There is no unit/integration framework for local match rules, configuration, inventory, movement, bots, or map markers. The online two-process smoke driver is valuable but large and stateful.

Risk:

- Local regressions are discovered only through manual play.
- One broad online failure can mask later assertions.

### TD-013: Online smoke shutdown emits engine errors/warnings

Observed messages include:

- ObjectDB instances leaked.
- Renderer dummy mesh/material/shader RID leaks.
- Lambda capture freed/passed as null.
- Sync data from non-authority or missing node.
- Unauthorized/missing received despawn node.

Some may be artifacts of rapid test teardown after pass/failure, but they reduce signal quality and may hide real lifecycle issues.

### TD-014: Animation mapping depends on numeric import order

Human and bot scripts load `Dance.glb`, obtain the animation list, and map hardcoded indices to semantic names.

Risk:

- Re-exporting/reimporting can reorder actions and silently attach the wrong animation to a name.
- The standalone individual animation scenes are not used as explicit sources.

### TD-015: UI is heavily runtime-built

Large runtime UI scripts construct most controls and styles.

Risk:

- Static scene review does not catch full UI structure.
- Layout and focus/accessibility regressions require manual execution.
- Long names, non-1600x900 resolutions, and split viewports need explicit matrix testing.

### TD-016: Theme resource is written into `res://` at runtime

`ThemeManager` unconditionally saves the generated theme each launch.

Risk:

- Dirty worktree churn in editor.
- Failure or undefined behavior in read-only/exported packages.
- Runtime/editor responsibilities are mixed.

### TD-017: Blender tools are machine-specific

Every generator hardcodes `D:\Godot Projects\one-gun\...`; preview output points to a specific Claude scratch directory. Map builders require temporary autoload edits.

Risk:

- Pipeline fails on another workstation or repository location.
- Temporary autoload workflow can leave project configuration altered if interrupted.
- Full map builders can overwrite hand edits.

### TD-018: Current source assets contain exact duplicates

Examples:

- Thirteen identical cat-color PNGs.
- Repeated environment pack Albedo/Normal/Metallic textures.
- Multiple autosave temp scenes.

Risk:

- Larger repository/import footprint and ambiguity about canonical source.

Do not deduplicate animation textures without testing imports and GLBs; apparent duplication may be coupled to importer paths.

### TD-019: Audio pipeline is incomplete and heavy

Evidence:

- Approximately 77.89 MB under `audio/`.
- Three source WAVs account for about 65 MB.
- An 11.01 MB track has no live reference.
- Pickup/drop/disarm/round/death SFX are missing/commented.
- No dedicated Music/SFX/UI audio buses.

Risk:

- Export size, load/memory cost, and inconsistent mixing.
- Important gameplay events lack feedback.

### TD-020: Collision and authority assumptions need adversarial validation

Examples:

- Bot LOS uses world-only collision mask 1.
- Player collision is on a separate layer.
- Owner-authoritative movement is trusted.
- Current melee/item online proximity validation is not equivalent to the gun path.
- Map root scaling requires compensating actor code.

Risk:

- Shooting through intervening actors, invalid pickups, or scale/authority regressions.

### TD-021: Legacy marker schemas and map content coexist with current systems

- NukeTown uses `bot_spawn_point` rather than `spawn_point`.
- Legacy maps lack item/powerup/gun marker groups.
- Older docs still name removed/commented maps.

Risk:

- Accidentally re-enabling a map can produce invalid spawning or partial gameplay.

### TD-022: Candidate-unused assets and add-on data are not classified

Candidates include legacy environment GLBs, five sword variants, four bottle models, animation wrapper scenes, an unused music track, Terrain3D resources, and other legacy content.

Risk:

- `all_resources` exports ship content that may be unused.
- Removing content without a reference/provenance pass could break dynamic paths.

### TD-023: Item/powerup/VFX presentation is partly placeholder

- Generic colored powerup sphere.
- Primitive bullet.
- Sphere-flash grenade explosion.
- Simple gum-trap mesh.
- Missing matching audio.

Risk:

- Gameplay identities are less readable than the systems deserve.
- Placeholder and intentional minimalist style are not formally distinguished.

## Low-priority findings

### TD-024: Stray and temporary files

- Six root Godot `.tmp` scene autosaves.
- `item.gd - Copy.uid` without a matching copied script.
- Terrain native-library hot-reload temp artifacts while the editor is open.

These should be investigated only after intended worktree changes are committed and all scenes are safely saved.

### TD-025: Stale comments and names

Examples:

- NetworkManager header still references an earlier phase and older architecture.
- RoundManager comments refer to phases as future after implementation.
- `Scenes/weternMap/` typo.
- `DummyModel`/`dummy.gd` naming is generic relative to its production role.
- `maps/test/` contains current maps.

Renaming paths is not recommended during stabilization; documentation/comments can eventually be reconciled without resource migrations.

### TD-026: Future purchase hook exists without a system

`melee_weapon.gd.upgrade_tier()` is commented as a future purchase-tier upgrade. No currency, purchase, or upgrade system exists.

Risk is low today, but the hook may mislead future readers into assuming a planned/active system.

### TD-027: Main-menu version and animation debug state

- Version text is hardcoded and inconsistent with export metadata.
- Button stagger animation is intentionally stripped for debugging.

These are visible polish debt rather than core functional risks.

## Technical wins to preserve

- Host-authoritative combat and score outcomes.
- Round epoch guards against stale actions/projectiles.
- Stable actor IDs separate from controlling peer IDs.
- Stable `RoundManager` RPC coordinator for reparented objects.
- Readiness handshake instead of a fixed load sleep.
- Local/online behavior gated cleanly enough to reuse map scenes.
- Central `GameConfig` and `GameEvents` contracts.
- Marker-preserving online content assignment.
- Reusable two-process smoke harness.
- Deterministic low-poly generators and an explicit asset budget.
- City builder retirement note protecting hand-tuned work.

## Risk order before new development

1. Reproduce and classify TD-001.
2. Confirm TD-002 in the editor and with route tests.
3. Establish a clean committed baseline and reconcile TD-003.
4. Verify a clean Terrain3D/editor state and Windows export path.
5. Run real two-machine Tailscale tests.
6. Only then decide which maintainability, pipeline, and content debts belong in the next approved phase.
