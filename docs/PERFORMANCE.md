# One Gun — Performance and Lower-Spec Development Rules

> This document is a permanent engineering requirement and the source of truth for performance decisions. It applies to all future feature work, refactors, reviews, maps, assets, and releases. Read it with the system-specific documents before making a non-trivial change.

## 1. Non-negotiable goals

- Keep Godot **Forward+** as the primary renderer. Do not switch the project to Compatibility unless the user explicitly approves that direction.
- Preserve One Gun's toy-like visual identity, readable characters and silhouettes, combat feedback, important nearby lighting, and atmosphere.
- Make the complete gameplay experience run well on modest desktop PCs and laptops. Visual quality may scale; mechanics, input response, hit detection, physics correctness, and network correctness may not.
- Treat meaningful performance regressions, frame-pacing regressions, repeated-scene memory growth, and avoidable RAM/VRAM spikes as bugs.
- Prefer scalable settings and cheaper distance/inactive behavior over deleting visual features globally.
- Do not rely on a powerful development PC, abundant VRAM/RAM/CPU cores, or fast storage to hide inefficient architecture.

The standing development question is:

> How will this behave on a significantly weaker PC than the development machine?

Apply it especially to maps, shaders/materials, lighting/shadows, post-processing, particles/VFX, loading/transitions, multiplayer spawning, characters, physics/collision, UI, audio, hot scripts, networked objects, projectiles, and destructible or interactive objects.

## 2. Target

The lower-spec target is approximately 60 FPS at 1920×1080 using the Low preset during normal gameplay, with stable frame pacing and no major spawn, shot, death, ability, or map-change stutters.

Design as though a player may have:

- an older dedicated GPU or modern-Vulkan integrated GPU;
- limited VRAM;
- a laptop CPU;
- 8–16 GB system RAM;
- slower storage.

Low must still look recognizably like One Gun. Spend visual budget on players, weapons, readable combat effects, important nearby environment, and gameplay lighting. Save it on distant decoration, hidden geometry, unnecessary shadows, excessive particles/transparency, and oversized textures.

## 3. Current quality architecture

PlayerPrefs owns local graphics settings. PlayerSettingsApplier applies viewport settings, and the event-driven GraphicsQualityManager applies scene-resource scaling when nodes enter the tree or a preset changes. There is no quality scan in _process().

| Preset | 3D scale | AA | Positional shadow atlas | Effects behavior |
|---|---:|---|---:|---|
| Low | 75% | Off | 1024 | Disables authored SSAO, SSIL, SSR, volumetric fog, glow, and camera DOF; disables local-light shadows; caps directional-shadow distance at 35 m; renders larger particle systems at 45% density |
| Medium | 90% | FXAA | 2048 | Disables authored SSIL/SSR; caps directional-shadow distance at 60 m; renders larger particle systems at 70% density |
| High | 100% | FXAA | 4096 | Restores authored environments, lights, particles, and camera attributes |
| Ultra | 100% | MSAA 4× | 8192 | Restores authored effects with the largest shadow atlas |

Tiny particle bursts of four particles or fewer retain their full count so gameplay cues cannot disappear. Authored High/Ultra values are cached per instance, so live preset changes are reversible and never mutate a shared map environment resource.

Render scale, AA, and shadow-atlas settings apply to the root viewport and every SubViewport, including splitscreen and menu/showcase viewports. UI remains at native resolution.

Low uses the purpose-built lightweight maps/test/title_bg_map.tscn for the live main-menu world instead of cycling complete playable maps. The lobby keeps its authored live 3D map preview on every quality tier; its SubViewport inherits render-scale and effects reductions, and map swaps release the previous preview scene before instantiating the next one to avoid a two-map memory peak.

When adding an expensive visual feature, integrate it with this architecture or explain why it must remain invariant. Do not hardcode maximum-cost effects for every machine.

## 4. Completion checklist for significant features

Before calling a significant feature complete, inspect whether it creates unnecessary:

- per-frame _process() / _physics_process() work;
- tree/group searches, node lookups, string work, arrays/dictionaries, allocations, or resource lookups in hot paths;
- physics queries, raycasts, active collision objects, or complex collision meshes;
- instantiation, retained nodes/resources, or repeated loads;
- draw calls, unique materials, shader variants, transparency/overdraw, texture/mesh memory;
- particles, decals, dynamic lights, or shadow-casting lights;
- RPC traffic, continuously synchronized cosmetic state, or duplicated network objects.

Use events/signals for event-shaped work. Cache safe hot-path references. Disable processing/rendering/physics when an object is inactive and provides no value. Let physics objects sleep where appropriate. Maintain clear code; do not micro-optimize inexpensive code or rewrite a working system for a theoretical gain.

## 5. Maps and visibility

Maps are a priority optimization area.

- Use reasonable geometry density and simple collision geometry. Never use an extremely dense visual mesh as collision when a simpler shape is equivalent.
- Add imported mesh LODs, visibility ranges/HLOD, and appropriate occlusion culling when the measured map composition benefits.
- Share meshes/materials for repeated props. Investigate MultiMesh for large non-interactive repeated decoration.
- Give distant decorative objects a justified visibility range when they cannot be noticed and have no gameplay role.
- Audit walls, rooms, corridors, buildings, and hidden geometry for occlusion behavior; being behind a wall does not automatically make an object cheap.
- Audit visible light counts, overlap, ranges, shadow distances, and shadow-casting lights. Decorative lighting should normally use emission or non-shadowed lights. Reserve realtime shadows for visible benefit.
- Stress-test maximum supported actors, all players visible, concurrent fire/melee/effects, repeated deaths, and map-specific worst cases.

Do not make broad scene rewrites, geometry merges, or visibility changes without profiling and visual/collision validation.

## 6. Textures, meshes, materials, and shaders

Use the smallest source that preserves the intended view:

- around 512 px for minor/small props where sufficient;
- around 1024 px for normal environment assets;
- 2048 px for justified important/large assets;
- avoid 4K unless the visible benefit is strong.

Keep the existing mesh budgets in AGENTS.md: props should generally remain at or below about 15k triangles with 1024² textures; buildings/landmarks at or below about 100k triangles with 2048² textures. Any new GLB over roughly 10 MB must be inspected and normally optimized before use.

Use appropriate GPU texture compression/import settings and avoid duplicate textures/resources. Reuse materials. Prefer shared parameters, instance parameters, textures, and colors to hundreds of unique materials.

Before accepting a custom shader, inspect full-screen coverage, loops, texture samples, transparency/overdraw, and shader variants. Use the least expensive implementation that retains the look.

## 7. Particles, VFX, and transparency

- Particle density must scale through the quality system.
- Stop and free one-shot systems after completion. Do not leave invisible particle systems processing.
- Keep smoke, glass, holograms, trails, and layered transparent effects effective without excessive overlapping surfaces.
- Preserve gameplay feedback at every preset. Prefer fewer well-shaped particles to high counts with little visible gain.
- Cosmetic effects do not need authoritative network synchronization when peers can reproduce them locally from a gameplay event.

## 8. Physics and scripts

Movement responsiveness and melee/hit correctness outrank optimization.

Still audit collision layers/masks, overlap areas, raycasts, queries, dense collision, always-active bodies, nested loops, per-frame group/tree searches, repeated get_node() calls, and transient allocations. Use the existing interactable registration pattern instead of player polling.

Do not introduce pooling until measurement shows repeated allocation/cleanup is a meaningful bottleneck. Temporary bullets, impacts, decals, particles, sounds, UI, dropped weapons, ragdolls, traps, and network entities must have explicit, correct lifetimes.

## 9. Loading, scene transitions, and memory

Whenever map selection/loading changes, verify:

- the previous map is freed and no stale manager/resource reference retains it;
- full maps do not coexist unnecessarily;
- threaded requests do not overlap or continue after cancellation;
- repeated selection cannot duplicate nodes or grow memory;
- previews use lightweight images/scenes rather than full playable maps where practical;
- repeated enter/leave, lobby/playpen/match, and menu transitions do not accumulate RAM/VRAM;
- spawn/first-use resources do not create avoidable gameplay stutters.

Map switching must not create large temporary RAM/VRAM spikes. A major transition architecture change requires evidence and discussion; small lifetime fixes can be made immediately.

The tracked build/.gdignore prevents generated build trees from being imported as a second copy of the project. Client/server export presets also exclude build staging, art sources, and developer tools.

## 10. Multiplayer

Local and Online must retain identical gameplay behavior.

- Do not synchronize static map data, local UI, deterministic cosmetic effects, or other presentation-only state without need.
- Do not spam RPCs each frame when state replication/interpolation or an event contract is appropriate.
- Keep gameplay-authoritative data reliable, actor-addressed, and round/epoch safe.
- Only the authority should run authoritative AI/physics where the architecture specifies it; puppets should not duplicate that work.
- Performance changes must not weaken validation, authority, hit correctness, or scene-ready/teardown ordering.

## 11. Validation and profiling

Run the available headless Godot validation after edits. Gameplay/feel/render changes still require a rendered editor playtest.

At useful checkpoints, measure and compare:

- FPS and frame pacing;
- CPU/GPU frame time;
- script and physics time;
- draw calls and visible objects;
- node/object counts;
- memory and VRAM/resource use;
- shader compilation and allocation spikes.

Profile actual bottlenecks when possible. Test maximum players, simultaneous attacks/effects, smoke, repeated respawns, repeated map switches, network enter/leave, menus, and rapid settings changes—not only an empty arena.

The weaker laptop is a real release target. At good checkpoints/releases, explicitly recommend a laptop build test. Use its profiler/crash evidence to find the specific weakness instead of globally lowering quality.

**Verified checkpoint — 2026-08-22:** the current build received a successful user-reported gameplay check on the weaker laptop using the Low preset. This checks off the current compatibility smoke test; it is not a measured 60 FPS/frame-time profile. Retest after the Winners Circle cinematic and after other substantial rendering, map, character-count or transition changes.

## 12. Decision rule for discovered problems

A small, safe, clearly beneficial fix may be included in current work.

Report first when the fix changes architecture, substantially changes visuals/gameplay, carries significant risk, or requires a major refactor. Report:

1. what is expensive;
2. why;
3. which hardware is affected;
4. the recommended change;
5. visual/gameplay tradeoffs.

Do not stop normal feature development for speculative optimization. Performance is a continuous requirement, not a separate final phase.

## 13. Current audit watch list

These are profiling targets, not authorization for blind rewrites:

- ForestMap.tscn is the largest authored gameplay scene in the current static audit (about 1,025 scene nodes, 269 mesh/CSG nodes, and nine GPU particle systems). Profile its rendered draw calls, visibility, particle cost, and memory before changing its art structure.
- models/new guy one gun model orange running.glb is a used legacy bot asset around 24.7 MB, above the normal incoming-asset budget. Its animation/appearance must be backed up and validated before reprocessing.
- Long WAV source files are imported with Godot compression mode 2 and loaded on demand; source size alone is not evidence of equivalent runtime RAM. Profile decoded/imported memory before converting formats.
- Main-menu High/Ultra still deliberately preloads the next live map while displaying the current one. Measure peak RAM/VRAM on the laptop before redesigning that approved visual presentation.
- Synchronous gameplay scene changes warrant repeated-switch memory and stutter profiling before a transition-system refactor.

