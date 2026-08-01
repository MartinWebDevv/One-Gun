# One Gun Menu Systems — Implementation Guide

This document records the completed implementation behind
`ONE_GUN_MENU_SYSTEMS_ULTRA_PACKET_CLAUDE_CODE.md`. The packet remains the
visual/behavioral specification; this file is the extension guide.

## System ownership

- `OneGunUI` and `UI/components/` own tokens and reusable cabinet controls.
- `MapRegistry` owns map names, paths, thumbnails, descriptive metadata, and
  availability checks used by menus and pause metadata.
- `GameConfig` owns match rules. Lobby controls never shadow those rules.
- `PlayerPrefs` owns personal settings and their versioned disk envelope.
- `player_settings.gd` owns pending transaction UI and preview restoration.
- `AccessibilityManager` is the only global readability/motion adapter.
- `OneGunCrosshair` owns procedural crosshair presentation. It is local-only.
- `PauseManager` owns ESC precedence and local-vs-online pause semantics.
- `NetworkManager` owns lobby roster/readiness/privacy/kick/late-join authority.

## Settings transaction contract

Opening Player Settings takes a deep snapshot. Controls edit `_pending` only.
Audio, display, and accessibility options may preview through their real engine
adapters. Apply calls `PlayerPrefs.apply_transaction()`, which normalizes and
writes a temporary versioned file before replacing the active file. Cancel
reapplies the opening snapshot to every preview adapter and performs no save.

To add a setting:

1. Add a conservative default to `PlayerPrefs.DEFAULT_SETTINGS`.
2. Clamp or validate it in `PlayerPrefs._normalize()` and add migration logic
   only when an old value must be transformed rather than default-merged.
3. Add the real runtime consumer before exposing the control.
4. Add the control to the matching builder in `player_settings.gd` and include
   it in category defaults/preview routing.
5. Extend `tools/menu_systems_validation.gd` with normalization, Cancel, and
   behavior coverage.

## Adding a map

Add one dictionary to `MapRegistry.MAPS` with `name`, `scene_path`,
`thumbnail_path`, description, size, recommended players, playstyle, hazards,
and placeholder tint. Keep authored spawn/item/melee/powerup markers in the map.
The lobby and pause metadata consume the registry automatically. Validate the
scene exists and capture its thumbnail before shipping.

## Extending the crosshair

Crosshair styles are procedural branches in
`UI/crosshair_renderer.gd._draw_shape()`. Add the style identifier to the
PlayerPrefs default/normalizer, the Shape dropdown, and
`shape_segment_count()`'s deterministic geometry test. New dynamic behavior may
read local presentation state, but must not write weapon, aim, spread, hitbox,
or RPC state. Reload visuals must use `gun.get_reload_progress()`. World-object
feedback must pass `character_body_3d.get_valid_crosshair_interactable()` so a
registered object hidden by a wall cannot light the reticle.

Combat feedback enters through `GameEvents.combat_feedback` only after the
local authoritative path or server confirms it. Use `<source>_hit` and
`<source>_elimination`; elimination replaces a current hit and never stacks.

## Online limitations and authority

Online settings and crosshair choices are local presentation only. The online
match menu does not pause simulation or replication. Only the host can return
everyone to the lobby; a guest sees only Resume, Player Settings, and Leave
Match. Existing online limitations remain: no peer team assignment, no public
rendezvous service beyond Tailscale discovery/direct address, and real
two-machine Tailscale playtesting is still required after network changes.

## Verification

`tools/menu_systems_validation.gd` covers resource loading, all settings and
crosshair pages, Cancel isolation, preference normalization, geometry/reload
conversion, elimination precedence, inline confirmation, local pause semantics,
and host/guest action authority. `tools/accessibility_render_validation.tscn`
proves that real camera transform deltas drive the rendered motion-blur shader.
`tools/lobby_network_validation.gd` covers the two-peer
readiness/privacy/kick/late-config behavior. Visual captures live under
`docs/screenshots/menu_redesign/` and should be refreshed at representative
16:9, ultrawide, and UI-scale extremes when layout changes.
