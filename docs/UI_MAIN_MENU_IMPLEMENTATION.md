# One Gun Main Menu Implementation

## Scope

This pass changes the presentation and interaction architecture of the main menu only. It does not change gameplay, maps, player controllers, combat, lobby logic, or network protocol behavior.

Preflight was recorded on branch `main` at commit `7883fd1cbc69429ad17f88edf8b8c398c5b506c6`. The working tree already contained unrelated gameplay and multiplayer changes; those files were preserved.

## Visual Direction

The implemented hierarchy follows the requested mix of premium toy packaging, first-party menu clarity, and restrained 1990s arcade energy:

- The left package panel contains the `ONE GUN` brand, `TOY BOX LEAGUE` label, four primary actions, connection state, and build identifier.
- The main display case presents the existing cat mascot on a presentation-only pedestal with a safe fallback label if the visual cannot load.
- The supporting card carries the identity line, build state, and Tailscale/named-lobby context.
- The existing live map background remains active beneath a stronger readability gradient and vignette.

The color roles continue to come from `ThemeManager`: deep navy surfaces, warm gold primary accents, cyan focus/online accents, lime ready state, coral danger state, bright text, and muted secondary text. Menu-local style factories centralize panel, button, input, and focus treatments.

## Navigation and Preserved Behavior

The four primary actions are:

1. `LOCAL PLAY`
   - Opens a presentation-only choice panel.
   - `SOLO + BOTS` keeps the old single-player route: default lobby rules are restored when appropriate, `GameConfig.split_screen_enabled` is set to `false`, and `game_setup.tscn` loads.
   - `2 PLAYER SPLITSCREEN` keeps the old local multiplayer route: default lobby rules are restored when appropriate, `GameConfig.split_screen_enabled` is set to `true`, and `game_setup.tscn` loads.
2. `ONLINE PLAY`
   - Opens the redesigned Tailscale panel.
   - Host still calls `NetworkManager.host_game(NetworkManager.DEFAULT_PORT, requested_name)`.
   - Join still accepts a named lobby or the existing direct `100.x`/`127.x` fallback and calls the same discovery/join methods.
   - The same success/failure signals and transition to `game_setup.tscn` remain in place.
   - Cancel preserves the prior network disconnect behavior.
3. `PLAYER SETTINGS`
   - Still loads `player_settings.tscn`.
4. `QUIT`
   - Still exits the scene tree.

No lobby, player-name, host/join, scene-transition, or network-protocol logic was redesigned.

## Online Panel

The online panel retains all functional information while making it feel part of the menu:

- Tailscale detected/not-detected state
- direct-address fallback display
- host lobby-name field
- join lobby-name/direct-IP field
- host and join actions
- inline searching, connecting, and error text
- cancel action

Keyboard fields retain normal text editing. Buttons and fields use visible cyan focus rings for keyboard/controller navigation.

## Mascot Safety

The display uses `res://models/playerAnimations/Dance.glb` as a visual-only instance in its own `SubViewport` and `World3D`.

- No rig, animation library, imported mesh, material, texture, or source asset was modified.
- No gameplay player scene is instantiated.
- The pedestal, floor, camera, and lights exist only inside the menu display viewport.
- If the model cannot be loaded, the menu shows a stable `MASCOT DISPLAY UNAVAILABLE` fallback instead of failing.

## Motion and Input

- Panel entrances use a 0.24 second transition.
- Hover/focus feedback uses 0.13 seconds.
- Press feedback uses 0.08 seconds.
- Primary buttons restore the removed stagger with a restrained 0.055 second interval.
- Animation uses scale and opacity only; it does not move layout containers or alter navigation order.
- `ui_cancel` closes local/online overlays and returns focus to the opening action.
- Primary navigation wraps vertically, and online host/join rows define explicit horizontal focus neighbors.

There is no player-facing reduced-motion setting yet. `_reduced_motion_enabled()` is an intentionally dormant hook: if `PlayerPrefs` later adds a `reduced_motion` key, background pan, mascot idle playback, and UI tweens will respect it without another menu rewrite.

## Responsive Behavior

The menu uses anchored layers, margin containers, and expanding box containers rather than fixed screen coordinates.

- At 1120 pixels wide and above, the full brand/navigation, mascot display, and supporting-info layout is shown.
- Below 1120 pixels, the mascot/supporting column is hidden to prevent clipping. Connection, build, and identity information remain in the navigation footer.
- Compact-height layouts reduce title, button, and support-panel sizing.
- Online and local overlays clamp their minimum size to the available viewport.

Rendered verification was performed at:

- 1600 x 900
- 1920 x 1080
- 1280 x 720
- 900 x 720 narrow-window layout

## Version and Theme Handling

- `application/config/version` in `project.godot` is now the menu's single displayed version source (`0.0.1`).
- Both visible build labels read that setting; the old hard-coded `v0.9` label is removed.
- The export preset was not rewritten and already uses the same `0.0.1` value.
- `ThemeManager` still builds the in-memory theme at launch, but writes `one_gun_theme.tres` only while running in the editor. Packaged builds no longer attempt to write into `res://`.

## Files Changed for This Pass

- `main_menu.tscn` - explicit background, interface, and modal layers
- `main_menu.gd` - responsive presentation, mascot display, local/online panels, focus, motion, and preserved callbacks
- `project.godot` - central displayed version setting
- `theme_manager.gd` - editor-only generated-theme save guard
- `docs/UI_MAIN_MENU_IMPLEMENTATION.md` - this handoff
- `docs/screenshots/main_menu/` - requested captures plus preflight and QA captures

## Screenshots

- `before_1600x900.png` - pre-change reference
- `main.png` - final main state at 1600 x 900
- `online_host.png` - host field focus state
- `online_join.png` - join field focus state
- `controller_focus.png` - primary controller/keyboard focus state
- `main_1280x720.png` - required 1280 x 720 layout
- `qa_1920x1080.png` - wide-layout QA
- `qa_narrow_900x720.png` - narrow-layout QA
- `qa_local_panel.png` - preserved local-mode routes

## Verification and Remaining Manual Check

Godot 4.6.3 was run headlessly against the project after the changes with no script or scene errors. A temporary menu-flow smoke check also passed the local overlay, online overlay/cancel, solo route, splitscreen route, settings route, and central version value. Rendered captures were produced at every resolution above with no menu-script, invalid-resource, or viewport warnings.

The host/join callbacks were preserved and inspected, but a real two-machine Tailscale session still requires the normal partner test. This pass intentionally stops before lobby, HUD, customization, gameplay, or network-system work.
