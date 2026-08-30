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
Profile, Prize Counter, Locker, and Progression reuse static 1600×900 backdrop
textures plus a quality-scaled lightweight mote layer; only Locker keeps its one
existing character-preview SubViewport. Official reward activity sampling runs
once per second on the host and adds no movement/combat RPC or per-frame database work.

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

The tracked build/.gdignore prevents generated build trees from being imported as a second copy of the project. Client/server export presets also exclude build staging, art sources, developer tools, and the backend-only `services/` coordinator (including its Node dependencies).

The startup cinematic requests its configured handoff scene on Godot's background loader after the six actors are prepared. The main menu no longer synchronously loads its first full live-map preview before drawing the cabinet: it draws the UI first, requests that preview on the resource thread, and fades the completed map in behind the interface. Keep this non-blocking first-frame contract when changing the title background.

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

**Victory-move checkpoint — 2026-08-24:** all 14 optional FBX clips remain below
the 10 MB per-asset intake threshold and are not part of the eager gameplay animation
set. Only the equipped or actively previewed move is retargeted and cached for a
given character model. Retest repeated Locker previews and ceremonies on Low.
The Prize Counter reuses one shadow-free 512×256 move viewport and does not create
a character until a locally mapped Victory item is selected. The viewport and its
animation player stop when inspecting ordinary items or leaving the page. Keep this
single-preview/lazy-load behavior when adding future poses or move types.

**Controller/social/gameplay checkpoint — 2026-08-26:** the complete batch passed
Forward+ rendered checks on an NVIDIA RTX 4060 Ti across Player V2 animation/action
captures, City environment/buildings, Neon Circuit, Winners Circle, settings UI,
notifications, accessibility motion blur, and all 28 Victory Move frames. Headless and
multi-process suites also cover the new controller routing, Playpen recovery, OT supply,
Fast Hands, animation replication, lobby Player Hub, and social client contract. This is
functional/render coverage, not a substitute for measured frame-time data on Low.

The added runtime work stays bounded: Fast Hands reuses one cached 64px placeholder,
social presence/snapshot refreshes are low-frequency and inactive while signed out, and
Playpen recovery uses a 0.25s authority-only scan rather than a per-player network poll.
No extra gameplay viewport or continuous social animation loop was introduced. Retest
the full lobby → Playpen → match → Winners Circle loop at 1080p Low on the weaker laptop,
including repeated transitions and a physical controller, before the next public build.

The 2026-08-26 title-menu consolidation replaces five always-visible destination buttons
with one Player Hub entry. Its shared home/lobby portal is Canvas UI created only while
open, reuses the existing destination overlays, and adds no viewport, scene world, or
continuous process loop. Keep that lightweight contract when polishing the portal.

**Hat/social/controller checkpoint — 2026-08-29:** all twelve Hat cosmetics use optimized runtime GLBs and one animated head attachment per visible character. The original Rice Hat look is restored, including its rope, in a 5,482-triangle / approximately 164 KB runtime GLB; the original Crown gems and gold adornments are restored in a 13,911-triangle / approximately 325 KB runtime GLB. Pimp Hat and White Fedora preserve their original colors/materials at 13,231 and 3,858 triangles respectively, with textures reduced to 1024² where needed. Prize Counter and Locker reuse their existing quality-scaled preview viewport and render one selected Hat at a time. Both play only the shared idle while a Hat is visible; the Prize Counter viewport returns to `UPDATE_DISABLED` immediately after inspection closes or a non-3D item is selected. Rotation changes only the character pivot, so the camera, background, lights, and podium do not rotate or distort. Progression creates at most one 512×384 quality-scaled reward-preview viewport while its modal is open; its shared idle animation runs only while that modal exists, and the viewport is freed on close. None of these preview paths adds a gameplay viewport. The Friends orb and invitation toast are ordinary Canvas UI with no continuous 3D work. Structural and Forward+ front/overhead render checks discover all registered models and now cover 12 hats × 8 character models (96 combinations); key-pose Forward+ sheets additionally cover six gameplay/presentation animations on each of the five added fixed-look models. Their source GLBs are each below 1 MB, share the lazy per-model animation cache, and add no per-frame model-specific script. Live Locker and Prize Counter screen-space checks cover every hat/model pair at 0°, 90°, 180°, and 270° with safe top/side margins. The registry/fallback change adds no process loop, viewport, material, or network state. Retest repeated character switching, Hat browsing, two-controller menu navigation, a six-character match, and the Playpen → match → Winners Circle loop at 1080p Low on the weaker laptop before the public build.

**Gameplay shoulder-camera checkpoint — 2026-08-28:** the Hat-safe non-ADS sight line changes only the existing spring-arm and camera transforms. It preserves the same 4.0m boom, player-configured FOV, collision mask/margin, and single gameplay camera; it adds no viewport, physics query, material pass, visibility scan, or per-frame allocation. A 1600×900 matrix discovers the registered character list and currently covers 12 Hats × 3 models × non-ADS/ADS across animated samples, while the existing collision, controller, cosmetic, menu, and Forward+ capture suites remain clean. Confirm feel and frame pacing at 1080p Low on the weaker laptop.

**Skeleton-bound cosmetic checkpoint — 2026-08-29:** current Hats and future rigid wearables use engine-owned `BoneAttachment3D` transforms instead of adding another cosmetic `_process()` loop. Skinned shirts/pants reuse the visible actor's existing `Skeleton3D`; they do not instantiate a second animated character rig, physics body, viewport, or network object. Only equipped local meshes are instantiated, and model swaps free the old visual before applying the same stable-ID loadout to the replacement. Keep garment triangle/texture budgets within the normal character/prop guidance and test maximum visible equipped actors plus repeated Locker/match transitions at 1080p Low on the weaker laptop when the first clothing art is added.

**Character normalization checkpoint — 2026-08-29:** all six developer-gift wrappers are normalized once in their visual scenes and retain the existing shared `player.tscn` capsule; there is no added physics body, collision query, viewport, animation process, or per-frame model-specific work. Prevalidated idle actor-space envelopes keep home/preview framing accurate without runtime CPU skinning or vertex scans. Forward+ key-pose sheets cover six gameplay/presentation animations on all six gift models. Retest a six-character match, repeated model/Hat switching, and the Playpen → match → Winners Circle loop at 1080p Low on the weaker laptop before the public build.

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
