# ONE GUN Menu Systems Ultra Packet — Claude Code

## Mission

Implement the approved ONE GUN menu redesigns and their associated functionality inside the existing Godot project.

This packet covers:

- Local Play lobby and map selection.
- Connected Match Settings and Bot Settings panels.
- Online Play browser, Quick Join, Join by Code, and Host Lobby creation.
- Online lobby host and guest states.
- Ready-state and Force Start behavior.
- Player Settings overlay and every category.
- Functional graphics settings and persistent controls.
- Deep crosshair customization, behavior, and feedback.
- Local pause menu.
- Online host and non-host match menus.
- Shared UI theme, navigation, persistence, accessibility, responsive layout, and verification.

The approved main menu already has its own implementation packet and may already exist in the project. Do not rebuild or replace it. Extend its established scene, theme, map-preview, profile, and navigation systems where appropriate.

---

# 1. How to Use This Packet

Give Claude Code:

1. The existing ONE GUN repository.
2. This Markdown packet.
3. The approved concept images listed in the reference manifest.

Recommended execution method:

- Send Section 0 first.
- Allow Claude Code to inspect the repository and report its findings.
- Then send one numbered implementation phase at a time.
- Run and visually approve the project at every stop point.
- Do not ask Claude Code to execute a later phase until the current phase passes its acceptance gate.

If you intentionally want a continuous run, tell Claude Code:

```text
Execute the packet in order. Treat every STOP POINT as an internal verification checkpoint. Do not skip validation, overwrite existing systems, fake unavailable networking, or continue past a genuine blocker. Report checkpoint results as you progress.
```

Primary reference resolution is 1920x1080. The finished interface must also support common 16:9 resolutions, window resizing, and ultrawide safe areas.

---

# 2. Approved Reference Manifest

Place the approved images in a repository folder such as:

```text
docs/ui/reference/menu_redesign/
```

The original generated filenames are listed below so the images can be identified even if they are renamed.

| Semantic reference | Original filename | Authority |
| --- | --- | --- |
| Local Play lobby | `exec-54deba46-4952-415b-8ff4-c365778467ab.png` | Approved visual target |
| Match Settings slide-out | `exec-1044e63d-e3c3-4c93-a58e-ca0635b898c6.png` | Approved visual target |
| Bot Settings slide-out | `exec-bbc520e6-140f-4cfb-b6c0-70df4c0fe721.png` | Approved visual target |
| Online lobby — host | `exec-d6e73042-8aa1-48f6-9ce3-9b23be1b2902.png` | Approved visual target |
| Online lobby — guest/not ready | `exec-8b19a6e8-3ffa-4052-a0d7-ca9c5f754dad.png` | Approved visual target plus locked behavior below |
| Online Play browser | `exec-f1df4dcc-1172-44d5-84ee-bbaf3ad2f3bb.png` | Approved visual target |
| Host Lobby creation | `exec-ee4097dc-8863-4c6f-bc4c-2c832af05e69.png` | Approved visual target |
| Player Settings — Gameplay | `exec-8b519930-897f-4e95-8781-09035687284d.png` | Approved settings-shell target |
| Player Settings — Audio | `exec-a32923a5-4ba9-424a-b1f5-bb583c1f3caf.png` | Approved except remove Audio Preview panel |
| Player Settings — Video | `exec-f3b33062-ddfb-4d98-b15c-e63ba9891645.png` | Approved visual and functional target |
| Player Settings — Controls | `exec-78d8debf-52c1-425c-9a4b-13dc6c5a13d0.png` | Approved visual and functional target |
| Player Settings — Accessibility | `exec-31ad4b7c-36e5-4d6a-b7e2-00b8db32349e.png` | Approved visual and functional target |
| Crosshair editor — Shape | `exec-99146eba-a811-4458-a5ea-b1ed0503b462.png` | Approved visual and functional target |
| Crosshair editor — Behavior | `exec-8dac4fc5-bc93-4472-9e29-cdcacadb205d.png` | Approved visual and functional target |
| Online match menu — host | `exec-1f76b846-d981-43b5-91a4-932d53a97d1e.png` | Approved visual target |
| Local pause menu | `exec-b5c7ee32-120f-4ebc-ba5e-12c18897b719.png` | Approved visual target |
| Online match menu — non-host | `exec-2c1344a3-e8b6-411f-82ca-6f664ecd8434.png` | Approved visual target |

If an image filename changes, identify it by its content and semantic reference. Do not depend on these generated filenames at runtime.

## Visual-reference rules

- Treat the approved images as composition and styling targets, not as flat textures to place over the screen.
- Rebuild interactive surfaces with Godot Control nodes, containers, Theme resources, StyleBoxes, NinePatchRects, vector/raster icons, shaders, and reusable scenes.
- Use live map scenes where a concept shows a map preview.
- Preserve existing game branding and remove any accidental `TOY BOX LEAGUE` or `TOY BOX ARENA` wording.
- The concept art may contain illustrative data. Runtime names, map descriptions, player counts, readiness, and networking data must come from the game state.
- If a visual detail conflicts with a locked behavior in this packet, the written locked behavior wins.

---

# 3. Non-Negotiable Operating Rules for Claude Code

```text
Work directly in the existing ONE GUN repository.

Before editing:
1. Read AGENTS.md and all applicable repository instructions.
2. Inspect git status and preserve unrelated user changes.
3. Identify the Godot version, renderer, project entry points, autoloads, UI scenes, current main menu, local lobby, online lobby, networking service, settings storage, input actions, gameplay HUD, player cameras, crosshair, map registry, and test strategy.
4. Locate existing fonts, icons, Theme resources, shaders, audio buses, profile data, settings data, and navigation helpers.
5. Report the files expected to change and genuine blockers.

During implementation:
- Extend existing working systems instead of replacing them without evidence.
- Do not stop at a plan when safe implementation is possible.
- Keep networking authoritative and do not fake online discovery or readiness.
- Do not replace live maps with screenshots.
- Do not make decorative settings that do nothing.
- Do not duplicate existing autoloads, managers, profile models, map registries, or lobby state.
- Keep UI code separate from gameplay, networking, and persistence services.
- Preserve controller, keyboard, and mouse navigation.
- Do not modify unrelated combat, map, character, weapon, or networking behavior.
- Never hard-code player names, lobby codes, map names, or roster entries from concept art.
- Use typed GDScript when compatible with the project style.
- Keep new resources and scenes modular and reusable.
- Do not commit or push unless explicitly asked.

After each phase:
- Run the safest relevant Godot import, parser, project startup, scene, tests, and multiplayer checks available.
- Capture a fresh 1920x1080 screenshot for visual comparison.
- Report files changed, tests run, results, remaining differences, and blockers.
- Stop at the phase's STOP POINT.
```

---

# 4. Locked Shared Visual Language

All redesigned menus must look like parts of the same physical ONE GUN toy interface.

## Core palette

- Deep navy and black-blue cabinet faces.
- Layered metallic-gold outer borders and warm inner highlights.
- Cream/off-white primary text.
- Gold primary actions and selected controls.
- Purple secondary selection and Player Settings actions.
- Blue/cyan informational and network states.
- Green confirmed/ready/success states.
- Red destructive, not-ready, leave, and danger states.

## Materials and construction

- Rounded, finished edges rather than sharp low-poly corners.
- Multiple border layers to create physical depth.
- Recessed content wells and raised tactile buttons.
- Small bolts/rivets only where they support the physical-cabinet look.
- Soft upper-left highlights and lower-right shadows.
- Restrained reflections, glow, bloom, and texture.
- Avoid flat rectangles, excessive gradients, noisy scratches, and unreadably dark panels.

## Typography

- Reuse the approved/project ONE GUN display face for major headings if licensed and available.
- Use a highly readable project font for descriptions, values, and help text.
- Provide fallback fonts for missing glyphs.
- Avoid baking important runtime text into images.

## Shared interaction states

Every interactive control must support:

- Normal.
- Hover.
- Keyboard/controller focus.
- Pressed.
- Selected.
- Disabled/locked.
- Error where applicable.

Focus must never be communicated only by color. Combine outline, glow, scale, icon, or motion. Keep motion subtle and honor reduced-motion settings.

## Shared motion

- Panel open/close: approximately 0.18–0.28 seconds.
- Connected slide-out: approximately 0.25–0.35 seconds.
- Map-preview fade: approximately 0.6–0.8 seconds.
- Hover scale: restrained, approximately 1.01–1.025.
- Avoid continuous bouncing or large spring overshoot.

## Shared responsive rules

- Design at 1920x1080.
- Verify at 1280x720, 1600x900, 1920x1080, and 2560x1440.
- Preserve a 16:9 safe composition on ultrawide displays.
- Support UI scale settings without clipping.
- Use anchors and containers rather than absolute-only placement.
- Maintain minimum readable text and hit-target sizes.

---

# 5. Target Architecture

Adapt names to the existing repository rather than creating duplicates blindly.

Recommended separation:

```text
UI Theme / Tokens
  -> shared StyleBoxes, fonts, colors, spacing, icons, animation timings

Menu Router / Overlay Coordinator
  -> opens and closes main-menu overlays, settings, lobby panels, and match menu

Lobby View Models
  -> convert local/online lobby state into display-ready data

Networking Service
  -> discovery, hosting, joining, privacy, lobby code, roster, readiness

Settings Model
  -> persisted values, pending edit session, defaults, migration

Settings Appliers
  -> audio, gameplay, graphics, input, accessibility, crosshair

Crosshair Controller
  -> renders selected style and reacts to validated gameplay events
```

## Required principles

- UI scenes may request actions but must not contain networking authority.
- Host-authoritative state owns map, rules, roster, bots, readiness, and match start.
- Client settings are local and must never be replicated as gameplay state.
- A pending settings edit session must be separate from saved settings.
- Runtime-generated roster and lobby rows must use reusable row scenes.
- All long lists must support keyboard/controller navigation and scrolling.
- Signals must be connected once and disconnected cleanly when views close.
- Online and local screens should share components without forcing identical behavior.

---

# Phase 0 — Repository Audit and Integration Plan

## Prompt for Claude Code

```text
Execute Phase 0 of ONE_GUN_MENU_SYSTEMS_ULTRA_PACKET_CLAUDE_CODE.md.

Do not edit yet. Inspect the repository and report:
- Godot version and renderer.
- Existing main-menu, local lobby, online lobby, pause menu, settings, HUD, and crosshair scenes/scripts.
- Existing networking backend and whether it supports public discovery, friends-only discovery, private lobbies, join codes, host migration, and roster readiness.
- Current map registry and preview system.
- Current bot settings and match settings data models.
- Current settings storage and audio bus names.
- Current input actions and rebinding support.
- Current graphics/environment architecture and gameplay-camera ownership.
- Existing shared Theme resources, fonts, icons, and UI sounds.
- Existing tests and safe headless/interactive validation commands.
- Dirty git state and unrelated changes that must be preserved.

Create a concrete file-level integration plan mapping this packet to the existing code. Flag only genuine blockers and identify which requested networking features need backend work rather than UI work.

Do not implement later phases. Stop after the audit.
```

## Acceptance gate

- Existing systems are identified by file path.
- No duplicate-manager approach is proposed without justification.
- Networking capability gaps are explicit.
- The user can approve the integration plan before edits begin.

## STOP POINT 0

Stop and obtain approval.

---

# Phase 1 — Shared ONE GUN UI Foundation

## Goal

Build the reusable theme and components before rebuilding complete screens.

## Required reusable pieces

- Main cabinet/panel frame.
- Inset section frame.
- Gold, navy, purple, blue, green, and red action buttons.
- Icon button.
- Toggle switch.
- Slider and value box.
- Dropdown/select control.
- Checkbox.
- Tooltip/help icon.
- Tab and segmented control.
- Roster row.
- Lobby browser row.
- Map thumbnail card.
- Lock, host crown, ready X/check, bot, player, privacy, and warning indicators.
- Inline confirmation state.
- Inline validation/error message.
- Loading, empty, unavailable, and disabled states.
- Shared focus-navigation helper where the project needs one.

## Prompt for Claude Code

```text
Execute Phase 1 of the packet.

Implement a reusable ONE GUN UI theme and component library matching the approved concept references. Reuse and extend existing resources when possible.

Requirements:
- Centralize palette, font sizes, spacing, corner radii, border thickness, animation timings, and semantic colors.
- Build controls with Godot UI resources and reusable scenes; do not use full-screen concept screenshots as interface layers.
- Support mouse, keyboard, and controller focus states.
- Provide clear selected, disabled, locked, error, ready, and danger variants.
- Add restrained shared UI sounds only if the project already has an appropriate audio path.
- Create a component-gallery/debug scene showing every state at 1920x1080 and 1280x720.
- Do not rebuild complete lobby or settings screens yet.

Validate theme/resource loading and controller focus. Capture the component gallery. Report changed files and stop.
```

## Acceptance gate

- Components visibly match the approved navy/gold physical style.
- All semantic colors and states are consistent.
- Controller focus is clearly visible.
- Components resize without broken borders.

## STOP POINT 1

Stop for visual approval.

---

# Phase 2 — Local Play Lobby and Live Map Selection

## Approved layout

Use the Local Play lobby reference.

- Left cabinet extends downward to align with the bottom of the map-selection carousel.
- Back button is integrated into the left cabinet.
- Purple badge reads `SETTINGS`, not `BOTS`.
- Center/right area displays a live map preview.
- Bottom map carousel changes the selected map.
- Right roster expands up to ten entries.
- Local play does not use ready states.
- No standalone bot-count slider appears on the base lobby screen.

## Live map preview

- Reuse the existing live map-preview system if available.
- Map selection fades between previews over approximately 0.6–0.8 seconds.
- Preview state must not start gameplay, networking, bots, round logic, damage, or match HUD.
- Selected-map information includes:
  - Map name.
  - Short description.
  - Size.
  - Recommended player count.
  - Playstyle.
  - Hazard availability.
- Data comes from map metadata/resources, never hard-coded UI strings.

## Local roster

- Support one to ten local/bot slots according to existing local-play rules.
- Human local players show their profile/character identity where available.
- Bots show bot icons and difficulty.
- No Ready button or readiness requirement.
- Preserve splitscreen and controller-join behavior already in the game.

## Prompt for Claude Code

```text
Execute Phase 2 of the packet using the approved Local Play lobby reference.

Implement the themed Local Play screen and integrate it with the existing local-lobby, map-selection, bot, splitscreen, and match-start systems.

Requirements:
- Recreate the approved left cabinet, center live preview, bottom map carousel, right roster, integrated Back button, SETTINGS badge, and Play action.
- Remove the bot-count slider from the base screen.
- Fade live map previews for 0.6–0.8 seconds without freezing or leaking scenes.
- Populate all map information from a reusable map metadata source.
- Expand roster rendering safely to ten slots.
- Do not add local ready states.
- Preserve every existing local-play rule and match-start validation.
- Implement empty/loading/missing-preview states.
- Ensure changing selection does not accidentally start a map or spawn gameplay systems.

Validate map switching, roster sizes, splitscreen inputs, controller navigation, Play, and Back. Capture the screen at 1920x1080. Stop before implementing the connected settings slide-outs.
```

## Acceptance gate

- Visual layout matches the approved reference.
- Map selection and metadata are live and data-driven.
- No bot slider appears on the base lobby.
- Local Play still starts successfully.

## STOP POINT 2

Stop for approval.

---

# Phase 3 — Connected Match Settings and Bot Settings

## Shared panel behavior

- Clicking either settings button opens a panel that slides out from the left cabinet toward the right.
- The slide-out remains visually connected to the left cabinet.
- Only one slide-out may be open at a time.
- Clicking the active settings button, Back, Cancel, or Escape closes it safely.
- Unsaved pending changes must not mutate the active lobby until Apply.
- Switching panels must resolve pending edits predictably; do not silently apply them.

## Match Settings

Use the approved Match Settings reference.

- Tabs: `GENERAL`, `COMBAT`, `SPAWNS`, `PRESETS`.
- Include all existing match settings from the code, including settings not visible in the legacy screenshot.
- Examples include teams, friendly fire, melee elimination rules, hazard/consumable rules, gun spawn mode, disarm lock time, melee spawn delay, match-point or score/round settings, and all existing implemented rules.
- Do not delete existing settings merely because they are absent from the concept.
- Provide tooltips for non-obvious rules.
- Bottom actions: Apply, Cancel, Reset.
- Presets can load, edit, delete, and save according to existing capability.
- Validate preset names and prevent accidental overwrite/delete.

## Bot Settings

Use the approved Bot Settings reference.

- Bot Count uses a stepper or plus/minus control, never a slider.
- Valid count must respect current lobby capacity and human-player count.
- Provide `Set All Difficulty`.
- Each active bot has a dropdown with `Easy`, `Medium`, `Hard`, and `Expert`.
- Preserve per-bot difficulty values when count changes where practical.
- Bottom actions: Apply, Cancel, Reset.
- Bot configuration must feed the existing bot spawning/AI system.

## Prompt for Claude Code

```text
Execute Phase 3 of the packet.

Implement the approved connected Match Settings and Bot Settings slide-outs for Local Play.

Requirements:
- Panels slide right from and remain attached to the left lobby cabinet.
- Only one panel can be open.
- Use a pending edit model. Apply commits, Cancel discards, and Reset restores the correct default scope.
- Match Settings exposes every existing implemented rule through General, Combat, Spawns, and Presets tabs.
- Bot Settings uses a count stepper, Set All Difficulty, and individual Easy/Medium/Hard/Expert selectors.
- Capacity validation accounts for human players and the ten-slot maximum.
- Presets persist through the existing save system or a compatible migrated format.
- Add tooltips, focus order, scrolling, disabled states, and inline validation.
- Do not change gameplay semantics except to correctly connect settings that already exist.

Validate Apply/Cancel/Reset, preset persistence, all visible rule bindings, bot count, each bot difficulty, controller navigation, and match start. Capture both open panels. Stop.
```

## Acceptance gate

- Panels visually and physically connect to the lobby cabinet.
- Existing settings are not lost.
- Bot count and difficulty affect spawned bots.
- Pending edits do not leak before Apply.

## STOP POINT 3

Stop for approval.

---

# Phase 4 — Online Play Browser, Hosting, Quick Join, and Private Codes

## Online browser shell

Use the approved Online Play browser reference.

- Open as a large centered cabinet overlay over the dimmed live main menu.
- It should be wider and taller than the old Online Play popup.
- Primary actions:
  - `HOST LOBBY`.
  - `QUICK JOIN`.
  - `JOIN BY CODE`.
  - `REFRESH`.
- Include search and relevant privacy/mode filters where supported.
- Show loading, empty, unavailable, refresh-error, and disconnected states.

## Lobby list

Each row shows:

- Lobby name.
- Privacy: Public, Friends Only, or Private.
- Current/max players.
- Game mode.
- Lock/privacy icon.
- Joinability/full/in-progress status when known.

Joining methods:

- Double-click with mouse.
- Enter/Confirm with keyboard/controller.
- `JOIN SELECTED` button.
- A private lobby routes to the private-code screen instead of attempting an unauthenticated join.

## Quick Join

- Select a joinable lobby using the existing backend's best available criteria.
- Prefer public, not-full, compatible-version, not-in-progress lobbies.
- Never fabricate a result.
- Show a clear inline reason if no suitable lobby exists.

## Host Lobby form

Use the approved Host Lobby creation reference.

- Remains inside the same large Online Play cabinet; do not create a nested OS-style popup.
- Default lobby name is `<PlayerName>'s Lobby` and remains editable.
- Privacy choices: Public, Friends Only, Private.
- Maximum players: 2–10.
- Starting game mode defaults to `ONE GUN`.
- Private requires a host-provided lobby code.
- Public and Friends Only receive an automatically generated share code.
- Lobby code is the only access secret. Do not add a separate password.
- Validate blank/reserved names, invalid max players, duplicate/invalid codes, backend errors, and incompatible versions inline.

## Private code-entry state

This state is approved by written specification even though it does not have a separate rendered concept.

- Remains within the same large Online Play cabinet.
- Browser content fades/slides to a page titled `JOIN PRIVATE LOBBY`.
- If a private lobby row was selected, show a summary with lobby name, host, current/max players, game mode, and Private lock state.
- Large uppercase alphanumeric field with placeholder `ENTER LOBBY CODE`.
- Provide `PASTE`, `CLEAR`, `BACK TO LOBBIES`, and `JOIN LOBBY`.
- Wrong/expired/incompatible/full errors appear inline under the field.
- Error response uses a brief red field highlight and restrained shake; no popup.
- Direct `JOIN BY CODE` begins without a lobby summary. Once a valid code resolves, display the lobby summary before completing the join.

## Networking truth rule

The current screenshot shows Tailscale/direct fallback. Inspect the actual backend before implementation.

- If a real discovery service already exists, integrate it.
- If discovery can be added safely within the existing architecture, implement it with proper authority, timeouts, versioning, and cleanup.
- If no discovery backend or service contract exists and implementing one requires infrastructure or credentials outside the repository, do not fake an internet lobby list. Implement the service interface, UI states, and existing direct-code path, then stop and report the external blocker precisely.

## Prompt for Claude Code

```text
Execute Phase 4 of the packet using the approved Online Play browser and Host Lobby references plus the written private-code specification.

Implement the large themed Online Play overlay, lobby discovery list, search/filtering, Refresh, Quick Join, Join Selected, Join by Code, private-code entry, and Host Lobby form.

Requirements:
- Integrate the existing networking backend rather than replacing or simulating it.
- Populate rows from real discovery data.
- Support double-click, Enter/Confirm, and Join Selected.
- Implement Public, Friends Only, and Private semantics supported by the backend.
- Use lobby codes only; no separate password.
- Default host name to the current profile name plus "'s Lobby".
- Validate all forms inline.
- Use asynchronous operations with cancel/timeout/error handling and prevent double submission.
- Cleanly restore the main menu on Cancel/Close.
- Preserve the existing Tailscale/direct fallback where applicable.
- If infrastructure is genuinely missing, stop at the service boundary and report it rather than showing fake remote lobbies.

Test with at least two local game instances or the repository's networking harness. Capture browser, host form, and private-code states. Stop before rebuilding the joined online lobby.
```

## Acceptance gate

- Browser UI is data-driven and not populated with concept names.
- Host and join paths use the real backend.
- Private codes are validated securely enough for the existing architecture.
- No nested generic popup is used.
- Controller navigation and async error recovery work.

## STOP POINT 4

Stop for approval or external backend resolution.

---

# Phase 5 — Online Lobby Host and Guest States

## Shared layout

- Use the approved online lobby host and guest references.
- Reuse the live map preview and map carousel.
- Roster supports up to ten slots.
- Reserve layout space for possible future voice-chat indicators, but do not implement or display voice indicators now.
- Show lobby code, Copy, Invite where supported, and Privacy.
- Map/rules changes reset human readiness.
- Bots are considered automatically ready.

## Host behavior

- Host has a crown indicator.
- Host controls map, game mode, Bot Settings, Match Settings, privacy, and appropriate player management.
- Host can kick non-host human players through an inline confirmation or existing safe flow.
- Host can see readiness for every human player.
- Host cannot falsely mark another human ready.

## Guest behavior

- Host-controlled map, mode, bot settings, and match settings are locked/disabled.
- Guest sees `YOU` on their own roster row.
- Guest cannot kick, change privacy, change rules, or change maps.
- Guest has a Leave Lobby action.

## Ready button

Locked behavior:

- Not ready: large red button labeled `READY UP`.
- Ready: large green button labeled `READY`.
- Do not show a separate `YOU ARE NOT READY` message above it.
- Human roster rows use a red X when not ready and green check when ready.
- The local player's row updates immediately but reconciles with host authority.
- Changing the map or relevant rules resets every human player's readiness and communicates why.

## Host start logic

- If every required human player is ready, host button reads `START MATCH` and starts with one click.
- If one or more human players are not ready, host button reads `FORCE START`.
- First Force Start click changes the same button to red `CONFIRM`.
- Second click launches the match.
- No popup.
- Confirmation resets when:
  - Clicking elsewhere.
  - Pressing Escape.
  - Five seconds pass.
  - Lobby state changes.

## Prompt for Claude Code

```text
Execute Phase 5 of the packet using the approved online lobby host and guest references.

Implement the themed online lobby and integrate it with the real lobby state and host authority.

Requirements:
- Render a ten-slot roster with host, YOU, bots, empty slots, ready X/check, and safe kick controls.
- Reserve but do not display future voice-chat indicator space.
- Host controls map, privacy, bots, match rules, and match start.
- Guest sees host controls locked and cannot invoke their actions.
- Not-ready action is a red READY UP button; ready action is a green READY button. Remove separate not-ready text.
- Bots are automatically ready.
- Map or rules changes reset human readiness.
- Implement START MATCH, FORCE START, and inline CONFIRM exactly as specified, including five-second and state-change cancellation.
- Keep readiness and start authority on the host/server.
- Handle host disconnect/migration according to existing networking behavior; do not invent unsafe authority transfer.
- Preserve lobby code Copy/Invite/privacy behavior supported by the backend.

Validate with host plus guest instances, readiness toggles, reset on rule/map change, kick permissions, normal start, force-start confirm, confirm timeout, guest leave, host return, and disconnect cleanup. Capture host and guest screens. Stop.
```

## Acceptance gate

- Host and guest permissions differ correctly.
- Ready state is authoritative and synchronized.
- Force Start never triggers on the first click.
- Guests cannot reach host-only actions through keyboard/controller focus or direct signal calls.

## STOP POINT 5

Stop for approval.

---

# Phase 6 — Player Settings Shell, Audio, and Gameplay

## Settings shell

Use the approved Player Settings Gameplay reference.

- Opens as a large overlay cabinet occupying roughly 88% of the viewport.
- It is not a separate blank settings scene.
- The dimmed and softly blurred live main-menu or gameplay context remains visible around the outer margins.
- Left categories:
  - Audio.
  - Gameplay.
  - Video.
  - Controls.
  - Accessibility.
- Selected category uses the purple dimensional tab treatment.
- Persistent bottom actions:
  - `DEFAULTS`.
  - `CANCEL`.
  - `APPLY`.
- Status line: `Changes are not saved until applied.`
- Player/character customization remains a separate future menu and must not appear here.

## Settings transaction model

- On open, snapshot current saved and active runtime settings.
- UI edits a pending settings model.
- Apply validates, applies, persists atomically, and refreshes the snapshot.
- Cancel restores any live-previewed values and closes without saving.
- Defaults resets the current category to recommended defaults in the pending model; it does not save until Apply.
- Close/X behaves like Cancel unless the existing project has an approved unsaved-change flow.
- Audio and crosshair may preview live, but Cancel must restore their opening values.
- Version and migrate the settings file so future additions do not corrupt older saves.
- Store local client settings under the existing profile/config system or a compatible `user://` ConfigFile. Do not network-replicate them.

## Audio tab

The Audio concept is approved with one correction:

- Keep Master Volume, Music Volume, and SFX Volume.
- Remove the entire `AUDIO PREVIEW` equalizer and `TEST SOUND` panel.
- Vertically center and comfortably space the three volume rows.
- Bind to the actual audio buses, using decibel conversion and a safe silence floor.
- Defaults: use current approved/project defaults.

## Gameplay tab

Approved controls:

- Mouse Sensitivity.
- Gamepad Sensitivity.
- ADS Sensitivity Multiplier.
- Gamepad Response Curve.
- Gamepad Sprint is Toggle.
- Mouse/Keyboard Sprint is Toggle.
- Invert Look Y-Axis.

Preserve any additional existing gameplay preferences and place them in logical sections without removing them.

## Prompt for Claude Code

```text
Execute Phase 6 of the packet.

Implement the approved Player Settings overlay shell, settings transaction/persistence model, Audio tab, and Gameplay tab.

Requirements:
- Open as a large cabinet overlay over the dimmed existing context, not a separate blank scene.
- Implement category navigation and persistent Defaults/Cancel/Apply actions.
- Separate pending, active, and saved settings.
- Cancel reliably restores live previews.
- Audio has only Master, Music, and SFX volume rows; remove the Audio Preview/Test Sound concept element.
- Bind audio sliders to real audio buses.
- Bind gameplay controls to the existing camera/input/player systems.
- Preserve additional existing gameplay preferences.
- Add numeric ranges, tooltips, keyboard/controller adjustment, and validation.
- Persist settings with a versioned format and load them before dependent scenes initialize.
- Opening Settings from the main menu and from an in-match menu must reuse the same scene and data model.

Validate Apply, Cancel, Defaults, restart persistence, missing/corrupt config recovery, audio buses, mouse/gamepad sensitivity, response curve, sprint modes, and invert look. Capture Audio and Gameplay screens. Stop.
```

## Acceptance gate

- Settings are functional and persist.
- Cancel fully reverts previews.
- Audio preview panel is absent.
- The same Settings UI works from main menu and match context.

## STOP POINT 6

Stop for approval.

---

# Phase 7 — Functional Video Settings and Controls Rebinding

## Video tab

Use the approved Video reference. Every displayed option must work.

### Display

- Window Mode: Fullscreen, Borderless, Windowed as supported.
- Resolution: populate valid display modes rather than hard-coding one list.
- V-Sync.
- Frame Rate Limit, including an unlimited option if supported.

### Graphics

- Quality Preset.
- Shadow Quality.
- Anti-Aliasing.
- Render Scale.

### Camera

- Field of View.
- FOV applies to every relevant gameplay camera without changing menu/showcase framing.
- Helper: FOV changes peripheral view, not aim sensitivity.

### Integration requirements

- Inspect the Godot version and renderer before choosing APIs.
- Use `DisplayServer` for window mode, size, and V-Sync where appropriate.
- Use `Engine.max_fps` or the project-equivalent for the frame cap.
- Apply MSAA/render scale through the actual active viewport/renderer settings.
- Apply shadow quality to the project's real lights/environment/shadow configuration.
- A Quality Preset must update the individual pending controls it owns.
- Changing an individual control after selecting a preset changes the displayed preset to Custom.
- Disable or hide unsupported renderer/platform options.
- Mark restart-required changes clearly only when genuinely required.
- On Cancel, restore the prior window/graphics state safely.
- Add a recovery guard for invalid resolution or display mode.

## Controls tab

Use the approved Controls reference.

- Sub-tabs: Keyboard & Mouse and Gamepad.
- Scrollable action list grouped into Movement, Combat & Actions, and any additional existing groups.
- Columns: Action, Primary, Secondary.
- Physical keycap/button presentation.
- Select a binding, then capture the next valid input.
- Escape cancels capture.
- Support keyboard keys, mouse buttons, mouse wheel where appropriate, gamepad buttons, and gamepad axes where appropriate.
- Detect conflicts and require inline confirmation before replacing/swapping.
- Provide per-row reset plus category Defaults behavior.
- Keep essential UI navigation recoverable; do not allow a player to make the menu impossible to control without an escape path.
- Persist InputMap overrides in the settings file and restore them on startup.
- Do not change multiplayer authority or gameplay actions beyond input mapping.

## Prompt for Claude Code

```text
Execute Phase 7 of the packet using the approved Video and Controls references.

Implement every Video option as a real runtime setting through a centralized graphics applier compatible with the project's Godot version and renderer. Implement full keyboard/mouse and gamepad rebinding through the existing InputMap/actions.

Requirements:
- No decorative graphics option may be left nonfunctional.
- Populate resolutions and supported modes from the platform.
- Implement V-Sync, FPS cap, presets, shadows, anti-aliasing, render scale, and gameplay-camera FOV.
- Presets and individual values stay synchronized, with Custom when values diverge.
- Unsupported settings are disabled/hidden with a reason.
- Implement transactional Apply/Cancel/Defaults and safe display recovery.
- Build grouped primary/secondary binding rows with capture, Escape cancel, conflict confirmation, per-row reset, scrolling, and persistence.
- Preserve controller access even after remapping and prevent duplicate signal/input capture.

Validate each graphics setting visibly or through runtime inspection, restart persistence, multiple resolutions, window modes, renderer compatibility, key conflict handling, keyboard navigation, and gamepad-only navigation. Capture both tabs. Stop.
```

## Acceptance gate

- Every visible graphics option changes the correct real system.
- Cancel restores window and graphics state.
- Rebindings affect gameplay and survive restart.
- A controller-only user cannot become trapped.

## STOP POINT 7

Stop for approval.

---

# Phase 8 — Accessibility and Complete Crosshair System

## Accessibility tab

Use the approved Accessibility reference.

### Readability

- UI Scale.
- Text Size.
- Colorblind Filter.
- High Contrast UI.

### Motion and flash

- Screen Shake intensity.
- Camera Bob intensity.
- Reduce Flashing.
- Motion Blur.

### Crosshair summary

- Style.
- Color.
- Size.
- Opacity.
- Outline.
- Small functional preview.
- `EDIT` opens the Crosshair Customization subpage inside the same settings cabinet.

All accessibility settings must affect real UI, camera, post-processing, effects, or crosshair behavior. If a system is not yet centralized, add a focused adapter rather than scattering checks throughout unrelated code.

## Crosshair rendering architecture

- Render the crosshair with a dedicated CanvasLayer/Control or existing HUD-native equivalent.
- Prefer procedural drawing or scalable project-native assets so geometry, color, thickness, gap, and opacity remain crisp at every resolution.
- Crosshair settings are local visual preferences only.
- Crosshair settings never change accuracy, projectile direction, recoil, spread, hit detection, or network state.
- Use viewport center/safe reticle location consistently with the current aiming system.
- Hide or alter the reticle only when existing gameplay states explicitly require it.

## Crosshair Shape tab

Use the approved Shape reference.

### Styles

- Classic.
- Dot.
- Ring.
- Cross + Dot.
- Brackets.
- Chevron.
- Minimal.
- Hidden.

### Shape and appearance controls

- Size.
- Thickness.
- Center Gap.
- Line Length.
- Center Dot.
- Dot Size when applicable.
- Color.
- Opacity.
- Outline On/Off.
- Outline Color.
- Outline Thickness.
- Glow On/Off.
- Glow Intensity.

### Preview

- Live preview updates immediately.
- Preview backgrounds: Dark, Bright, Forest, Desert, Neon.
- These may use lightweight representative thumbnails/colors; do not load full gameplay maps merely for the settings preview.
- Preview states must remain readable at all UI scales.

## Crosshair Behavior tab

Use the approved Behavior reference and recommended defaults.

### Modes

- Static — no movement-based expansion.
- Movement — gentle expansion while moving/jumping and return when stable.
- Full Dynamic — movement plus weapon/status animations.

The default is Static, but event feedback below may still operate.

### Controls and defaults

- Movement Expansion: Off.
- Movement Intensity: 50%.
- Return Speed: Normal.
- Fire Pulse: On.
- Reload Indicator: On.
- Gun Pickup Feedback: On.
- Interactable Feedback: On.
- Animation Intensity: 50%.
- Animation Speed: Normal.
- Reduce Crosshair Motion: Off.

### Runtime rules

- Fire pulse is a short visual expansion/contraction or toy-splash pulse.
- Reload indicator uses normalized reload progress from 0.0 to 1.0. It must automatically adapt if reload duration becomes shorter or longer.
- Reload indicator may use a cyan arc and brief gold ready pulse.
- Pickup feedback activates only when the existing gameplay interaction/raycast confirms the gun is visible, reachable, and in valid range.
- Interactable feedback uses the existing valid interaction target. Never reveal objects or players through walls.
- Movement animation must never imply inaccurate spread if the weapon remains perfectly accurate.
- Reduced motion suppresses or minimizes nonessential crosshair animation.
- Behavior preview buttons: Fire, Reload, Pickup, Interact.

## Crosshair Feedback tab

This tab is approved by written specification even though no separate concept image was rendered. Match the Shape/Behavior editor layout and styling.

### Hit marker

- On/Off.
- Style.
- Color.
- Size.
- Thickness.
- Opacity.
- Display Duration.
- Hit Sound On/Off.
- Hit Sound Volume.

### Elimination marker

- On/Off.
- Style choices including Gold Star, Toy Splash, Skull + Star, and Expanding Ring where assets permit.
- Color.
- Size.
- Opacity.
- Display Duration.
- Elimination Sound On/Off.
- Elimination Sound Volume.

### Event rules

- Feedback appears only after a validated gameplay event.
- A confirmed gun elimination uses the elimination marker.
- Do not stack a normal hit marker beneath an elimination marker.
- Melee hit may use a short white impact marker.
- Melee elimination may use a stronger orange impact marker.
- Hazard elimination may use a purple environmental marker if the current event system identifies it.
- Object hits should use a subtle neutral response or no marker.
- Passing the crosshair over a hidden player never produces feedback.
- Sounds route through the real SFX bus and respect Master/SFX volume.

## Recommended default crosshair

- Style: Classic.
- Color: bright green.
- Size: 100%.
- Thickness: medium/3.
- Gap: medium-small/8.
- Opacity: 100%.
- Dark outline enabled.
- Static movement mode.
- Fire pulse enabled.
- Reload indicator enabled.
- Pickup/interactable feedback enabled.
- Gold splash-style elimination marker enabled.
- White melee hit marker enabled.
- Markers never stack.
- Hit/elimination sound enabled at moderate volume.

## Prompt for Claude Code

```text
Execute Phase 8 of the packet using the approved Accessibility, Crosshair Shape, and Crosshair Behavior references plus the written Feedback specification.

Implement functional accessibility settings and a complete procedural/scalable crosshair system.

Requirements:
- Apply UI scale, text size, colorblind filter, high-contrast UI, screen shake, camera bob, reduce flashing, and motion blur to real systems.
- Open Crosshair Customization as an internal settings subpage with Shape, Behavior, and Feedback tabs.
- Implement all approved styles and shape/appearance controls.
- Implement the recommended Behavior defaults and normalized reload progress.
- Connect pickup/interactable state only to valid existing interaction detection.
- Implement validated hit/elimination feedback without marker stacking or hidden-target revelation.
- Route marker sounds through SFX volume.
- Add lightweight live previews and test actions that never alter gameplay.
- Persist and migrate all settings.
- Ensure reduced-motion and high-contrast settings affect the editor as well as gameplay.
- Keep crosshair changes strictly visual.

Add focused tests for geometry/value conversion, settings round trip, reload normalization, event-to-marker selection, elimination precedence, reduced motion, and visibility gating. Validate at multiple resolutions and UI scales. Capture Accessibility, Shape, Behavior, and Feedback states. Stop.
```

## Acceptance gate

- Accessibility settings visibly affect real systems.
- Crosshair remains centered, crisp, and resolution independent.
- Reload visualization tracks any reload duration.
- Feedback only occurs from validated events.
- Crosshair never changes gameplay accuracy.

## STOP POINT 8

Stop for approval.

---

# Phase 9 — Local Pause and Online Match Menus

## Shared rules

- Use the approved compact cabinet references.
- Gameplay/HUD remains visible behind a dark veil and mild blur.
- Reuse the same Player Settings overlay built earlier.
- Returning from Player Settings returns to the correct match menu state.
- Input focus must not leak into gameplay while a menu is open.
- Destructive actions use two-click inline confirmation; no popup.
- First click changes the same button to `CONFIRM ...`.
- Confirmation cancels on Escape, clicking elsewhere, state change, or five-second timeout.

## Local Play pause menu

Use the approved Local pause reference.

- Title: `GAME PAUSED`.
- Status: `LOCAL MATCH PAUSED`.
- Display live match metadata: map, round, mode.
- Buttons:
  - Resume.
  - Player Settings.
  - Return to Lobby.
  - Return to Main Menu.
- No Restart Match button.
- Local gameplay, physics, timers, AI, and appropriate audio pause according to existing design.
- Menu and Settings remain processable while paused.
- Footer: gameplay is paused while this menu is open.

## Online host match menu

Use the approved Online host reference.

- Title: `MATCH MENU`, never `PAUSED`.
- Warning: `MATCH STILL IN PROGRESS`.
- Display map, round, and mode.
- Buttons:
  - Resume.
  - Player Settings.
  - Return to Lobby with `HOST ONLY` tag.
  - Leave Match.
- Returning to Lobby follows existing host/server behavior and safely informs clients.
- Online gameplay and network processing continue.

## Online non-host match menu

Use the approved non-host reference.

- Title: `MATCH MENU`.
- Warning: `MATCH STILL IN PROGRESS`.
- Buttons:
  - Resume.
  - Player Settings.
  - Leave Match.
- No Return to Lobby.
- No Host Only tag.
- No Return to Main Menu.
- Cabinet shortens naturally without an empty host-control gap.

## Escape behavior

- Opening menu captures UI input and releases gameplay mouse capture as appropriate.
- Escape on the root match menu resumes/closes it.
- Escape inside Player Settings returns to the match menu through Cancel semantics.
- Escape during inline confirmation cancels confirmation first.
- Online match continues visibly behind the menu.
- Local match remains paused while Settings is open from the pause menu.

## Prompt for Claude Code

```text
Execute Phase 9 of the packet using the approved local, online-host, and online-non-host menu references.

Implement a role-aware in-match menu using shared components and the correct local/online pause semantics.

Requirements:
- Local title/status and buttons match the approved local reference; no Restart Match.
- Online title is MATCH MENU with MATCH STILL IN PROGRESS; never pause online simulation/networking.
- Host sees Return to Lobby with Host Only; guest does not.
- Guest menu shortens without empty space.
- Reuse the same Player Settings overlay and restore the correct menu when it closes.
- Implement inline five-second destructive confirmation without popups.
- Implement Escape precedence: cancel confirmation, leave Settings, then resume/close.
- Prevent gameplay input leakage while the overlay is open.
- Preserve correct mouse capture, controller focus, audio, and scene-tree pause modes.

Validate local pause, online host, online guest, Settings round-trip in every state, Leave/Return confirmations, timeout cancellation, Escape behavior, disconnects, and scene cleanup. Capture all three menu states. Stop.
```

## Acceptance gate

- Local simulation pauses; online simulation does not.
- Host and guest actions differ correctly.
- Settings opens and returns without corrupting pause state.
- Destructive actions never trigger on the first click.

## STOP POINT 9

Stop for approval.

---

# Phase 10 — Integration, Regression, Performance, and Final Polish

## Integration requirements

- Main menu routes correctly to Local Play, Online Play, and Player Settings.
- Local and online lobbies route back correctly.
- Match start and return flows do not create duplicate scenes or managers.
- Profile name and selected character identity appear where supported.
- Map metadata is shared across local lobby, online lobby, and match menus.
- Settings load before menus/cameras/audio/crosshair depend on them.
- UI overlays never consume or leak input incorrectly.
- Async discovery/loading operations cancel when their view closes.
- Repeated opening/closing does not duplicate signals or retain nodes.

## Visual regression matrix

Capture and compare:

- Local Play base.
- Match Settings open.
- Bot Settings open.
- Online browser.
- Host Lobby form.
- Private code entry.
- Online lobby host.
- Online lobby guest not ready.
- Online lobby guest ready.
- Player Settings Audio.
- Player Settings Gameplay.
- Video.
- Controls keyboard/mouse.
- Controls gamepad.
- Accessibility.
- Crosshair Shape.
- Crosshair Behavior.
- Crosshair Feedback.
- Local pause.
- Online host match menu.
- Online guest match menu.

Test at minimum:

- 1280x720.
- 1920x1080.
- 2560x1440.
- One ultrawide resolution.
- UI scale minimum/default/maximum.

## Functional regression matrix

- Mouse-only navigation.
- Keyboard-only navigation.
- Gamepad-only navigation.
- Controller hot-plug while menus are open.
- Local single player.
- Local splitscreen where supported.
- Local bots at minimum and capacity.
- Online host + one guest.
- Ready reset after map change.
- Ready reset after rules change.
- Normal start when everyone is ready.
- Force Start two-click confirmation.
- Browser refresh/empty/error.
- Quick Join unavailable/success.
- Public/Friends/Private hosting.
- Valid/invalid/expired/private code.
- Apply/Cancel/Defaults for every settings tab.
- Restart persistence.
- Corrupt/old settings migration.
- Graphics setting compatibility.
- Rebinding conflict and recovery.
- Reload-duration changes with crosshair indicator.
- Hit versus elimination feedback precedence.
- Local pause versus online continuing match.
- Repeated scene transitions and disconnect cleanup.

## Performance and cleanup

- Profile idle menu and preview performance.
- Avoid per-frame allocations in crosshair and UI state code.
- Avoid polling where signals/events suffice.
- Confirm live previews free previous map nodes/resources.
- Confirm lobby rows and roster rows do not leak connections.
- Confirm Settings does not create multiple persistence/applier instances.
- Confirm no errors, warnings, orphan nodes, or leaked audio remain after repeated navigation.

## Prompt for Claude Code

```text
Execute Phase 10 of the packet.

Perform final integration, visual regression, functional regression, performance checks, and polish across every implemented menu state.

Requirements:
- Run the complete visual and functional matrices in this phase to the extent supported by the repository environment.
- Fix defects found within packet scope rather than merely listing them.
- Compare fresh screenshots against every approved concept and document intentional deviations.
- Verify responsive layout, UI scaling, focus order, mouse/controller input, persistence, networking authority, async cancellation, pause semantics, and scene cleanup.
- Remove temporary debug UI, mock rows, placeholder hard-coded lobby data, dead code, duplicate resources, and unused generated assets.
- Update project documentation with architecture, settings schema, networking limitations, and how to add maps/settings/crosshair styles.
- Do not claim tests that were not run.

At completion, report:
1. Outcome by menu system.
2. Exact files created and modified.
3. Validation commands and manual tests run.
4. Screenshot paths.
5. Remaining differences from concepts.
6. External/backend blockers.
7. Safe next steps.
```

## Final acceptance gate

- Every visible control is functional or clearly disabled with an honest reason.
- All menu states use the unified ONE GUN theme.
- Local/online authority and pause behavior are correct.
- Settings persist and Cancel restores pending previews.
- Crosshair customization is visual-only and event-safe.
- No fake networking data remains.
- No Toy Box branding remains.
- No unrelated user work was overwritten.

## STOP POINT 10

Final handoff.

---

# 6. Locked Behavior Summary

Use this section as the quick source of truth when concept art is ambiguous.

| Feature | Locked behavior |
| --- | --- |
| Local map preview | Live existing map; fade 0.6–0.8 seconds |
| Local roster | Expands to ten; no ready requirement |
| Base bot amount control | None |
| Bot amount | Stepper inside Bot Settings only |
| Bot difficulties | Easy, Medium, Hard, Expert per bot |
| Settings slide-outs | Connected to left cabinet; only one open |
| Match Settings | General, Combat, Spawns, Presets; preserve all code settings |
| Online roster | Up to ten; human ready X/check; bots auto-ready |
| Guest ready button | Red `READY UP`, then green `READY` |
| Separate not-ready text | Do not show |
| Force Start | First click -> red `CONFIRM`; second click starts |
| Force confirmation cancel | Elsewhere, Escape, state change, or five seconds |
| All ready | Host sees one-click `START MATCH` |
| Voice chat | Do not implement indicators yet; reserve layout space |
| Online browser | Real discovery only; no fake lobby data |
| Private access | Lobby code only; no password |
| Player Settings | Large overlay, not separate blank screen |
| Settings actions | Defaults, Cancel, Apply |
| Audio | Master, Music, SFX only; no Audio Preview panel |
| Graphics options | All must be integrated and functional |
| Player customization | Separate menu; not part of Player Settings |
| Crosshair default | Bright-green Classic, dark outline, static movement |
| Crosshair reload | Normalized progress; adapts to any reload duration |
| Marker stacking | Elimination marker replaces normal hit marker |
| Local Escape menu | Actually pauses; no Restart Match |
| Online Escape menu | Match continues; title `MATCH MENU` |
| Online host menu | Resume, Settings, Return to Lobby, Leave Match |
| Online guest menu | Resume, Settings, Leave Match only |
| Destructive menu actions | Two-click inline confirmation; no popup |

---

# 7. Prohibited Shortcuts

Claude Code must not:

- Use concept screenshots as clickable full-screen UI.
- Hard-code concept player names, roster members, lobby codes, or lobby rows.
- Show fake online lobbies as though they were real.
- Replace working networking with a local-only mock and call it complete.
- Rebuild the approved main menu unnecessarily.
- Remove existing match settings that are not shown in concept art.
- Leave graphics controls decorative or disconnected.
- Apply pending settings before Apply is selected.
- Let Cancel keep live-preview changes.
- Allow guests to invoke host-only actions.
- Pause an online match locally in a way that stops networking/game state.
- Show pickup/interactable crosshair feedback through walls.
- Change weapon accuracy through crosshair customization.
- Stack hit and elimination markers for one elimination.
- Add voice-chat indicators before voice chat exists.
- Add a local Restart Match button.
- Add Toy Box League, Toy Box Arena, or substitute Toy Box branding.
- Overwrite unrelated dirty-worktree changes.
- Claim a visual or functional match without running the project and comparing a fresh capture.

---

# 8. Final Master Prompt

Use this only after Claude Code has access to the repository, this packet, and all approved references.

```text
Implement ONE_GUN_MENU_SYSTEMS_ULTRA_PACKET_CLAUDE_CODE.md inside this existing Godot repository.

Start with Phase 0. Read repository instructions, inspect the existing systems and dirty git state, map the packet onto the real architecture, and report genuine blockers. Do not edit until the Phase 0 audit is complete.

After I approve the audit, execute phases in order. At each STOP POINT, implement the requested phase fully, run the available validation, capture current screenshots, report exact changed files and remaining differences, and wait for approval.

Treat the approved concept images as visual targets and the packet's locked behavior as functional authority. Reuse existing working systems, keep networking authoritative, keep settings transactional and persistent, make every displayed graphics option functional, and never fake discovery data. Do not rebuild the existing approved main menu unless an integration change is strictly required.
```

