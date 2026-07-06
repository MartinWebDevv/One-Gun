# One Gun — TODO / Known Gaps

> Compiled from a full read-through of the codebase on 2026-07-06. Items are grouped by kind, not by priority — see the "Recommended Priorities" section at the bottom for suggested order.

## Explicitly Unfinished (code says so)

- **In-match music is not wired up.** `audio_manager.gd`'s `MUSIC_PATHS["game"]` entry is commented out with an instruction comment to drop a file into `res://audio/` and uncomment it. Menu music works; matches are silent.
- **Most SFX are commented out.** `audio_manager.gd`'s `SFX_PATHS` has entries stubbed for gun pickup/drop, disarm, round start/end, death — all commented out, no audio files present. Only UI hover/click sounds are live.
- **Main menu button stagger animation was gutted for debugging.** `main_menu.gd`'s `_stagger_page_buttons()` has a comment stating the slide/stagger animation was "stripped for debugging" — buttons fade in but no longer slide/stagger as apparently originally designed. Needs restoring or intentionally removing the dead code path.
- **Online multiplayer is a disabled stub.** The "Online" button in `main_menu.gd` exists and is visibly disabled (`online_btn.disabled = true`); its handler does nothing. No networking code exists anywhere in the project — this is a placeholder for a feature not yet started, not a partially-built one.
- **Player 2's name is session-only.** `GameConfig.player2_name` is explicitly commented as "session-only, not saved to disk — P2 may be a different guest each time." This looks intentional (P2 is a rotating local guest) but is worth confirming with design intent rather than assuming it's an oversight.

## Likely Gaps (inferred from behavior, not commented)

- **Bots never use the item slot.** `dummy.gd` has logic to fight over the gun, melee weapon, and powerup, but no path for picking up or throwing consumable items (e.g. the bubble gum trap). Confirm whether this is intentional (bots shouldn't get hazard advantages) or missing behavior.
- **No player cosmetics/customization system**, despite the settings UI existing for controls/audio/FOV — there's no model color, outfit, or skin selection anywhere. If a "Customize Your Character" entry point exists in menu copy/design intent, it currently has no backing implementation.
- **Melee kill-feed icon fallback is a hardcoded match statement.** `melee_weapon.gd`'s `_get_weapon_icon()` matches on `weapon_data.weapon_name` string and falls back to 💀 for anything unrecognized — adding a 6th weapon to the registry without updating this function silently loses its icon.
- **Bot line-of-sight check uses `collision_mask = 1`** (world geometry only) — worth verifying bots can't "see"/shoot through other players standing between them and a target, since player collision may be on a different layer (per `project.godot`, layer 2 = "Players").
- **Theme resource is re-saved to disk every launch.** `theme_manager.gd` calls `ResourceSaver.save()` unconditionally in `_ready()` with no existence/diff check — harmless today but worth guarding if theme-building becomes more expensive or this runs somewhere hot.

## Housekeeping / Repo Hygiene

- **No git repository initialized.** All work is currently unversioned; recommend `git init` plus a `.gitignore` review (one already exists at `.gitignore`, worth double-checking it excludes `.godot/` and import caches) before further work, so changes are recoverable.
- **`ONEGUN.zip` sitting in the project root** — looks like a manual backup snapshot; confirm it's not meant to be tracked, and consider moving it outside the project folder once git is initialized.
- **Stray Godot editor autosave/temp files**: `game_setup.tscn573602726996.tmp`, `game_setup.tscn573634723216.tmp`, `node_3d.tscn557102750531.tmp`, `node_3d.tscn557116189349.tmp`, `node_3d.tscn557231172196.tmp`, `node_3d.tscn81350665721.tmp`. These typically appear after an editor crash or unclean shutdown — worth checking whether any contain unsaved work not present in the committed `.tscn`, then deleting them.
- **Duplicate/stray UID file**: `item.gd - Copy.uid` in the project root suggests a copy-paste artifact from a duplicated `item.gd` at some point; confirm there's no orphaned duplicate script and remove the stray `.uid`.
- **`docs/CODING_STANDARDS.md` exists but is empty** — out of scope for this pass (not one of the four requested files), but flagged since it sits alongside the docs just populated.

## Design Decisions Worth Confirming With the Team

- Should online play be attempted at all, or is "local-only" a permanent design pillar? This affects whether the disabled menu button should be removed entirely or left as a future placeholder.
- Is melee-as-disarm-only (rather than melee-as-kill) the intended default forever, or was `melee_eliminates_*` meant to graduate from "house rule" to a first-class game mode selector?
- Should bots eventually use items, or is that a deliberate "humans only" hazard-balance choice?

## Recommended Development Priorities

1. **Wire up core audio feedback** (gunshot, hit, disarm, elimination, round-start/end SFX + in-match music). Right now combat has zero audio feedback beyond menu sounds, which is likely the single biggest gap between "functionally complete" and "feels good to play." Low code risk — mostly asset integration into an existing, working `AudioManager`.
2. **Resolve the main menu stagger animation** — either restore it or intentionally simplify the code, since a "stripped for debugging" comment left in place is a sign of an interrupted task, and it's very low effort to close out.
3. **Decide and implement (or explicitly close out) bot item usage** — this is a small, contained AI behavior addition if it's wanted, and worth resolving before it's forgotten.
4. **Initialize version control** before making further changes — there is currently no way to diff, branch, or recover from a bad edit. This is unrelated to gameplay but is the highest-leverage non-gameplay task available.
5. **Clean up stray temp/backup files** (`.tmp` autosaves, `ONEGUN.zip`, stray `.uid`) once git is in place, so the working tree reflects only intentional files.
6. **Only after the above**: consider new-feature work (cosmetics, online play, additional weapons/maps) — these are larger scope and better tackled once the existing systems are polished and version-controlled.
