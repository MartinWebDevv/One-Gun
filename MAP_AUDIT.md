# One Gun Map Audit

## Summary

The repository contains six map-like scenes:

- Three current selectable gameplay maps.
- Two legacy/prototype gameplay maps.
- One menu-background map.

The current maps are not simple grayboxes. Each has an authored theme, cover network, environmental presentation, gameplay markers, local gameplay scaffolding, and online compatibility through runtime conversion. Their biggest shared audit concern is navigation: all three contain a configured `NavigationMesh` subresource but no serialized vertex/polygon data in the `.tscn`, despite project history claiming successful baked polygon counts.

No map was changed during this audit.

## Map inventory

| Scene | Status | Approx. nodes | Player markers | Gun markers | Item markers | Powerup markers | Authored melee | Gun instances |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| `maps/test/ForestMap.tscn` | Selectable | 1,010 | 8 | 1 | 5 | 2 | 8 | 1 |
| `maps/test/WesternV2Map.tscn` | Selectable | 448 | 8 | 1 | 8 | 4 | 6 | 1 |
| `maps/test/CityMap.tscn` | Selectable | 554 | 8 | 1 | 5 | 5 | 7 | 1 |
| `node_3d.tscn` | Legacy prototype | 221 | 8 | 0 | 0 | 0 | 4 | 1 |
| `maps/test/NukeTownMap.tscn` | Legacy prototype | 148 | 0 current / 8 legacy bot markers | 0 | 0 | 0 | 4 | 1 |
| `maps/test/title_bg_map.tscn` | Menu only | 43 | 0 | 0 | 0 | 0 | 0 | 0 |

The current lobby list is defined in `game_setup.gd`:

- Whispering Woods -> ForestMap.
- Western Town -> WesternV2Map.
- Maple & 3rd -> CityMap.

Coliseum and Explosion Town entries remain only as commented/legacy intent.

## Shared current-map architecture

All three selectable maps:

- Use a 2x root transform.
- Include a `WorldEnvironment`, directional light, static collision, and `NavigationRegion3D`.
- Include eight `spawn_point` markers.
- Include exactly one gun scene.
- Include a `gun_spawn_point` marker for random mode.
- Preserve multiple authored melee instances.
- Include item and powerup marker groups.
- Include baked local player/splitscreen/HUD structure.
- Include `RoundManager`.
- Are converted at runtime for online play without editing the map scene.

The 2x root scale is an established compatibility constraint. Online player and bot code compensates for inherited map scale. Removing or changing it casually would affect character size, collision, spawn positions, physics, network presentation, and map balance.

## Navigation audit

### Current selectable maps

Scene text contains only NavigationMesh configuration:

| Map | Agent radius | Agent height | Max climb | Max slope | Serialized polygons found |
|---|---:|---:|---:|---:|---:|
| Forest | 0.60 | 2.5 | 0.7 | 48° | 0 |
| Western V2 | 0.45 | 2.5 | 0.7 | 48° | 0 |
| City | 0.45 | 2.5 | 0.8 | 48° | 0 |

No external navigation resource is referenced. By contrast, `node_3d.tscn`, NukeTownMap, and title_bg_map each visibly serialize 209 navigation polygons.

Project history claims 569 Forest polygons and 556 Western V2 polygons, with successful City route checks. That history likely describes a prior generated/baked state rather than the current serialized files. Existing online smoke tests do not prove obstacle-aware navigation because bot checks can pass with direct movement or limited test paths.

Required future validation: open each selectable map in Godot, inspect `NavigationRegion3D.navigation_mesh.get_polygon_count()`, visualize navigation, and run bots through all intended routes. This audit does not rebake or save any map.

## Whispering Woods

Scene: `maps/test/ForestMap.tscn`  
Lobby name: Whispering Woods  
Status: current/selectable, visually developed, gameplay-complete subject to navigation verification.

### Theme and presentation

- Twilight fantasy forest.
- Oval/perimeter-contained arena.
- Central pond crossed by an arched bridge.
- Dense original low-poly trees, shrubs, grass, ferns, flowers, mushrooms, logs, stumps, stones, and boulders.
- Moonlight, glow, distance fog, and volumetric fog.
- Glowshroom point lights.
- Wind-sway foliage shader.
- Falling leaves/firefly-style particles.
- Ambient birds and shooting stars.
- Pond splash response.
- Dedicated forest music and bird ambience.

Lighting values emphasize cool twilight: ambient energy 1.5, glow enabled, standard fog density 0.008, volumetric fog density 0.018, and moon/cool emissive accents.

### Gameplay flow

- The bridge/pond center is the primary gun contest and a strong opening focal point.
- Eight perimeter player spawns create inward movement toward the central objective.
- Forest growth and boulders provide frequent sightline breaks.
- The bridge creates a predictable crossing and elevated commitment point.
- Pond terrain changes visual/readability context and creates a recognizable center landmark.
- Outer groves support flanking and escape paths.

### Cover

- Trees and boulders provide hard or semi-hard cover depending on collider setup.
- Logs, standing stones, and terrain details provide low cover/route shaping.
- Dense foliage adds visual concealment, though visual concealment and physical collision are not always equivalent.
- The bridge exposes players crossing the center and creates contestable choke behavior.

### Gameplay content

- 8 current player spawn markers.
- 1 gun and 1 gun marker.
- 8 authored melee placements.
- 5 item markers.
- 2 powerup markers.
- Full local player/HUD/splitscreen scaffolding.
- Online conversion preserves all marker and melee placements.

### Completion and risks

Strengths:

- Most cohesive atmosphere package in the project.
- Original generated asset set is small, deterministic, and well within budget.
- Strong central landmark and immediately readable objective route.
- Map-specific audio is integrated.

Risks/placeholders:

- Very high node density (about 1,010 nodes) makes manual editing and load/render profiling important.
- Current navigation polygons are not serialized.
- Visual foliage density may obscure players differently at different graphics settings/camera angles.
- Forest full online smoke failed Magnet Hands once and passed on repeat, indicating timing sensitivity.

Future recommendation: preserve the authored scene and markers; validate nav coverage, collision/readability, and the intermittent online item test before content changes.

## Western Town / Western V2

Scene: `maps/test/WesternV2Map.tscn`  
Lobby name: Western Town  
Status: current/selectable, visually and structurally developed, with a repeatable online smoke failure requiring investigation.

### Theme and presentation

- Sunset Western main street/showdown town.
- Long central street with the gun near the high-noon focal point.
- False-front storefronts, church, interactive saloon, clock tower, water tower, windmill, hitching posts, troughs, hay, crates, barrels, cacti, mesas, and desert backdrop.
- Warm sunset sun, fog, volumetric haze, glow, porch lanterns, dust, tumbleweeds, and vulture/bird presentation.
- Windmill with separately animated blades.

Lighting is warm and directional: ambient energy 1.25, glow enabled, standard fog density 0.006, volumetric fog density 0.012, and a shadowed sunset directional light.

### Gameplay flow

- The long street establishes a dangerous central gun lane.
- Storefronts and side/rear lanes allow flanking around that lane.
- The church end and saloon/clocktower landmarks orient players quickly.
- Elevated routes deliberately create two-level fights rather than a flat arena.
- The central catwalk crosses above the primary gun contest.

### Elevation and cover

- Walkable rooftops on multiple buildings.
- Rear plank walkways.
- Railed cross-street catwalk with mid-span cover.
- Water-tower platform as the highest perch.
- Rock shelf/plateau connection.
- Parapets, rails, porches, wagons, barrels, crates, and buildings provide layered cover.
- Stairs are intended to be bot-navigable and human step-up compatible.

### Gameplay content

- 8 current player spawn markers.
- 1 gun and 1 gun marker.
- 6 authored melee placements.
- 8 item markers.
- 4 powerup markers.
- Full local player/HUD/splitscreen scaffolding.
- Online conversion preserves authored placements.

### Completion and risks

Strengths:

- Strongest vertical combat layout.
- Clear central objective lane plus multiple flanks.
- Interactive/reused saloon adds identity.
- New low-poly generated assets coexist with optimized legacy Western landmarks.

Risks/placeholders:

- Current navigation polygons are not serialized, despite prior route-validation notes.
- Saloon/legacy Tripo art has a history of extreme asset density; optimized files are now reasonable, but originals are external.
- No dedicated Western level music/ambience is configured by design/history.
- Full online match smoke failed twice at the same Magnet Hands authoritative-movement check.

Future recommendation: do not rebuild or remove authored markers. First validate navigation at every elevation tier and reproduce the Magnet Hands failure in an interactive two-peer test.

## Maple & 3rd / CityMap

Scene: `maps/test/CityMap.tscn`  
Lobby name: Maple & 3rd  
Status: current/selectable, highly scripted and user-tuned; builder is retired.

### Theme and presentation

- Midday suburban New York-inspired block.
- Cross streets, ring road, markings, crosswalks, curbs, sidewalks, and a park corner.
- Enterable corner store and diner.
- Enterable brownstone with interior stairs and accessible roof.
- Traffic lights, moving cars, hydrant, manhole steam, paper litter, clouds, pigeons, streetlights, mailbox, shelter, hoop, dumpsters, and urban props.
- Bright daylight, low fog, moderate glow.

Lighting is the clearest/brightest of the three maps: ambient energy 1.1, glow intensity 0.25, fog density 0.0012, and a shadowed sun at energy 1.3.

### Gameplay flow

- Cross intersection is the primary orientation anchor and gun contest.
- Ring-road/sidewalk loops create predictable circulation routes.
- Enterable commercial buildings create interior ambush and escape spaces.
- Brownstone roof adds a limited vertical position.
- Park corner provides a softer, more open contrast to hard street/building geometry.
- Moving traffic adds nonlethal environmental displacement and timing pressure.

### Cover

- Building corners, interiors, counters/furniture, cars, dumpsters, shelters, mailboxes, and street props break sightlines.
- Park assets create lower organic cover.
- Rooftops and building entries add vertical/indoor transitions.
- Streets and intersection create longer exposed lanes.

### Gameplay content

- 8 current player spawn markers.
- 1 gun and 1 gun marker.
- 7 authored melee placements.
- 5 item markers.
- 5 powerup markers.
- Full local player/HUD/splitscreen scaffolding.
- Host-authoritative traffic/contact effect behavior coexists with player combat.

### Completion and risks

Strengths:

- Richest environmental scripting and interaction set.
- Strong mixture of open street, interior, rooftop, and park spaces.
- Thirty original generated City assets are very small.
- City online-bot smoke passed on both peers during this audit.

Risks/placeholders:

- Current navigation polygons are not serialized.
- Prior notes say the brownstone roof route is climbable by humans but too steep for bot navigation beyond the interior/landing.
- Traffic and many environmental scripts increase the regression surface.
- `tools/build_city_map.gd` is explicitly retired; rerunning it would overwrite user-tuned work.

Future recommendation: treat the scene as hand-authored source of truth, validate bots through interiors/streets, and use surgical edits only.

## `node_3d.tscn` legacy prototype

Status: not selectable; former Coliseum/prototype gameplay map.

### Theme and structure

- CSG-heavy graybox/prototype arena.
- Approximately 96 CSGBox nodes.
- Basic environment, directional light, static layout, and serialized navigation data.
- Full older local players, HUD, splitscreen, round manager, gun, and melee scaffolding.

### Gameplay content

- 8 current `spawn_point` markers.
- 1 gun.
- 4 melee instances.
- No current gun/item/powerup marker groups found.
- NavigationMesh visibly serializes 209 polygons.

### Completion and role

This is useful as a simple test arena and smoke-test default but does not conform to the current marker-driven item/powerup content contract. Its CSG construction and generic presentation identify it as prototype content rather than a current map.

Future recommendation: retain as a test/legacy reference until test coverage no longer depends on it; do not present it as current content without a compatibility review.

## NukeTownMap legacy prototype

Scene: `maps/test/NukeTownMap.tscn`  
Status: not selectable; former Explosion Town/NukeTown-style prototype.

### Theme and structure

- CSG suburban/industrial prototype layout.
- Approximately 33 CSGBox nodes.
- Basic environment and light.
- Full older local gameplay scaffolding.
- Serialized navigation data with 209 polygons.

### Gameplay content and incompatibility

- 1 gun.
- 4 melee instances.
- 8 markers use the legacy group `bot_spawn_point`, not the current `spawn_point` group.
- No current gun/item/powerup marker groups.

Current `RoundManager` spawn assignment searches `spawn_point`, so this map is not compatible with current match spawning without an explicit migration. It should remain out of the selectable lobby.

Future recommendation: keep documented as legacy. If ever revived, first audit marker schema, current HUD/scaffolding, item/powerup support, collision, and online conversion rather than making isolated visual edits.

## Title background map

Scene: `maps/test/title_bg_map.tscn`  
Status: menu-only.

### Purpose

- Stripped CSG environment derived from the legacy NukeTown-style map.
- Rendered through the main menu's SubViewport.
- Contains environment/light/navigation remnants but no gameplay actors, markers, weapons, items, or HUD.

### Completion and risks

- Functional as an animated/live background.
- Navigation data is unnecessary for its current menu-only role, but this audit does not remove it.
- Visual identity reads as reused prototype space rather than a bespoke title composition.
- The lobby gameplay preview is separate and should not be confused with this title scene.

Future recommendation: preserve current functionality until a deliberate menu-art phase; do not disable the live preview/background as part of unrelated optimization.

## Map wins to preserve

- Each selectable map has a distinct landmark, palette, combat rhythm, and sightline structure.
- All current maps use eight spawn markers and support up to eight actors.
- Authored melee, item, powerup, and gun markers are preserved online.
- Online conversion reuses maps without maintaining separate network map copies.
- Forest/Western/City generated assets are compact and reproducible.
- City is correctly marked as hand-tuned and protected from full rebuilds.
- Current maps support local HUD/splitscreen and online runtime stripping from the same source scene.

## Cross-map validation checklist for a future phase

This list records recommended tests only:

1. Confirm nonzero navigation polygon counts and visualize navigable surfaces.
2. Run each bot difficulty between every spawn, gun location, marker cluster, and elevated route.
3. Verify all eight player spawns are unobstructed at map scale 2.
4. Confirm all authored melee instances activate and reroll independently.
5. Confirm every item/powerup marker survives round resets locally and online.
6. Validate gun center/random modes.
7. Test camera clipping and player readability at dense cover.
8. Run local solo, local splitscreen, online human-only, and online bots on each selectable map.
9. Reproduce Magnet Hands specifically on Western V2 and Forest.
10. Preserve the gameplay preview and all authored marker transforms during any future scene work.
