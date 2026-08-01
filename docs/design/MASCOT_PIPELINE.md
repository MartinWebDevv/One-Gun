# ONE GUN Mascot & Weapon Production Pipeline

Companion to `ONE_GUN_CHARACTER_WEAPON_ULTRA_PACKET_CODEX.md`. Created in
**Section 1 (Project Audit & Pipeline Setup)** — updated as sections complete.

**Approved visual references (locked):**
- `docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png` — 8-mascot roster sheet (Blue Cat master)
- `docs/design/OneGun_DefaultGunSkin_ConceptArt.png` — hydro ray pistol
  (canonical copy: `docs/design/ONE_GUN_DEFAULT_HYDRO_RAY_CONCEPT.png`, the
  filename the gun phase G1 expects)

**Production stage:** corrected Sections 1 and 2 are approved, and the Section
3 blockout proportions, stance, depth, and silhouette are approved. The first
Section 4 high-resolution model (`BC_HighRes_v001.blend`) was rejected after
user review. A ground-up organic rebuild (`BC_HighRes_v002.blend`) is at an
early clay direction checkpoint. Section 4 is not complete or approved, and
Section 5 retopology/UV/LOD work remains locked.

---

## 1. Section 1 audit results (2026-07-16; corrected 2026-07-17)

### Engine / tools
- **Godot 4.6 project format**, running with **Godot 4.6.3 stable**
  (`config/features = "4.6", "Forward Plus"`) and Jolt physics. Editor binary:
  `D:\GodotEngine\Godot_v4.6.3-stable_win64.exe` (not on PATH).
- **Blender 5.1.2** at `D:\Blender\blender.exe`, used headlessly
  (`--background --factory-startup --python <script>`). Existing generator
  scripts in `tools/` (e.g. `gen_trophy_pedestal.py`) are the house style:
  fully scripted, reproducible, save `.blend` + export in one run.
- No automated test suite. Verification = headless Godot boot
  (`--headless --path . --quit`, or load a scene) + human playtest.

### Current (temporary) player character
- `player.tscn` → `character_body_3d.gd` (humans, P1/P2 via `input_prefix`);
  `DummyModel.tscn`/`botmodel.tscn` → `dummy.gd` (bots, separate script,
  hand-duplicated tuning constants).
- Visual mesh: `models/playerAnimations/cat model firing ani.glb` — a
  Mixamo-rigged cat (bones named `mixamorig_*`, ~33 bones, authored ~10× scale
  and instanced at **0.45 scale, y −1.0** under a `CharacterModel` Node3D).
- The bot is not using the same visual hierarchy: `DummyModel.tscn` instances
  `botmodel.tscn` (the temporary orange model) at 0.7 scale. Its capsule is
  r 0.555, h 2.675 m and its hold markers are root-level nodes rather than
  hand-bone attachments.
- Human gameplay collider: capsule r 0.495, h ≈ 2.33 m. Collider, camera, and
  authoritative movement are gameplay-owned. The mismatch between that
  collider and the concept's 1.4 m visual target is unresolved; it cannot be
  silently solved by changing gameplay or scaling away the approved height.
- Camera: third-person `AimPivot/SpringArm3D/Camera3D` (spring 4.0, shoulder
  offset). There is **no first-person viewmodel**. Any exception to the
  packet's first-person review requirements needs explicit user approval in
  the gun phase; it is not assumed by Section 1.

### Animation system (temporary)
- One `AnimationPlayer` inside the cat GLB. `character_body_3d.gd`
  `_merge_animations()` merges 11 clips out of
  `models/playerAnimations/Dance.glb` **by hard-coded index**
  (`ANIM_INDICES`: idle, idle_jumping, idle_pistol, walk, run_jumping,
  walk_pistol, run, run_pistol, sprint_roll, death, dance). Index-based lookup
  is fragile — the new shared library must be **name-addressed**.
- No AnimationTree, no facial animation, no root motion in gameplay
  (root_motion_track set but locomotion is in-place, code-driven).
- `main_menu.gd` re-uses the same GLB + `idle_Pistol` (index 2) for the
  menu pedestal showcase (isolated overlay SubViewport).
- Individual source clips also exist as separate GLBs in
  `models/playerAnimations/` (idle, running, sprint, deaths, etc.).

### Weapon & item systems
- **Gun**: `gun.tscn`/`gun.gd` — exactly one per match. Visual:
  `models/weaponModels/water_gun.glb`. Reload = `ReloadTimer.wait_time = 2.0`
  **baked in the scene**, with no reload-duration field in `GameConfig`.
  Making it data-driven later requires an authoritative configuration field,
  animation-phase retiming, and integration validation; it is not merely a
  one-line visual hookup.
- **Human attachment**: `BoneAttachment3D` on `mixamorig_RightHand` / `LeftHand`
  with `Marker3D` children `GunHoldPoint`, `MeleeHoldPoint`, `ItemHoldPoint`;
  weapons are reparented onto the marker on pickup. This is the existing
  socket convention the new rig must reproduce (right hand = authoritative
  main grip — matches the packet default). **Bots use separate root-level
  hold markers**, so the later visual interface must support both controllers
  without duplicating production socket definitions.
- **Melee**: one `melee_weapon.tscn` per match, re-skinned each spawn by
  `MeleeWeaponRegistry` (bat, frying pan, crowbar, stick, swords in
  `models/weaponModels/`).
- **Throwables/deployables**: `item.tscn`/`item.gd` family — grenade,
  boomerang, smoke bomb, decoy, bubble-gum trap, bear trap, spring pad.
- **Shield**: there is **no held shield item** — "shield" is the
  `extra_melee_shield` powerup (blocks one melee hit). Packet shield-grip
  poses are future-proofing only; nothing to attach today.

### Multiplayer / persistence
- Online (Phases 1–2e): host-authoritative, actor-ID addressed;
  humans owner-authoritative movement, bots replicate as puppets;
  `online_actor_state` snapshot drives scoring/HUD. Character visuals are
  purely cosmetic client-side — a mesh swap doesn't touch authority, but any
  **future cosmetic IDs must replicate via validated IDs** (packet Section 8).
- `player_prefs.gd` stores personal settings + input rebinds only.
  **No character-selection, cosmetic, unlock, or loadout system exists** —
  Section 8 builds it from scratch. `GameConfig` presets cover match rules.
- `game_setup.tscn` contains a Customize Character button and an empty popup,
  but no customization implementation or character preview.
- Character presentation currently exists only in the main-menu pedestal
  showcase in `main_menu.gd`, which uses the temporary player and gun scenes.
  `lobby_map_preview.gd` previews maps, not characters. No podium character
  display exists yet.
- The temporary character uses imported materials/textures; there is no
  mascot material shader, recolor mask, accessory definition, portrait set,
  or cosmetic icon catalog.

### Repo state
- Instructions: both `AGENTS.md` (Codex) and `CLAUDE.md` (Claude Code) apply.
  Key rules: never edit hand-tuned map values; preserve unrelated working-tree
  changes; respect asset budgets (props ≤15k tris/1024², landmarks
  ≤100k/2048²); keep editable `.blend` sources and reproducible helpers.
- Large uncommitted working set exists (main-menu FABLE5 work etc.) —
  mascot work must not touch those files except where a section requires it.
- The packet, references, `art_src/`, and pipeline workspace are currently
  untracked. No commit or cleanup of unrelated files is authorized here.

---

## 2. Production workspace (created in Section 1)

```
art_src/                          # .gdignore — Godot never imports/scans this
  mascots/blue_cat/
    ref/                          # approved concept + turnaround/proportion sheets
    blend/                        # versioned .blend sources (never deliverables)
    materials/                    # editable texture, palette, and mask sources
    renders/                      # per-section visual review evidence
    qa/                           # validation reports, logs, and non-production output
  mascots/shared/
    blend/                        # authoring/export rig and shared animation sources
  weapons/one_gun/
    ref/  blend/  materials/      # approved reference and editable sources
    renders/  qa/                 # gun review and validation evidence
models/mascots/
  blue_cat/                       # BlueCat LOD GLBs and external runtime textures
    textures/                     # customization masks and texture deliverables
  shared/                         # shared skeleton/animation GLB exports
  accessories/                    # exported universal/body-fit accessory meshes
models/weaponModels/one_gun/      # final gun LODs, textures, and moving-part exports
tools/mascot_pipeline/            # reproducible Blender helper scripts
Scenes/characters/
  shared/                         # shared runtime skeleton/animation resources
    attachments/                  # attachment/socket contract resources
  materials/                      # mascot shaders and material definitions
  accessories/                    # cosmetic catalog/attachment definitions
  blue_cat/                       # Blue Cat Godot scenes and import wrappers
docs/design/                      # packet, approved concepts, this doc
```

`art_src/.gdignore` keeps heavy sources and hundreds of QA renders out of the
Godot importer. Only `models/**` GLBs and `Scenes/characters/**` scenes are
game-facing. Every intentionally empty production directory contains a
`.gitkeep` so the structure survives a clean checkout.

## 3. Naming convention (versioned)

- Blender sources: `art_src/mascots/<mascot>/blend/<Mascot>_<stage>_v###.blend`
  — stages: `ref`, `blockout`, `hires`, `retopo`, `face`, `mat`, `rig`,
  `anim`. Example: `BlueCat_blockout_v001.blend`. Never overwrite an approved
  version; bump `v###`.
- Helper scripts: `tools/mascot_pipeline/<mascot-prefix>_<purpose>.py`
  (`bc_blockout.py`, `shared_export.py`…). Every repeatable operation is a
  script, per packet rule 9.
- Mascot exports: `models/mascots/<mascot>/<Mascot>_LOD0.glb` (+ `_LOD1`,
  `_LOD2`); shared skeleton/animation export:
  `models/mascots/shared/MascotAnimations.glb`.
- Gun exports: `models/weaponModels/one_gun/OneGun_Default_LOD0.glb`
  (+ `_LOD1`, `_LOD2`) with stable moving-part and socket names.
- Renders: `art_src/mascots/<mascot>/renders/S<sec>_<view>_v###.png`
  (views: front/side/back/quarter/silhouette/wire/overlay/turntable).
- QA: `art_src/mascots/<mascot>/qa/S<sec>_<check>_v###.<ext>` and the
  equivalent weapon path. QA output is never a production export.
- Animation actions are stable, name-addressed runtime contracts. Initial
  shared names include `Idle_Base`, `Idle_Var01`, `Walk_F`, `Run_F`,
  `Sprint_F`, `Jump_Start`, `Jump_Air`, `Land_L`, `Land_H`, `Gun_Hold`,
  `Gun_Aim`, `Gun_Fire`, `Gun_Reload`, `Gun_Drop`, `Melee_*`, `Throw_*`,
  `React_*`, `Emote_*`, `Victory_*`, `Podium_1`, `Podium_2`, `Podium_3`,
  `Menu_PedestalIdle`, and `Death_Default`. Slashes are not used inside an
  action name because Godot reserves them for animation-library addressing.
  Per-mascot personality overrides prefix the mascot code (`BC_Idle_Base`).
  Action revisions inherit the containing versioned `.blend` filename; the
  stable runtime action name does not receive a version suffix.
- Bones: shared skeleton uses the packet's standard names (Section 9), NOT
  `mixamorig_*`; the old names die with the temporary model.

## 4. Blue Cat production path (proposal)

1. **S2 Reference** — script-crop the roster sheet regions (lineup, scale
   sheet, toy-style guide, expressions, weapon holds) into
   `ref/`, build measured orthographic turnaround at 1.4 m; mark inferred
   back/side details as proposals. Stop for approval.
2. **S3 Blockout** — `bc_blockout.py`, fixed ortho cams matched to the
   turnaround, silhouette/overlay renders + turntable. Stop.
3. **S4 Hi-res model** — subdivision sculpt pass to premium-toy finish. Stop.
4. **S5 Retopo/UV/LODs** — deformation topology, masks UVs,
   LOD0 35–60k / LOD1 15–25k / LOD2 6–10k. Stop.
5. **S6 Face** — eyeballs, lids, brows, shape keys (Godot-exportable),
   15 required poses. Stop.
6. **S7 Materials** — palette sampled from the sheet, mask channels
   (Primary/Secondary/Belly/Markings/Accent/Eyes/Details), 2K plan. Stop.
   → **HARD GATE A** → Gun G1–G10 → **HARD GATE B** → S8+ (customization
   architecture, shared rig ~65–75 export bones, weighting, grips,
   animation library, Godot AnimationTree integration, perf) → **HARD GATE C**.

Each stop produces the packet's required review renders into `renders/` and a
report; no self-approval.

## 5. Compatibility concerns (flagged now, resolved at the named section)

1. **Scale is an approval decision, not a settled workaround**: the concept
   locks mascots at ~1.4 m, while the live human capsule is ~2.33 m and the
   camera/maps are tuned around the current body. The Blue Cat must be authored
   at a true 1.4 m. Before S16 changes runtime scale or collision, provide a
   side-by-side gameplay/hitbox/camera study and obtain explicit approval.
   Do not silently scale away the approved height or alter authoritative
   collision as part of an art swap.
2. **Reload duration** is baked into `gun.tscn` (2.0 s), not `GameConfig` —
   G7/G9 require a single authoritative, data-driven configuration field plus
   phase-retiming and networking tests. This is a later gameplay-facing change
   and needs its own reported integration evidence.
3. **Animation lookup by index** (`ANIM_INDICES`) must become name-based when
   the shared library lands (S16); bots (`dummy.gd`) and the menu showcase
   (`main_menu.gd`) reference the same clips and swap at the same time.
4. **No first-person viewmodel exists** — the gun phase must either add an
   approved first-person presentation path or receive an explicit exception
   allowing third-person and menu close-up evidence. Section 1 does not choose.
5. **No held shield item exists** — shield grips/poses are authored for
   future use but have no gameplay hookup today.
6. **Two character scripts and two socket arrangements exist**:
   `character_body_3d.gd` uses bone-attached markers; `dummy.gd` uses root-level
   markers. The S16 visual interface must cover humans, bots (`botmodel.tscn`),
   and the menu pedestal without splitting the production rig contract.
7. **No customization runtime exists** — Section 8 must add stable IDs,
   validated network serialization, material isolation, compatibility rules,
   and missing-content fallbacks without sending arbitrary resource paths.

---

## 6. Corrected Section 1 approval record (2026-07-17)

- Audit paths and tool versions have been independently checked against the
  current repository.
- Every packet-required production category now has a documented, trackable
  location outside unrelated gameplay systems.
- The temporary cat, bot, gun, animations, and gameplay scenes remain intact.
- No Blue Cat model, rig, production export, material, runtime character scene,
  customization implementation, or gameplay integration has been created.
- Existing Section 2 reference outputs were preserved without being reviewed
  or approved as part of the Section 1 correction.

The user approved the corrected Section 1 by instructing Codex to continue.

## 7. Corrected Section 2 approval record (2026-07-17)

- Audited Claude's v001 extraction, measurement, turnaround, and detail-guide
  work against the approved concept and every Section 2 requirement.
- Retained all v001 sheets for provenance, but superseded them because the
  mirrored “side” was not a true side, the filled “back” was not an approved
  interpretation, and several requested proportions were missing.
- Added exact native source crops and a v002 locked-evidence atlas covering the
  lineup, scale panel, toy guide, expressions, animation, weapon holds, rig
  diagram, and environment example.
- Added a complete 1.40 m normalized measurement sheet with evidence classes,
  tolerances, all packet-requested visible dimensions, and unseen depth values
  isolated as proposals.
- Added v002 turnaround and detail sheets that clearly separate approved art
  from true-side, true-back, tail-rest, hand, marking, and relaxed A-pose
  proposals.
- No `.blend`, `.glb`, Godot model scene, rig, material, or gameplay file was
  created or changed for Section 2.
- The user approved the corrected v002 package and all four isolated proposals:
  lineup-master hand/foot markings, the side-depth envelope, the plain-back and
  tail-rest interpretation, and the relaxed A-pose/hand plan.

This approval unlocked Section 3; its subsequent review state is recorded
below.

## 8. Section 3 blockout approval record (2026-07-17)

- Created `art_src/mascots/blue_cat/blend/BC_Blockout_v001.blend` in Blender
  5.1.2 using separate editable masses and the approved relaxed A-pose.
- Evaluated floor-to-ear height is 1.397 m against the approximately 1.40 m
  target. The approved head width/depth, torso depth, stance, muzzle, feet, and
  tail envelope are represented directly in scene units.
- Added fixed front, matching-direction side, back, and three-quarter
  orthographic cameras plus neutral studio lighting.
- Produced front/side/back/three-quarter, true black silhouette, metric
  reference-overlay, 48-angle animated turntable, and static contact review
  renders.
- Corrected the first render pass by lowering the crown tufts, extending the
  tail into a readable rear silhouette, matching the source-facing side
  direction, and replacing the lit black material with a true alpha-derived
  silhouette.
- The `.blend` contains zero UV layers and zero armatures. No production
  topology, rig, skinning, texture, character animation, Godot export, or
  runtime file was created or changed.
- Remaining proportion/silhouette mismatches and their approximate sizes are
  recorded in `art_src/mascots/blue_cat/qa/BC_BLOCKOUT_NOTES.md`.
- The user approved the proportions, stance, depth, and silhouette direction.
- Approval is conditional on Section 4 replacing the temporary bead-like arms
  with continuous rounded limb forms and removing all blocky, sharp, or
  visibly segmented construction across the character. The required finish is
  the smooth, cohesive, polished premium-toy look of the approved concept.

## 9. Section 4 high-resolution form review (2026-07-17)

- Created `art_src/mascots/blue_cat/blend/BC_HighRes_v001.blend` from the
  approved blockout direction. The file retains 35 hidden editable
  construction objects and a separate final review collection.
- Replaced the temporary segmented arms with one closed Bezier-derived trunk
  per arm. The arm, shoulder bridge, torso, hip bridge, leg, hand, foot, head,
  ears, crown tufts, and tail are fused into one watertight rounded body shell.
- Added intentional separate review forms for eyeballs, socket/lid rims,
  irises, pupils, highlights, brows, inner ears, muzzle, nose, mouth, whiskers,
  belly, palm pads, three toe pads per foot, and the tail tip.
- Corrected the initial voxel pass after review exposed open-curve surface
  tearing. All construction curves are capped, the shell is one connected
  component with zero non-manifold or boundary edges, and dense surface
  relaxation removes the remaining voxel ribs.
- The blue review material uses a low-specular satin finish so the form reads
  like the approved smooth premium-toy concept rather than a glossy blockout.
  These are temporary flat review materials only; Section 7 remains the
  production material stage.
- User-review corrections recessed the eye whites, moved the blue socket rims
  behind the whites, compressed the iris/pupil/highlight stack to a shallow
  surface layer, rebuilt the tail around a broad pelvis-embedded root, and
  flattened/buried the palm pads into the hand surface. All Section 4 media was
  regenerated after these corrections.
- Evaluated review height is 1.3875 m, 12.5 mm (0.9%) below the concept's
  approximate 1.40 m target after high-resolution surface relaxation. The
  fixed metric/reference overlays show the retained approved proportions and
  silhouette; the exact export scale remains locked for the Section 5 mesh.
- Saved-source audit: 276,008 base triangles across all visible review forms;
  body shell 112,034 vertices / 112,032 faces; zero UV layers; zero armatures;
  zero file-texture images. This is intentionally the high-resolution source,
  not the 35-60k LOD0 budgeted for Section 5.
- Produced fixed front/side/back/three-quarter views, alpha-derived black
  silhouette, metric reference overlays, explicit face/shoulder/hand/feet/tail
  closeups, wire review, and a 48-view animated turntable plus contact sheet.
- Full audit and deliverable index are recorded in
  `art_src/mascots/blue_cat/qa/BC_HIGHRES_NOTES.md`.
- No retopology, production UV, LOD, rig, skinning, shape-key library,
  production texture, Godot export, runtime scene, or gameplay file was
  created or changed in Section 4.

The user rejected this v001 model after review because the overall result still
read as smoothed procedural parts rather than the approved professionally
sculpted toy character. V001 is retained for provenance only and is not an
approval candidate.

The replacement `BC_HighRes_v002.blend` rebuilds the character around one
organic implicit body sculpt, shallow embedded eyes, a unified muzzle, a clean
swept tail rooted inside the pelvis, and surface-seated palm markings. Six
early clay views are recorded in
`art_src/mascots/blue_cat/qa/BC_HIGHRES_V002_NOTES.md`. The full Section 4
package is deliberately deferred until the user accepts this new direction.

Section 4 remains in progress and Section 5 remains locked.
