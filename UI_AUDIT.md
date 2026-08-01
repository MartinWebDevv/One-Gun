# One Gun UI Audit

## Summary

The UI is more complete than the sparse scene files suggest. Most screens and HUD elements are assembled and styled at runtime in GDScript. The visual direction is a rounded, playful arcade presentation using Fredoka, dark translucent panels, gold highlights, color-coded status cards, animated banners, and emoji/text weapon identities.

The main missing UI-backed feature is character customization. Its lobby button and popup entry point exist, but the popup has no functional content. There is also no dedicated loading-screen scene; loading feedback is handled by lobby/start flow and coordinated scene changes.

## UI architecture

### Theme

- `ThemeManager` builds a shared theme and helper styles at startup.
- `one_gun_theme.tres` is configured as the project-wide custom theme.
- Fredoka variable font is used with runtime weight variations.
- Common styling helpers include panels, pills, headings, bold text, punch/flash animations, and gold-accented controls.

Audit concern: `ThemeManager` saves `one_gun_theme.tres` back into `res://` every launch. This is unnecessary runtime project mutation and may be unsuitable in a packaged/read-only environment.

### Runtime construction

`main_menu.tscn`, `game_setup.tscn`, and `player_settings.tscn` contain minimal static structure. Their scripts create most labels, buttons, panels, scroll containers, settings rows, and popups dynamically. In-match UI is similarly composed through multiple focused scripts and runtime-built online HUD elements.

Benefits:

- Centralized look and responsive runtime behavior.
- Local and online screens can adapt to role/state.
- Reusable widget scripts isolate focused presentation.

Risks:

- Scene inspection alone does not reveal the actual interface.
- Large UI scripts are difficult to review visually.
- Node names, lookup paths, and construction order become implicit contracts.
- Layout regressions lack automated screenshot coverage.

## Screen audit

### Main menu

Files: `main_menu.tscn`, `main_menu.gd`, `maps/test/title_bg_map.tscn`, `title_background.gd`.

Implemented:

- Live SubViewport 3D map background.
- Vignette and title treatment.
- Local Play.
- Online Play.
- Player Settings.
- Quit.
- Playtest/version tag.
- Button hover/click audio.
- Online Host/Join panel.
- Host lobby-name entry.
- Join lobby-name or direct Tailscale IP entry.
- Host Tailscale address/status tip.
- Connection status/error feedback.

Placeholder/provisional:

- Version label is hardcoded as `v0.9 • playtest build`, while export metadata says `0.0.1`/`0.01`.
- The background is a stripped legacy NukeTown-style scene rather than a purpose-built title environment.
- Main-menu stagger animation is explicitly stripped for debugging; buttons are simply shown.

### Game setup/lobby

Files: `game_setup.tscn`, `game_setup.gd`, `lobby_map_preview.gd`.

Implemented:

- Local and online lobby modes.
- Map selection and live gameplay preview.
- Host-authoritative online controls.
- Online roster and synchronized names.
- Each peer can edit only its own display name.
- Bot count and per-bot difficulty configuration.
- Human/bot cap at eight total actors.
- Match rule controls mirroring `GameConfig`.
- Item category and per-item toggles.
- Match preset save/load slots.
- Ready state and host Play/Force Play behavior.
- Client read-only/synchronized settings presentation.
- Online team/friendly-fire controls disabled/labeled as offline-only.

Placeholder/incomplete:

- `CustomizeCharacterPopup` opens, but no customization controls or backing data exist.
- `_on_customize_popup_closed()` is empty by design.
- A map vote mode is represented in code, but no actual peer voting system exists; selection falls back to host behavior.
- There is no explicit loading-screen scene or per-peer loading progress bar.

Preservation note: the gameplay preview is active functionality and should remain enabled. It intentionally keeps environmental animation processing active while rendering at a reduced internal resolution.

### Player settings

Files: `player_settings.tscn`, `player_settings.gd`, `player_prefs.gd`.

Implemented sections:

- Music/SFX/UI volume controls.
- Mouse and gamepad sensitivity.
- FOV/display settings.
- Gameplay toggles such as sprint behavior.
- Crosshair color.
- P1/P2 input rebinding for movement, jump, sprint, dash, interact, fire/swing/use, throw/drop, ADS, and slot cycling.
- Persistent `user://player_prefs.json` storage.
- Standalone mode from main menu.
- Overlay mode from pause menu.

Current presentation is functional and themed. The script is large because it constructs rows, bindings, sections, validation, and persistence behavior in one place.

### Pause menu

Files: `pause_manager.gd`, `pause_menu.gd`.

Implemented local behavior:

- ESC opens/closes pause.
- SceneTree pauses locally.
- Resume.
- Settings overlay.
- Return/exit confirmation.

Implemented online behavior:

- ESC opens a local overlay without pausing the SceneTree.
- Host sees Return to Lobby and can return everyone.
- Client does not see Return to Lobby.
- Host Main Menu ends the session for everyone.
- Client Main Menu disconnects only that client.

The role-aware behavior is implemented and should be preserved.

## In-match local HUD

### HUD composition

Local map scenes contain a `CanvasLayer`, player HUD containers, split-screen viewport containers, and match-wide HUD nodes. Focused scripts include:

- `player_ui_container.gd`.
- `stamina_bar.gd`.
- `dash_charges.gd`.
- `inventory_slots.gd`.
- `gun_ui.gd`.
- `melee_ui.gd`.
- `item_ui.gd`.
- `reload_spinner.gd`.
- `powerup_status.gd`.
- `crosshair.gd`.
- `hit_marker.gd`.
- `status_label.gd`.
- `round_label.gd`.
- `kill_feed.gd`.
- `match_hud.gd`.

### Implemented player information

- Stamina bar with caption, smooth movement, and empty feedback.
- Dash charges rendered as flat/rounded pips aligned to the stamina width.
- Three inventory slots: one weapon and two item slots.
- Gold active/equipped item highlight.
- Drop-hold progress.
- Gun ready/reloading state.
- Melee identity.
- Item identity.
- Reload spinner/progress.
- Active powerup cards and timers.
- Crosshair and hit/elimination confirmation marker.
- Player status/spectator state.

There is no health bar because the game has no numeric health system.

### Implemented match information

- Round and set labels.
- Countdown/GO/winner banners.
- Alive/remaining-player drama states.
- Gun pickup/drop notifications.
- Kill/disarm feed.
- TAB scoreboard.
- Kills, deaths, pickups, melee hits, and disarms.
- Round/set/match scores.

## Online HUD

File: `online_hud.gd`.

Online maps remove the baked local HUD and create one machine-local HUD bound to the locally owned network actor.

Implemented:

- Countdown, GO, round winner, set/match state.
- Alive count and remaining-player presentation.
- Local stamina and dash charges.
- Gun/melee/item state.
- Reload progress.
- Three-slot inventory matching local play.
- Equipped-item indication and drop-hold progress.
- Active powerups.
- Kill/disarm feed.
- TAB scoreboard with local-row highlight.
- Spectator state.
- Remote player name tags.
- Local crosshair color.
- Role-aware online ESC overlay.

The online HUD is now feature-comparable to the local HUD for core match awareness. It does not contain online team presentation because teams are not implemented online.

## World-space UI

Implemented world indicators include:

- Pickup labels on weapons/items.
- Gun locator arrow while loose.
- Gun-holder outline.
- Remote online name tags.
- Interaction/status text.

These are functional but primarily text/emoji/procedural presentation rather than a finished icon system.

## Placeholder UI inventory

| Area | Placeholder/provisional element | Evidence |
|---|---|---|
| Lobby | Character customization | Empty popup and no data/system |
| Lobby | Map voting | Mode represented but no vote collection/resolution |
| Loading | Dedicated loading screen | No loading scene or progress UI found |
| Main menu | Version/build identity | Hardcoded playtest copy conflicts with export metadata |
| Main menu | Background environment | Reused legacy/prototype map presentation |
| Main menu | Entry animation | Explicitly disabled for debugging |
| World/HUD | Weapon/item iconography | Mostly emoji, text, and colored procedural cards |
| Powerups | World pickup visual | One generic colored emissive sphere for all seven types |
| Match VFX/UI | Grenade impact | Bare sphere flash, with no dedicated explosion audio |

## UI wins to preserve

- Local and online inventory presentation now follows the same mental model.
- Host/client controls communicate authority correctly.
- Online pause does not stop replication.
- Scoreboard highlights the local actor.
- Remaining-player presentation builds round tension effectively.
- The theme kit creates a recognizable arcade identity without requiring many texture assets.
- Persistent rebinding covers both local players.
- Map preview is useful lobby feedback and should remain functional.
- Per-widget scripts isolate most HUD display responsibilities from gameplay logic.

## UI risks and future validation

These are documentation findings, not implementation work:

1. Character customization should remain clearly marked unavailable until a real data/art design exists.
2. Runtime-created layouts need a manual resolution/splitscreen matrix: fullscreen, windowed, P1-only, split P1/P2, host lobby, client lobby, online match, spectating, and long player names.
3. Build/version copy should eventually come from one source.
4. Theme generation should be separated from runtime project-file writing.
5. Online loading should eventually expose timeout/readiness state instead of appearing stalled when one peer is slow.
6. Text and emoji weapon/item identity should be treated as provisional unless intentionally accepted as the final style.
7. The preview and large runtime scripts should be included in every lobby regression pass because most UI does not exist in the static scenes.
