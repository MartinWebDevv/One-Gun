# ONE GUN Character, Weapon, Animation & Customization — Fable 5 Ultra Production Packet

## Purpose

Provide one controlled start-to-finish production sequence for the ONE GUN mascots, final ONE GUN weapon, shared animation system, and complete player-customization architecture.

Create production-quality, game-ready versions of the eight mascots shown in the supplied ONE GUN character concept sheet:

1. Blue Cat
2. Red Fox
3. Green Frog
4. Panda
5. Raccoon
6. Penguin
7. Axolotl
8. Bear

The final characters must preserve the concept's lively expressions, large readable silhouettes, rounded toy-like forms, smooth materials, and playful personality. They must not look faceted, primitive, stiff, unfinished, or intentionally low-poly.

This packet also creates the final central ONE GUN weapon and establishes:

- A shared game-ready skeleton and animation system
- Facial expressions and emotes
- Gun, melee, throwable, and shield handling
- Personality animation variants
- Godot integration and performance requirements
- The complete approved player-customization system


## Master Production Map

Fable must follow this order. A later phase is locked until the user explicitly approves the preceding hard gate.

| Phase | Allowed work | Required stop |
| --- | --- | --- |
| Phase A | Sections 0–1: audit and pipeline setup | Confirm assets and production paths |
| Phase B | Sections 2–7: Blue Cat reference, model, topology, face, and materials | **Hard Gate A: approve the unrigged Blue Cat visual asset** |
| Phase C | Gun Sections G1–G10: final weapon from reference through Godot | **Hard Gate B: approve the final gun** |
| Phase D | Sections 8–18: customization, rig, grips, animation, Godot, and Blue Cat QA | **Hard Gate C: approve the complete Blue Cat** |
| Phase E | Sections 19–26: remaining mascots, one at a time | **Hard gate after every mascot** |
| Phase F | Sections 27–29: roster QA, customization validation, and delivery | Final production approval |

## Locked Default Weapon Concept

The approved Option C hydro ray pistol concept is the canonical base weapon design. Place the approved concept image in the Fable design packet under the clear filename `ONE_GUN_DEFAULT_HYDRO_RAY_CONCEPT.png`.

Locked visual decisions:

- Compact single-shot hydro ray pistol
- Primarily one-handed with a second-hand support area
- Friendly rounded toy styling with a polished, moderately sleek silhouette
- Cream-white upper shell
- Deep cobalt/navy grip, lower structure, and support surface
- Orange muzzle ring, top hatch, trigger, and controls
- Wide circular muzzle ring with a medium-length slender cyan-tipped nozzle
- Cyan-tinted chamber window showing one yellow hydro pellet
- Top loader that opens while cyan water energy condenses a fresh pellet
- Small star emblem and subtle ONE GUN stamp
- Yellow projectile core, thin cyan liquid-energy trail, and cyan splash impact with small yellow droplets

The shape is the canonical base gun model. Its approved colors and materials form the default gun skin. Future recolors, patterns, decals, finishes, special skins, and themed model variants must use the customization rules in this packet.

The current gameplay reload duration is two seconds, but it must remain data-driven. The animation is divided into Open, Condense, Insert/Settle, and Close phases. Small duration changes may scale the full sequence. Larger changes should primarily adjust the condensation/hold phase so mechanical opening and closing never look unnaturally fast or slow.

### Approval Rules

- Fable cannot approve its own work.
- Completing a section does not unlock the next hard-gated phase.
- Only an explicit user instruction to continue past the named gate unlocks the next phase.
- If Fable is started in a new conversation, it must inspect the project and identify the last explicitly approved gate before editing.
- Fable must execute only the next allowed section, provide its required review evidence, and stop.
- Fable must never skip ahead because a later task appears technically possible.
- The final gun may not be replaced with a placeholder after Hard Gate B.
- Approved character or gun source assets may not be destructively rebuilt without the user's permission.

### Normal Start Command

Give Fable this packet and the approved concept sheets, then say:

> Read the complete ultra packet. Determine the current approved production stage. Execute only the next allowed section and stop at its required review point.


## How to Use This Packet

Give Fable 5:

- The existing ONE GUN Godot project
- The supplied mascot concept sheet
- This Markdown packet

Send the prompts below **one section at a time and in order**. Fable must stop after every section and provide the requested renders, screenshots, files, and validation results for approval.

Do not allow Fable to create the gun and all eight mascots at once. The **Blue Cat must complete the entire production pipeline and receive approval in Blender and Godot before another mascot begins**.

Near-1:1 means matching the approved reference's silhouette, proportions, facial construction, colors, rounded finish, personality, and visual weight. Where the single concept sheet does not show a side or back design, Fable must not silently invent a final design; it must create a reviewable turnaround proposal and wait for approval.

---

# Section 0 — Permanent Quality Rules

## Prompt for Fable 5

```text
You are building the ONE GUN mascot roster from the supplied concept sheet using Blender and Godot. These rules apply permanently to every section of this packet.

QUALITY AND SCOPE RULES
1. Build only the mascot or production stage explicitly requested in the current prompt.
2. The Blue Cat is the master character. Do not begin another mascot until the Blue Cat passes the final Blender, animation, customization, Godot, and performance approval gate.
3. Do not use a one-pass primitive-generation workflow as the final model. Spheres, capsules, cylinders, and metaballs may be used only for early blockout.
4. The finished LOD0 must use smooth continuous forms, clean deformation topology, smooth shading, controlled subdivision, and rounded transitions.
5. No flat-shaded or intentionally low-poly finish. No visible primitive intersections. No sharp shoulder, wrist, hip, ankle, muzzle, ear, finger, or tail junctions unless specifically shown in the reference.
6. Do not confuse a low-detail art direction with a low-quality mesh. The concept uses simple shapes with polished surfaces.
7. Match the supplied concept through fixed-camera reference overlays and rendered comparisons. Do not rely only on memory or verbal interpretation.
8. Preserve editable .blend source files. Exported .glb files are deliverables, not source replacements.
9. Blender Python may automate scene setup, naming, materials, modifiers, exports, renders, QA, and repeatable operations. Do not depend on a script that merely assembles crude primitives and declares the character complete.
10. Keep authoring rigs and export/deformation rigs separate when useful. Only required deformation bones and animation data should be exported to Godot.
11. Do not accept automatic skin weights without manual deformation testing and correction.
12. Do not begin rigging until the unrigged model is visually approved.
13. Do not begin final animation until the rig and deformation tests are approved.
14. Do not permanently modify unrelated gameplay, networking, weapon, combat, save, or map systems.
15. Use existing project conventions, paths, naming, autoloads, and resources where practical.
16. Inspect existing project assets before creating replacements.
17. Treat customization as a core requirement. Do not bake colors, accessories, or outfit assumptions in ways that block later customization.
18. Cosmetic options must not alter gameplay hitboxes, movement speed, damage, weapon behavior, or multiplayer authority.
19. All gameplay locomotion animations must be in-place unless a specific cinematic/menu animation is explicitly approved for root motion.
20. Character personality differences must preserve gameplay timing and fairness unless a separate gameplay-perk system is approved later.

REQUIRED REVIEW OUTPUTS
At each visual milestone, provide front, side, back, three-quarter, silhouette, and wireframe renders plus a turntable when requested. For Godot stages, provide fresh in-engine screenshots or recordings. Report exact files created or edited and validation performed.

FAIL CONDITIONS
- Faceted silhouette or visibly low-poly curved surfaces
- Raw primitive shapes visible in the final model
- Stiff neutral pose caused by poor rigging or weighting
- Incorrect scale or proportions
- Dead, painted-on, or nonfunctional facial features
- Clipping hands, weapons, clothes, or accessories
- Broken shape keys or deformations after export
- Unapproved invention of unseen character details
- Missing editable source files
- Claims of a close match without comparison renders

Before implementing the current section, inspect all relevant existing files and report genuine blockers. Implement when possible rather than stopping at a plan. Stop after the requested section.
```

---

# Section 1 — Project Audit and Character Pipeline Setup

## Prompt for Fable 5

```text
Audit the existing ONE GUN project and prepare a non-destructive mascot production workspace. Do not model a character yet.

Inspect and report:
- Godot version and renderer
- Blender version available to the project
- Existing player character scenes and meshes
- Existing skeletons, AnimationPlayers, AnimationTrees, and animation libraries
- Existing gun, melee, throwable, and shield scenes
- Current weapon attachment and hand-placement methods
- Current player scale, collider dimensions, camera assumptions, and multiplayer replication
- Existing character selection, save/profile, cosmetic, inventory, unlock, or loadout systems
- Existing materials, shaders, UI previews, icons, and pedestal character display
- Repository instructions and current uncommitted changes

Create an organized production structure consistent with the project. It should have clear locations for:
- Blender source files
- Reproducible Blender helper scripts
- Reference images and approved turnarounds
- Exported GLB assets
- Godot mascot scenes
- Shared skeleton/animation resources
- Materials and customization masks
- Accessories and attachment definitions
- Review renders and QA output, excluded from production exports when appropriate

Define a versioned naming convention for mascot files and animation actions. Do not overwrite the existing temporary cat model or gameplay character until the new production asset passes approval.

Propose the exact Blue Cat path from reference to blockout, high-quality model, retopology, face, materials, rig, animation, customization, export, and Godot testing based on what exists in the project.

Stop after the audit and folder/pipeline setup. Provide the discovered asset paths, planned files, and any compatibility concerns.
```

---

# Section 2 — Reference Extraction and Blue Cat Turnaround

## Prompt for Fable 5

```text
Prepare a modeling-ready Blue Cat reference package from the supplied mascot concept sheet. Do not build the 3D model yet.

Requirements:
- Extract the clearest available Blue Cat reference areas without altering their proportions.
- Use the lineup front view, scale/proportion front and side views, toy-style guide, expression examples, animation examples, weapon-hold examples, and environment example.
- Establish the character's official height as approximately 1.4 meters from the bottom of the feet to the top of the ears.
- Measure the visible proportions instead of guessing: overall width, head height and width, eye size and separation, muzzle position, torso length, shoulder width, arm length, hand size, leg length, foot size, ear size, and tail thickness.
- Create a consistent orthographic reference layout with front, side, back, and three-quarter views at the same scale.
- Use the supplied views as locked evidence. Where the back or hidden areas are not shown clearly, create a proposed interpretation that preserves the established design language and mark it as a proposal.
- Include a face close-up, neutral expression, eye construction guide, mouth/muzzle guide, hand/foot close-up, tail guide, and sampled color palette.
- Keep the character in a relaxed modeling pose suitable for rigging, not a rigid military T-pose. Use a symmetrical A-pose with slightly bent elbows and separated fingers if the intended hand design includes fingers.
- The design must retain: large expressive head, oversized green eyes, blue body, cream muzzle/belly areas, pink inner ears, small head tufts, rounded limbs, chunky hands, sturdy feet, and readable tail silhouette.
- Do not introduce realistic fur, sharp anatomy, excessive muscle definition, clothing, or unapproved markings.

Provide the turnaround and measured proportion sheet for approval. Identify every area that was inferred rather than directly visible. Stop before modeling.
```

---

# Section 3 — Blue Cat Proportional Blockout

## Prompt for Fable 5

```text
Create the first Blue Cat proportional blockout in Blender using the approved turnaround. This is a silhouette and proportion stage, not the finished mesh.

Requirements:
- Configure Blender units so the character measures approximately 1.4 meters from floor to ear tips.
- Set fixed orthographic front, side, and back cameras aligned with the approved reference images.
- Create a symmetrical A-pose blockout with separate temporary masses only where useful for iteration.
- Match the concept's large head, wide cheeks, small torso, short limbs, chunky hands, large stable feet, ear placement, muzzle projection, and tail shape.
- Avoid realistic adult human proportions. The character should read as a compact toy mascot from silhouette alone.
- Use enough subdivision in preview renders that curved silhouettes are smooth even during blockout.
- Do not add small surface details, UVs, rigging, textures, or animations yet.
- Create front, side, back, three-quarter, black-silhouette, and reference-overlay renders.
- Create a 360-degree turntable using neutral studio lighting.
- Compare the render against the reference and list the largest remaining proportion mismatches.

Stop after the blockout. Do not proceed to final modeling until the silhouette and proportions are approved.
```

---

# Section 4 — Blue Cat High-Quality Rounded Model

## Prompt for Fable 5

```text
Convert the approved Blue Cat blockout into a polished high-quality character model while preserving the approved silhouette.

Requirements:
- Create smooth continuous body forms with clean transitions at neck, shoulders, wrists, hips, ankles, muzzle, ears, and tail.
- Use a subdivision/sculpted workflow appropriate for a rounded premium-toy finish.
- The head must feel full and expressive, with padded cheeks and a muzzle that projects naturally rather than appearing pasted onto a sphere.
- Build proper eye sockets and eyelid volumes around separate rounded eyeballs.
- Model the nose, mouth line, cheeks, eyebrows, ear rims, inner ears, head tufts, belly/muzzle regions, hands, feet, claws/toes if approved, and tail as intentional forms.
- Keep details bold and readable at gameplay distance. Do not add pores, realistic fur strands, or noisy microdetail.
- Hands must be chunky but capable of securely holding the gun, bat, frying pan, stick, throwables, and shield. Use the approved simplified finger arrangement.
- Feet must have broad stable contact surfaces and a strong silhouette for running and landing.
- Use smooth shading and sufficient mesh density to eliminate faceting in close menu renders.
- Preserve non-destructive modifiers and an editable source model where practical.
- Do not rig, UV unwrap, or texture yet unless a temporary flat material is needed for review.

Target guidance for the eventual LOD0 is approximately 35,000–60,000 triangles, but prioritize the approved silhouette and deformation quality before optimization.

Provide studio renders, silhouettes, wireframe previews, reference overlays, and a turntable. Explicitly show the face, hands, feet, shoulders, and tail close-up. Stop for model approval.
```

---

# Section 5 — Retopology, UVs, Mesh Organization, and LODs

## Prompt for Fable 5

```text
Prepare the approved Blue Cat model for deformation, materials, customization, and real-time use.

Requirements:
- Create clean primarily quad-based deformation topology.
- Add appropriate loops around eyes, eyelids, eyebrows, muzzle, mouth, shoulders, elbows, wrists, fingers, hips, knees, ankles, toes, ears, and tail.
- Maintain smooth rounded silhouettes without wasting geometry on flat hidden areas.
- Prevent poles and long thin faces in high-deformation regions.
- Organize the model into intentional components. Keep the main deforming body continuous where seams would be visible. Separate eyeballs, facial parts, accessory-ready components, and other elements only where technically useful.
- Define stable material slots and names for customization regions.
- Create non-overlapping UVs with consistent texel density. Reserve appropriate space for the face, eyes, hands, and other close-view areas.
- Create customization mask UVs or compatible mask texture layout.
- Produce LOD0, LOD1, and LOD2 while preserving silhouette and facial readability.
- Suggested budgets: LOD0 35k–60k triangles, LOD1 15k–25k, LOD2 6k–10k. Deviate only with a documented visual or performance reason.
- Keep a high-resolution source model separate from the game meshes.
- Verify normals, tangents, transforms, origin, scale, symmetry, manifold state where appropriate, and absence of accidental duplicate geometry.

Provide solid and wireframe turntables of every LOD plus triangle counts and UV previews. Stop before facial shape keys or rigging.
```

---

# Section 6 — Face, Eyes, and Expression System

## Prompt for Fable 5

```text
Build the Blue Cat facial system so the character can reproduce the concept's lively expressions without losing its rounded appeal.

Requirements:
- Use separate rounded eyeballs with coordinated eye-aim controls.
- Build upper and lower eyelids that conform to the eye surface during blinks and squints.
- Create controllable eyebrows with enough range for friendly, focused, sad, surprised, and angry expressions.
- Build muzzle, cheek, mouth, and jaw deformation using shape keys, bones, or a documented combination that exports reliably to Godot.
- Avoid a flat mouth drawn on the surface. Expressions must change the actual facial silhouette where appropriate.
- Create standardized shape/control names that every mascot will share where anatomically possible.
- Required poses: Neutral, Happy, Focused, Surprised, Victory, Taunt, Sad, Angry, Blink, Half Blink, Squint, Look Left, Look Right, Look Up, and Look Down.
- Add mouth shapes necessary for exertion, impact, open smile, frown, and simple future vocal reactions.
- Preserve eye volume, avoid eyelid clipping, and prevent cheek/muzzle collapse at extreme expressions.
- Ensure every expression works with head turns and body poses.
- Do not add speech lip-sync complexity beyond reusable mouth shapes unless existing project requirements call for it.

Provide close-up renders and a short facial-expression preview showing transitions between all required poses. Stop after the facial system is approved.
```

---

# Section 7 — Toy Materials, Palette, and Recolor Masks

## Prompt for Fable 5

```text
Create the Blue Cat's production materials and customization-ready color system.

Requirements:
- Sample the approved colors from the concept rather than choosing unrelated blues, creams, greens, or pinks.
- Preserve the main visual regions: primary blue body, secondary blue/markings, cream muzzle/belly/paw regions, pink inner ears, green irises, dark pupils, nose, claws/details, and approved accents.
- Use soft toy-like PBR materials with moderate roughness, restrained specular response, and subtle surface variation.
- Do not use realistic fur particles or noisy fur textures.
- Do not make the character look wet, metallic, rubbery, chalky, or flat/unlit.
- Create reusable mask channels for Primary, Secondary, Belly/Muzzle, Markings, Accent, Eyes, Nose/Details, and any approved species-specific region.
- Colors must be changeable without duplicating the entire texture set.
- Use stable parameter names that Godot can expose through material instances.
- Create a 2K production texture/mask plan unless testing shows a different resolution is justified. Higher-resolution authoring sources may be retained, but runtime imports should remain appropriate for up to ten players.
- Pack grayscale data where project conventions support it and document every channel.
- Verify materials under neutral studio light, the main-menu pedestal lighting, and representative gameplay lighting.

Provide material-ball references, color swatches, mask previews, and Blue Cat renders under all three lighting conditions. Stop for approval.
```

---


# HARD GATE A — Approve the Unrigged Blue Cat Visual Asset

Fable reaches this gate only after Sections 2–7 are complete.

The user must approve:

- Blue Cat turnaround and inferred design decisions
- Approximately 1.4-meter scale
- Front, side, back, and three-quarter proportions
- Smooth rounded LOD0 model
- Hands sized for the final weapon
- Face and expression construction
- Clean topology, UVs, and LOD plan
- Toy-like materials and customization masks

Fable must stop here. It may not begin the shared skeleton, customization implementation, weapon grips, or animation work.

After explicit approval, proceed to Gun Section G1. The final gun must be approved before mascot Section 8 begins.

---

# Gun Section G1 — Weapon Reference Sheet and Mechanical Design

## Prompt for Fable 5

~~~text
Begin production of the final ONE GUN weapon. The unrigged Blue Cat visual asset has been explicitly approved. Do not rig or animate the character during the gun phase.

REFERENCE REQUIREMENTS
- Locate `ONE_GUN_DEFAULT_HYDRO_RAY_CONCEPT.png` in the project or design packet. This is the approved canonical base weapon and default skin.
- If dedicated gun concept art is missing, stop and request it. Do not create the final gun from a tiny menu image or an unclear single perspective.
- Prepare aligned left, right, front/muzzle, rear, top, bottom, and three-quarter references.
- Add grip, muzzle, sight, trigger, reload mechanism, ammunition, and moving-part close-ups.
- Establish dimensions beside the approved 1.4-meter Blue Cat and its actual hand meshes.
- Sample the approved color and material palette.
- Mark every unseen or ambiguous area as a proposed design requiring approval.

MECHANICAL DESIGN REQUIREMENTS
Document how the weapon visually supports ONE GUN's rules:
- One round of ammunition
- One shot before empty
- Two-second reload
- Pickup from the map
- Drop at the disarm location
- One-shot kill gameplay authority
- Clear loaded and empty states

Define:
- Where the single round, cartridge, dart, or energy unit is stored
- What opens or moves during reload
- What the mascot inserts, rotates, closes, or charges
- What moves during firing and recoil
- Whether anything ejects
- How loaded versus empty is visible
- Where the trigger and sight are located
- How the mechanism remains playful and toy-like rather than realistically firearm-like

Do not model yet. Provide the full reference/mechanical sheet, dimension proposal, moving-parts diagram, and list of inferred decisions. Stop for approval.
~~~

---

# Gun Section G2 — Scale, Ergonomics, and Silhouette Blockout

## Prompt for Fable 5

~~~text
Create the final gun's proportional blockout using the approved weapon reference and the approved Blue Cat mesh.

Requirements:
- Work at correct Blender/Godot scale.
- Fit the main grip to the Blue Cat's actual right hand.
- Establish a reachable trigger and a reliable left support-hand position.
- Keep the gun clear of the face during default hold and aim poses.
- Match the concept's overall body, barrel, muzzle, grip, sight, and reload-component proportions.
- Preserve a chunky, readable toy-blaster silhouette.
- Ensure the gun remains recognizable from gameplay distance and attractive in first-person and menu close-ups.
- Use smooth preview subdivision so blockout renders are not visibly faceted.
- Do not add final panel lines, small details, UVs, textures, rigging, or production materials yet.

Provide:
- Left, right, front, rear, top, and three-quarter renders
- Black silhouette
- 360-degree turntable
- Blue Cat one-handed and two-handed hold tests
- First-person framing test based on the existing camera system
- Third-person gameplay-distance framing test
- Main-menu pose test
- Dimensions and largest remaining mismatches

Stop for silhouette, scale, and ergonomic approval.
~~~

---

# Gun Section G3 — High-Quality Rounded Model and Functional Parts

## Prompt for Fable 5

~~~text
Convert the approved gun blockout into the polished final high-resolution weapon model.

QUALITY TARGET
- Premium rounded toy construction matching the approved mascot style
- Smooth curved shells and controlled bevels
- Large readable layered forms
- Chunky muzzle and comfortable grip
- Clean color-break panels
- Subtle approved ONE GUN branding
- No razor edges, faceted curves, visible primitive intersections, or random nonfunctional detail
- No realistic firearm manufacturing details or gritty military treatment

FUNCTIONAL PARTS
Separate only components that genuinely move or need independent materials, such as:
- Main body/shell
- Muzzle or barrel assembly
- Trigger
- Single-round chamber
- Chamber door, lever, latch, or charging part
- Removable ammunition piece
- Loaded/empty indicator
- Sight
- Approved optional moving accents

Build the reload mechanism so its motion is physically understandable at the current two-second default while remaining adjustable through the data-driven reload phase system. The ammunition cannot be permanently fused into the loaded model.

Maintain the approved grip, support-hand, muzzle, sight, and scale relationships.

Provide:
- High-quality studio renders
- Close-ups of grip, trigger, muzzle, sight, reload mechanism, ammunition, and indicator
- Character hold tests
- First-person and third-person renders
- Solid and wireframe turntables
- Comparison against the approved weapon concept

Stop for high-resolution model and mechanism approval.
~~~

---

# Gun Section G4 — Game Meshes, UVs, Normals, and LODs

## Prompt for Fable 5

~~~text
Prepare the approved weapon model for real-time Godot use.

Requirements:
- Preserve the editable high-resolution source.
- Create a smooth close-view LOD0 suitable for first-person, menu, and podium presentation.
- Create LOD1 for normal third-person use and LOD2 for distant presentation.
- Choose triangle budgets based on measured quality and performance rather than forcing a visibly low-poly silhouette.
- Maintain clean curved silhouettes, muzzle shape, grip, and moving-part fit across LODs.
- Use clean topology around bevels, moving parts, panel breaks, and cylindrical forms.
- Correct normals, tangents, smoothing, transforms, scale, origins, and object hierarchy.
- Create efficient UVs with consistent texel density and extra priority for first-person visible surfaces.
- Organize stable material slots and customization-mask UVs.
- Avoid unnecessary hidden geometry and excessive separate draw-call objects.
- Keep moving parts independently animatable.
- Create simple gameplay collision separately from the visible mesh; do not use the detailed render mesh as authoritative collision.

Provide triangle counts, UV layouts, solid/wireframe turntables, LOD comparison renders, and the collision proposal. Stop for approval.
~~~

---

# Gun Section G5 — Materials, Skin Masks, Decals, and Themed Variants

## Prompt for Fable 5

~~~text
Create the production weapon materials and approved gun-customization system.

SUPPORTED CUSTOMIZATION
- Primary color
- Secondary color
- Accent color
- Emissive color
- Patterns
- Decals and stickers
- Material finishes
- Special skins
- Full themed model variants

Requirements:
- Sample the approved concept palette.
- Use the same polished toy-like PBR language as the mascots.
- Use moderate roughness, controlled specular highlights, subtle surface variation, and restrained emission.
- Avoid realistic gunmetal, heavy grime, wet plastic, flat unlit color, or uncontrolled bloom.
- Create reusable mask channels and stable Godot shader/material parameter names.
- Do not duplicate full texture sets for simple recolors.
- Give decals safe placement zones and prevent inappropriate stretching.
- Keep runtime texture resolution appropriate for one close first-person weapon while preserving LOD efficiency.
- Themed model variants must preserve the authoritative main grip, support grip, muzzle, aim point, ammunition socket, reload interface, collision envelope, and recognizable gameplay silhouette.
- Cosmetic changes must never alter accuracy, range, damage, reload duration, pickup rules, or hit detection.

Create proof content:
- Default approved skin
- One recolor preset
- One pattern
- One decal layout
- One alternate finish
- One restrained emissive variation

Show all proof skins in neutral studio light, gameplay lighting, and main-menu lighting. Confirm emission does not cause exposure glare. Stop for approval.
~~~

---

# Gun Section G6 — Rig, Moving Parts, Sockets, and Attachment Contract

## Prompt for Fable 5

~~~text
Create the gun's export hierarchy or compact armature and its standardized attachment contract.

Required markers/sockets:
- MainHandGrip
- SupportHandTarget
- Muzzle
- Aim/Sight
- AmmoSocket
- EjectionPoint if the approved mechanism uses one
- VFXOrigin
- AudioOrigin
- DropPivot
- FirstPersonOffset
- ThirdPersonAttachment
- MenuAttachment if a separate marker is genuinely required

Requirements:
- Rig or parent the trigger, chamber, chamber door/lever, ammunition, indicator, muzzle assembly, and other approved moving parts.
- Keep animation controls separate from exported deformation/moving-part bones where useful.
- Use clean bone/object axes, origins, scales, and naming.
- Store weapon-specific offsets in one data-driven weapon definition rather than scattered character scripts.
- Keep the right hand as the authoritative grip unless the existing project uses another established convention.
- Ensure the approved Blue Cat can use both main and support targets without wrist distortion.
- Maintain compatibility with later mascot hand-pose and IK/retargeting work.
- Do not change gameplay hitboxes or weapon rules.

Provide hierarchy documentation, a socket visualization, moving-part control demonstration, and an isolated Godot import test. Stop for approval.
~~~

---

# Gun Section G7 — Weapon Animation Set

## Prompt for Fable 5

~~~text
Create the final weapon-side animation set using the approved adjustable reload mechanism, currently configured for a two-second total duration.

Required weapon animations/states:
- Equip
- Pickup
- Loaded_Idle
- Empty_Idle
- Aim
- Fire
- Recoil
- Reload_Start
- Chamber_Open
- Ammo_Remove or Eject if applicable
- Ammo_Insert
- Chamber_Close
- Reload_Complete
- Empty_Trigger_Attempt
- Disarmed_Drop
- Ground_Impact response or compatible state
- Menu_Showcase
- Optional Inspect animation only if it does not delay required production

Requirements:
- The current default reload timeline must total two seconds at normal gameplay playback, while reading its authoritative duration from the gameplay configuration rather than permanently baking the value into the asset.
- Separate the animation into Open, Condense, Insert/Settle, and Close phases. Preserve readable mechanical timing when the configured duration changes.
- Use clear anticipation, readable motion, recoil, mechanical follow-through, and settle.
- Make loaded and empty states visually distinct but not distracting.
- Add standardized event markers compatible with the project, including Fire, MuzzleFlash, AmmoDetach, AmmoAttach, ChamberOpen, ChamberClose, ReloadComplete, Drop, and Impact where relevant.
- Gameplay code remains authoritative. Animations respond to state and event timing but do not independently grant ammo, deal damage, or decide reload success.
- Keep all sockets stable through animations unless their approved moving part intentionally changes.
- Confirm cosmetic themed variants can reuse the animation contract.

Demonstrate the complete weapon animation reel in Blender and the isolated Godot test scene. Stop for approval.
~~~

---

# Gun Section G8 — Firing, Reload, Status VFX, and Audio Hooks

## Prompt for Fable 5

~~~text
Create or connect the visual-effect and audio-event hooks required by the final weapon without replacing unrelated gameplay systems.

Required hooks:
- Muzzle flash
- Projectile/bullet trail origin
- Fire recoil impulse reference
- Loaded indicator
- Empty indicator
- Reload start and completion
- Approved ammo insertion/ejection effect
- Impact-effect selection hook
- Drop/ground-impact hook
- Optional subtle idle light
- Fire, empty, reload, mechanism, pickup, drop, and impact audio events

Requirements:
- Reuse suitable existing project effects and audio where available.
- If final audio is unavailable, create named hooks and clearly labeled temporary development placeholders rather than unlicensed final assets.
- Effects must remain readable but brief and must not obscure players or the one-shot projectile.
- Emission and bloom must be restrained under every map environment and menu lighting setup.
- Weapon skins may customize approved effect colors only within combat-readability limits.
- Cosmetic effects cannot change gameplay timing or authority.
- Networked effects must trigger from the existing authoritative gameplay events.

Provide effect previews under representative bright and dark maps plus the main menu. Stop after the hooks and visual limits are validated.
~~~

---

# Gun Section G9 — Godot Gameplay, First-Person, World, Pickup, and Drop Integration

## Prompt for Fable 5

~~~text
Integrate the approved final gun into the existing Godot weapon system.

First inspect whether the project uses:
- A separate first-person viewmodel
- A full-body first-person character
- One shared gun scene
- Separate first-person and world scenes
- Existing weapon animation, pickup, drop, networking, and save interfaces

Requirements:
- Preserve the existing authoritative rules: one-round capacity, one-shot firing, one-shot kill behavior, currently configured two-second reload, pickup ownership, disarm drop, gun persistence at the drop location, damage, and networking.
- Replace only the temporary visual asset through the project's intended interface.
- Connect LODs, materials, skin data, animations, sockets, effects, and audio hooks.
- Use simple authoritative collision and pickup shapes separate from render meshes.
- Verify correct first-person FOV/framing without clipping the camera.
- Verify third-person attachment and support-hand targets.
- Verify world pickup visibility and readable orientation.
- Verify disarmed drop behavior and stable resting orientation without unrealistic bouncing or tunneling.
- Verify that changing the configured reload duration correctly retimes the phased animation without changing gameplay authority.
- Verify menu and winner-podium presentation.
- Ensure the high-detail viewmodel does not force distant players to render first-person detail.
- Do not rewrite combat or network logic merely to accommodate the asset.
- Report every gameplay-facing file changed and why.

Demonstrate firing, empty state, the current two-second reload, at least one alternate test duration, pickup, ownership, disarm, drop, repickup, menu display, and podium display. Stop for integration approval.
~~~

---

# Gun Section G10 — Cross-Mascot Proxy Test and Final Gun Approval Gate

## Prompt for Fable 5

~~~text
Perform the final gun approval review before mascot rigging and animation resume.

Test the approved gun with:
- The approved Blue Cat hands/body
- Cat/Fox/Raccoon proportion proxy
- Panda/Bear proportion proxy
- Frog proportion proxy
- Penguin proportion proxy
- Axolotl proportion proxy

Verify:
- Main-hand grip
- Trigger reach
- Support-hand target reach
- Wrist comfort
- Face and body clearance
- First-person framing
- Third-person readability
- Menu pose
- Muzzle and aim alignment
- Reload-part reach
- Socket stability
- Skin/material behavior
- LOD quality
- Loaded/empty readability
- Correct reload at the current two-second default plus one alternate-duration test
- Pickup, fire, drop, disarm, and network behavior
- Controlled emission and bloom

Provide:
- Fixed concept-comparison renders
- High-quality turntable
- Wireframe and LOD comparison
- Blue Cat hold and reload test
- All proxy grip tests
- First-person and third-person captures
- Skin proof sheet
- Weapon animation reel
- Godot gameplay demonstration
- Editable Blender source and helper scripts
- Exported Godot assets
- Exact file list
- Remaining mismatches and reasons

Stop at Hard Gate B. Fable cannot approve its own gun and cannot resume mascot Section 8 until the user explicitly approves the final weapon.
~~~

---

# HARD GATE B — Approve the Final ONE GUN Weapon

The user must explicitly approve the final weapon after Gun Section G10.

After approval:

- The final weapon becomes the authoritative visual asset for all remaining grip, rig, animation, menu, podium, and customization work.
- Fable resumes at mascot **Section 8 — Player Customization Architecture**.
- Placeholder guns are forbidden unless used in an isolated test clearly unrelated to production.
- Changes to the final gun's main grip, support target, muzzle, aim point, reload mechanism, or scale require impact review against approved character work.

---

# Section 8 — Player Customization Architecture

## Prompt for Fable 5

```text
Design and implement the reusable player-customization foundation using the approved Blue Cat visual asset and the final weapon approved at Hard Gate B. Do not build the customization menu UI unless an existing UI requires a minimal test panel.

APPROVED CUSTOMIZATION CATEGORIES
- Mascot selection
- Full character skins
- Primary, secondary, belly/muzzle, marking, accent, eye, and detail colors
- Body patterns, including species-appropriate stripes, spots, patches, face markings, and tail markings
- Headwear
- Face accessories
- Neck accessories
- Upper-body clothing
- Lower-body clothing
- Hand accessories/gloves
- Footwear
- Back accessories
- Species-specific accessories
- Gun skins, colors, patterns, materials, decals, and themed models
- Melee weapon selection and cosmetic skins, colors, decals, hit effects, and swing trails
- Throwable appearance and trail
- Shield model, colors, emblem, and activation effect
- Idle animation style
- Victory animation
- Emote loadout
- Podium poses
- Defeat animation
- Spawn, elimination, footstep, muzzle, projectile, and melee effects
- Player nameplate, player icon, banner, badges, and titles

TECHNICAL REQUIREMENTS
- Create a data-driven CharacterAppearance or project-appropriately named Resource that stores stable cosmetic IDs and color values rather than fragile direct file paths.
- Create a cosmetic catalog mapping IDs to PackedScenes, materials, icons, compatibility rules, unlock metadata hooks, and safe defaults.
- Define standardized BoneAttachment3D or equivalent attachment points for Head, Face, Neck, Chest, Back, RightHand, LeftHand, Hips, Feet, Tail/Species, Weapon, Shield, and VictoryProp as applicable.
- Universal accessories such as hats, glasses, backpacks, and weapon skins should use shared attachment conventions.
- Clothing that must deform with the body must use character-specific meshes or documented body-fit groups. Do not force one shirt or pair of pants to fit the frog, penguin, bear, and cat without dedicated fitting.
- Define body-region hide masks so clothing can hide covered body surfaces and prevent clipping.
- Accessories must not change gameplay collision or hitboxes.
- Cosmetic effects must have visibility, brightness, and duration limits so they cannot obscure combat.
- Keep runtime material instances isolated per customized character so one player's colors do not change every player.
- Create save/load serialization hooks using stable IDs and safe fallbacks for missing cosmetics.
- Create multiplayer serialization that sends only validated cosmetic IDs, palette values, and equipped option IDs. Do not send arbitrary resource paths.
- Provide compatibility filtering so invalid species/item combinations fall back safely.
- Design for LOD and disabling expensive cosmetic effects at distance.

PROOF ITEMS
Create a small set of temporary development cosmetics to prove the system:
- One recolor preset
- One pattern
- One universal hat
- One face accessory
- One back accessory
- One character-specific clothing item
- One gun recolor/skin
- One alternate idle or victory selection reference

These proof items are validation assets, not final store content. Demonstrate save/load, character re-instancing, and two differently customized characters visible simultaneously without shared-material contamination. Stop after the customization foundation works.
```

---

# Section 9 — Shared Skeleton and Export Rig

## Prompt for Fable 5

```text
Build the Blue Cat authoring rig and the clean shared mascot export skeleton.

Requirements:
- Use one consistent bone hierarchy, naming standard, local-axis convention, and rest-pose convention that can be reused across all eight mascots.
- Keep the exported deformation skeleton near the concept target of approximately 65–75 bones where practical. The Blender control rig may contain additional non-exported controls.
- Include root, hips, multiple spine bones, chest, neck, head, arms, forearms, hands, simplified chunky fingers/thumbs as approved, legs, feet, toes, eye controls/deformers, eyelid/brow/facial support where bones are used, ears, and tail.
- Include standardized optional appendage bones for fox/raccoon tails, bear/panda ears, penguin scarf/flipper needs, axolotl gills/tail, and other species-specific secondary motion. Unused bones may remain unweighted on characters that do not need them if this improves animation compatibility.
- Separate animator-friendly controls from the export/deform bones.
- Provide IK/FK controls for arms and legs, reliable foot locking, pole targets, hand posing, eye aim, head/neck control, tail/ear secondary controls, and weapon-hand alignment helpers.
- Keep scale clean and avoid negative or unapplied transforms.
- Ensure the export skeleton works with Godot's current retargeting/import system and the project's AnimationTree approach.
- Create standardized attachment/socket bones or compatible markers for weapon, support hand, head accessory, face accessory, neck, back, shield, throwable, and victory prop.
- Do not export control widgets, helper geometry, hidden reference meshes, or unnecessary control bones.

Provide a rig hierarchy diagram/list, control demonstration, exported-bone count, and a test GLB imported into an isolated Godot test scene. Stop before final weighting approval.
```

---

# Section 10 — Skin Weighting and Deformation Approval

## Prompt for Fable 5

```text
Complete and validate Blue Cat skin weighting. Automatic weights are only a starting point.

Create a deformation test action covering:
- Head turns and tilts
- Extreme eye and facial poses
- Arms overhead, forward, crossed, and behind
- Two-handed gun hold
- Bat, frying pan, stick, throwable, and shield poses
- Deep elbow bends
- Wrist rotation and hand grip
- Spine bend, twist, squash, and stretch
- Deep crouch
- Wide stance
- High knee lift
- Full knee bend
- Ankle flex and foot roll
- Jump squash
- Landing compression
- Tail, ear, and secondary motion extremes

Correct:
- Collapsing shoulders or hips
- Pinched elbows and knees
- Twisted candy-wrapper wrists or ankles
- Floating or sliding feet
- Collapsing belly or muzzle
- Eyelid and eyeball intersections
- Broken finger grips
- Tail kinks
- Volume loss during squash and stretch
- Clothing/accessory test clipping

Use corrective shape keys only where clean weighting and topology cannot solve the deformation. Ensure correctives export reliably to Godot.

Provide a deformation-test recording in Blender and the imported Godot test scene performing the same action. Stop until deformation quality is approved.
```

---

# Section 11 — Weapon, Item, and Hand-Grip System

## Prompt for Fable 5

```text
Integrate the approved Blue Cat rig with the final ONE GUN weapon approved at Hard Gate B and the existing melee, throwable, and shield assets. Do not substitute the earlier temporary gun.

Required held-item categories:
- The ONE GUN firearm
- Baseball bat or existing melee bat
- Frying pan
- Stick as melee and throwable
- Shield item
- Existing generic throwables where available

Requirements:
- Inspect the existing weapon origins, grips, sockets, and gameplay attachment code before changing anything.
- Establish consistent grip markers on items without destructively changing gameplay models.
- Use the right hand as the authoritative main grip unless the current game uses another convention.
- Support reliable left-hand placement for two-handed gun poses.
- Create reusable hand-pose actions or pose assets for gun, bat, pan, stick, throwable, shield, relaxed, fist, and open hand.
- Prevent fingers from penetrating grips and prevent props from floating away from the palms.
- Make weapon alignment work in Blender review renders and in Godot BoneAttachment3D nodes.
- Keep gameplay hitboxes and weapon logic separate from the visible character mesh.
- Cosmetic weapon skins must not alter authoritative hitboxes or attachment transforms.
- Document any weapon-specific offset required and store it in data rather than scattered hard-coded transforms.

Provide close-up grip renders and an in-engine item-cycle test. Stop after all current item types align correctly.
```

---

# Section 12 — Core Locomotion Animation Library

## Prompt for Fable 5

```text
Create the Blue Cat core locomotion animation library. These animations establish the shared timing and quality standard for every mascot.

Required animations:
- Idle_Base loop
- Idle_Variation_01
- Walk_Forward
- Run_Forward
- Sprint_Forward if the game distinguishes it
- Move_Backward
- Strafe_Left
- Strafe_Right
- Turn_Left
- Turn_Right
- Jump_Anticipation/Start
- Jump_Airborne loop
- Land_Light
- Land_Heavy
- Crouch or low stance if currently supported
- Stun loop if required by current gameplay

Animation requirements:
- Gameplay locomotion must be in-place and controlled by Godot movement code.
- Match existing gameplay speeds through playback/blending rather than changing movement values.
- Use clear anticipation, smooth arcs, squash and stretch, body lean, counter-rotation, follow-through, and short settle motion.
- Keep feet planted during contact phases and eliminate visible sliding at the intended playback speeds.
- Use subtle ear, tail, cheek, and body overlap without making the character floppy.
- Maintain a readable silhouette from gameplay camera distances.
- Preserve weapon-ready compatibility so locomotion can blend with upper-body item poses.
- Author at an appropriate consistent frame rate, such as 30 FPS animation timing with smooth engine interpolation, unless existing project standards require another value.
- Standardize loop start/end poses and action names.
- Add documented animation event markers for foot contacts, jump commit, airborne transition, and land contact where the existing system supports them.

Demonstrate the complete locomotion set in Blender and through the actual Godot AnimationTree at representative game speeds. Stop for approval.
```

---

# Section 13 — Combat, Gun, Melee, Throwable, Shield, and Reaction Animations

## Prompt for Fable 5

```text
Create the Blue Cat gameplay action animations using the existing ONE GUN rules and weapon assets.

Required actions where supported by current gameplay:
- Pick_Up_Gun
- Gun_Hold_Idle
- Gun_Aim
- Gun_Fire and recoil
- Gun_Reload matching the game's configured reload duration, currently two seconds
- Gun_Drop/Disarmed reaction
- Melee_Equip
- Melee_Hold
- Bat_Swing
- Pan_Swing
- Stick_Swing
- Throw_Windup
- Throw_Release
- Shield_Equip
- Shield_Hold
- Shield_Hit reaction
- Normal_Hit reaction
- Knockback reaction
- Stun reaction
- Disarm reaction
- Defeat/Eliminated

Requirements:
- Use anticipation, strong readable attack silhouettes, impact recoil, follow-through, and recovery.
- Keep authoritative hit detection and damage in gameplay code. Animation events may mark intended windows but must not independently decide hits.
- Add standardized markers such as AttackCommit, HitWindowOpen, HitWindowClose, ThrowRelease, PickupAttach, GunDrop, Fire, ReloadComplete, and FootContact where compatible with the existing system.
- A thrown melee weapon must use the appropriate throw animation without implying a successful disarm.
- Weapon tier or gameplay-speed variations must preserve approved balance and timing.
- Keep the gun and melee grips stable throughout actions unless intentionally released.
- Avoid stiff torso-only swings. Use hips, spine, shoulders, head focus, feet, ears, and tail to sell the action.
- Keep animations safe for multiplayer replication and interruption by gameplay state changes.
- Create clean transitions back to locomotion and held-item states.

Demonstrate each action in Blender and Godot with the real items. Stop after combat animation quality and timing are approved.
```

---

# Section 14 — Emotes, Facial Acting, Victory, Podium, and Menu Animations

## Prompt for Fable 5

```text
Create the Blue Cat's expressive non-combat animation set and connect it to the customization architecture.

Required animations/poses:
- Happy
- Focused
- Surprised
- Taunt
- Sad
- Angry
- Victory_Default
- At least one alternate Victory proof animation
- Defeat_Default
- Podium_First
- Podium_Second
- Podium_Third
- MainMenu_Pedestal_Idle
- PlayerPreview_Idle
- Emote_Wave or another simple proof emote

Requirements:
- Coordinate face, eyes, eyebrows, ears, head, torso, hands, feet, and tail.
- Avoid body animation with a frozen face or facial animation on a frozen body.
- Use asymmetric poses, clear lines of action, anticipation, overshoot, follow-through, and settle.
- The first-place pose must support holding the gun.
- Second- and third-place poses must support the selected melee weapon where the current end-screen design requires it.
- The main-menu idle must remain subtle, loop cleanly, keep the feet planted, and maintain the weapon pose.
- Emotes must not alter gameplay position or collision.
- Connect animation selections through stable customization IDs so alternate idles, victories, podium poses, defeat animations, and emote loadouts can be saved and replicated.

Provide a complete expression/emote reel and an in-Godot pedestal/podium demonstration. Stop for approval.
```

---

# Section 15 — Blue Cat Personality Animation Pass

## Prompt for Fable 5

```text
Apply the Blue Cat's approved personality to the shared animation foundation without changing gameplay timing.

Personality target:
- Quick and curious
- Balanced all-around
- Friendly but competitive
- Alert eyes and ears
- Confident with weapons without appearing aggressive at rest

Requirements:
- Add small curious head and eye movements to idle variations.
- Use balanced stride length, moderate bounce, controlled landings, and readable anticipation.
- Let ears and tail react to movement, impacts, surprise, focus, and victory.
- Use facial focus during aiming and attacks.
- Preserve shared locomotion durations and action timing so the Blue Cat gains no gameplay advantage.
- Store personality variations as character animation overrides, additive layers, or project-appropriate animation resources rather than duplicating the entire controller logic.

Provide a side-by-side reel showing the neutral shared motion and the final Blue Cat personality version. Stop after approval.
```

---

# Section 16 — Godot Character Scene and AnimationTree Integration

## Prompt for Fable 5

```text
Integrate the completed Blue Cat into the actual Godot character architecture without replacing unrelated gameplay systems.

Requirements:
- Import LOD meshes, skeleton, skin, blend shapes, materials, animations, and attachment points with documented import settings.
- Create a dedicated Blue Cat character scene that connects to the existing player controller through the project's intended visual-character interface.
- Keep gameplay collider and authoritative movement separate from the cosmetic mesh.
- Configure the AnimationTree/state machine for locomotion, airborne states, held-item overlays, attacks, reactions, emotes, defeat, and menu/podium modes.
- Blend movement direction and speed smoothly.
- Support animation interruption rules required by firing, disarm, stun, knockback, defeat, and round transitions.
- Connect standardized animation events to existing gameplay hooks without moving gameplay authority into the animation asset.
- Connect facial expressions, eye aim, blink behavior, and menu/emote playback.
- Connect customization colors, skins, accessories, weapon cosmetics, and animation selections.
- Ensure character material instances are unique where customization requires them.
- Preserve current network ownership and replication behavior.
- Provide safe defaults if customization or an optional cosmetic is missing.
- Do not expose editor-only control rig components in the runtime scene.

Test local play, available bots, multiplayer replication if the test environment supports it, the main-menu pedestal, and the end-screen podium. Report every changed gameplay-facing file and why it was necessary. Stop after integration is stable.
```

---

# Section 17 — Performance, LOD, and Ten-Player Stress Test

## Prompt for Fable 5

```text
Optimize and stress-test the Blue Cat character system without visibly degrading the approved close-view model.

Requirements:
- Test at least ten visible mascot instances using different recolors and proof accessories.
- Measure triangle counts, draw calls, material instances, skeleton cost, blend-shape cost, animation cost, texture memory, particles, and accessory overhead.
- Activate LODs at distances that preserve silhouette and facial readability.
- Reduce or disable facial updates, secondary animation, expensive cosmetic effects, and high-detail accessories at distance where safe.
- Keep main-menu and podium characters at appropriate high detail.
- Avoid creating unique full texture copies for simple color changes.
- Ensure discarded previews, character swaps, and returning to menus do not leak nodes, materials, animations, or GPU resources.
- Confirm cosmetic effects cannot create unbounded particle counts.
- Preserve stable frame pacing during ten-player movement and combat.
- Do not lower LOD0 quality merely to solve a distant-character problem.

Provide profiler measurements, the test scene, observed bottlenecks, optimizations made, and comparison screenshots of every LOD. Stop for approval.
```

---

# Section 18 — Blue Cat Final Approval Gate (HARD GATE C)

## Prompt for Fable 5

```text
Perform the final Blue Cat approval review. Do not begin another mascot.

Compare the latest Blender and Godot results directly against every relevant area of the supplied concept sheet.

Verify:
- Approximately 1.4-meter scale
- Head/body/limb/hand/foot/tail proportions
- Rounded silhouette with no faceting
- Large expressive eyes and functional eyelids
- Accurate muzzle, cheeks, ears, tufts, colors, and markings
- Premium soft toy-like materials
- Clean wireframe and deformation topology
- Stable rig, facial system, and extreme-pose deformation
- Gun, melee, throwable, and shield grips
- Complete locomotion, combat, reaction, emote, victory, podium, and menu animation sets
- Blue Cat personality pass
- Godot AnimationTree integration
- Saveable and network-ready customization data
- Proof recolor, pattern, accessories, clothing, gun skin, and animation selection
- LOD quality and ten-player performance
- Editable Blender source, export files, scripts, and documentation

Provide:
- Fixed front/side/back/three-quarter reference overlays
- High-quality turntable
- Wireframe and deformation reel
- Facial-expression reel
- Animation reel
- Godot gameplay, menu, podium, and customization demonstrations
- Exact list of source and runtime files
- Remaining mismatches with exact reasons

Stop and wait for explicit approval. The production of the Red Fox or any other mascot is forbidden until this gate is approved.
```

---

# Section 19 — Remaining Mascot Production Rules

## Prompt for Fable 5

```text
The Blue Cat has been explicitly approved. Prepare to produce the remaining mascots one at a time using the approved pipeline.

Rules:
- Each mascot receives its own approved front/side/back/three-quarter turnaround before modeling.
- Each mascot receives a unique mesh matching its species and silhouette. Do not merely stretch or recolor the Blue Cat mesh.
- Reuse the shared skeleton structure, bone names, action names, attachment points, material parameter names, customization data, AnimationTree interface, and export settings.
- Adjust bone lengths and skinning to fit each mascot while preserving retargeting compatibility.
- Keep shared gameplay animation timings identical.
- Create personality animation overrides without changing movement or combat balance.
- Create species-specific body-region masks, clothing fit profile, optional bones, accessory compatibility, and LODs.
- Retest weapons, items, face, extreme deformations, customization, and Godot import for every mascot.
- Stop after each mascot's complete approval gate before beginning the next.

Recommended order:
1. Red Fox
2. Raccoon
3. Panda
4. Bear
5. Green Frog
6. Penguin
7. Axolotl

This order builds similar mammal structures first, then moves into the most anatomically distinct silhouettes.

Report how the approved Blue Cat pipeline will be reused and what requires unique work for the next mascot. Stop before modeling the Red Fox.
```

---

# Section 20 — Red Fox Character Brief

## Prompt for Fable 5

```text
Produce the Red Fox through the complete approved mascot pipeline. Work through turnaround, blockout, finished model, retopology, face, materials, rig adaptation, weighting, animation retargeting, personality overrides, customization, LODs, Godot integration, and final QA. Stop at the Red Fox approval gate.

Visual target:
- Orange fox with a large expressive head
- Tall pointed ears with darker outer/inner details as shown
- Cream muzzle, cheeks, chest/belly, and tail tip
- Dark hands/forearms and lower legs/feet where shown
- Narrower, more agile silhouette than the Blue Cat
- Large readable eyes and a clever confident expression
- Full rounded tail with a clean cream tip
- Smooth polished toy finish, not realistic fur

Personality target:
- Clever and agile
- Fast-looking, alert, and slightly mischievous
- Quicker anticipation and sharper settles while preserving shared gameplay timing

Customization needs:
- Fox-specific ear and tail accessory compatibility
- Tail marking masks
- Correct fitting profile for clothing
- Shared universal accessories and weapon systems

Do not start the Raccoon until the Red Fox is explicitly approved.
```

---

# Section 21 — Raccoon Character Brief

## Prompt for Fable 5

```text
Produce the Raccoon through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- Gray body with darker limbs and ears
- Strong dark facial mask surrounding large expressive eyes
- Cream/light muzzle and belly regions as shown
- Rounded but slightly slimmer silhouette than the Panda
- Full striped raccoon tail
- Small alert ears and readable cheek shape
- Smooth toy finish with no realistic fur

Personality target:
- Sneaky and nimble
- Cautious posture, quick glances, light steps, and playful confidence
- Personality variation must preserve shared gameplay timing

Customization needs:
- Face-mask and tail-stripe color regions
- Tail and ear accessories
- Correct clothing fit profile
- Shared universal accessories and weapon systems

Do not start the Panda until the Raccoon is explicitly approved.
```

---

# Section 22 — Panda Character Brief

## Prompt for Fable 5

```text
Produce the Panda through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- White head and torso regions with black ears, eye patches, limbs, and approved markings
- Large rounded head and strong readable panda eye-mask shapes
- Sturdy, round, bottom-heavy body
- Short powerful limbs and broad feet
- Friendly expression capable of focused and competitive poses
- Smooth toy finish with no realistic fur

Personality target:
- Strong and sturdy
- Calm weight, planted poses, controlled momentum, and solid landings
- Preserve shared gameplay speed and action timing

Customization needs:
- Independent light/dark region recoloring while preserving readable face contrast
- Panda ear accessories
- Sturdy-body clothing fit profile
- Shared universal accessories and weapon systems

Do not start the Bear until the Panda is explicitly approved.
```

---

# Section 23 — Bear Character Brief

## Prompt for Fable 5

```text
Produce the Bear through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- Warm brown body
- Lighter tan muzzle, belly, and inner-ear regions
- Broad head, small rounded ears, strong muzzle, and friendly dark eyes
- Largest and heaviest-looking mascot silhouette
- Broad torso, thick limbs, chunky hands, and sturdy feet
- Smooth plush-toy-inspired form without simulated fur

Personality target:
- Tough and fearless
- Heavy anticipation, powerful follow-through, broad poses, and weighty settles
- Preserve shared gameplay speed and attack timing despite the heavier presentation

Customization needs:
- Bear-specific headwear fit
- Broad-body clothing fit profile
- Clear muzzle/belly recolor masks
- Shared universal accessories and weapon systems

Do not start the Green Frog until the Bear is explicitly approved.
```

---

# Section 24 — Green Frog Character Brief

## Prompt for Fable 5

```text
Produce the Green Frog through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- Bright green body with lighter belly/mouth region
- Large elevated rounded eyes with dark pupils and strong expression range
- Wide friendly mouth
- Compact torso with visibly springy legs
- Rounded fingers, hands, toes, and feet suited to the shared weapon grips
- Smooth toy/amphibian surface without wet glare or realistic skin bumps

Personality target:
- Bouncy and energetic
- Deep anticipation, springy arcs, quick compression, and lively landings
- Preserve shared gameplay timing and jump mechanics

Customization needs:
- Frog-specific eye/head accessory fitting
- Amphibian color and spot/pattern masks
- Frog body clothing fit profile
- Shared weapon sockets despite different hand proportions

Do not start the Penguin until the Green Frog is explicitly approved.
```

---

# Section 25 — Penguin Character Brief

## Prompt for Fable 5

```text
Produce the Penguin through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- Dark outer body with white face/belly region
- Small orange beak and orange feet
- Compact oval silhouette
- Short flipper-like arms adapted carefully for readable weapon handling
- Red scarf as a removable/customizable neck accessory, not permanently fused to the body
- Smooth toy finish

Personality target:
- Small and slippery
- Quick short steps, controlled waddling flavor, playful slides, and compact poses
- Preserve shared gameplay movement and action timing

Customization needs:
- Removable scarf and alternate neck accessories
- Penguin-specific upper-body/clothing fit
- Headwear fitted to the compact head
- Reliable two-handed gun solution despite flipper proportions
- Shared universal accessories where visually compatible

Do not start the Axolotl until the Penguin is explicitly approved.
```

---

# Section 26 — Axolotl Character Brief

## Prompt for Fable 5

```text
Produce the Axolotl through the complete approved mascot pipeline and stop at its final approval gate.

Visual target:
- Cheerful pink body with lighter belly region
- Large rounded head and simple friendly face
- Distinct external gill branches on both sides of the head
- Soft rounded tail and compact amphibian body
- Rounded hands and feet capable of shared item grips
- Smooth soft toy finish without wet realism

Personality target:
- Quirky, cheerful, and chaotic
- Playful head movement, energetic gill overlap, loose secondary motion, and surprising poses
- Preserve shared gameplay timing and clarity

Customization needs:
- Gill color and decoration regions
- Gill-safe headwear compatibility rules
- Tail and species-specific accessories
- Axolotl body clothing fit profile
- Secondary-motion limits that remain stable in multiplayer and at high movement speed

Do not begin roster-wide final QA until the Axolotl is explicitly approved.
```

---

# Section 27 — Full Roster Consistency and Retargeting QA

## Prompt for Fable 5

```text
Perform a complete roster consistency review after all eight mascots have individually passed approval.

Verify side by side:
- Every mascot is approximately 1.4 meters to its approved highest head feature unless a deliberate visual exception is documented
- Distinct silhouettes remain readable at gameplay distance
- Shared skeleton hierarchy, bone names, action names, sockets, and Godot interface
- Shared animation timing and gameplay fairness
- Clean animation retargeting without foot sliding, hand drift, facial failure, or prop misalignment
- Each mascot's personality variations
- Comparable material quality and controlled specular response
- Comparable eye, face, and expression quality
- Weapon, melee, throwable, and shield compatibility
- Universal accessory placement
- Species/body-fit clothing rules
- Customization masks and material parameters
- LOD consistency
- Ten-player mixed-roster performance
- Menu pedestal and podium presentation

Create a lineup scene matching the concept's readable front-facing presentation plus a full mixed-roster gameplay and animation test.

Do not homogenize the meshes to solve retargeting. Fix rig adaptation, weights, animation overrides, or sockets while preserving each approved silhouette.

Provide lineup renders, animation comparisons, customization examples, profiler results, and a list of remaining exceptions. Stop after roster approval.
```

---

# Section 28 — Complete Customization Catalog Validation

## Prompt for Fable 5

```text
Validate that the finished roster supports the complete approved customization catalog without requiring character-system redesign.

Test and document:
- Mascot switching
- Full skins
- All approved color regions
- Patterns and markings
- Head, face, neck, upper body, lower body, hands, feet, back, and species-specific slots
- Universal versus body-fit-specific accessories
- Body-region hiding and clipping prevention
- Gun, melee, throwable, and shield cosmetics
- Idle, victory, emote, podium, and defeat selections
- Spawn, elimination, footstep, muzzle, projectile, and melee effects
- Nameplate, icon, banner, badge, and title data
- Save/load and missing-content fallbacks
- Multiplayer replication and ID validation
- Ten uniquely customized players
- LOD behavior and effect limits

Create a compatibility matrix showing which slots are universal, fit-group-specific, or mascot-specific. Confirm that adding a new cosmetic normally requires data and assets rather than edits to core character code.

Do not build the final customization storefront or inventory UI unless separately requested. Stop after the architecture and runtime validation are complete.
```

---

# Section 29 — Final Production Delivery

## Prompt for Fable 5

```text
Prepare the approved ONE GUN mascot system for final handoff.

Deliver and verify:
- Editable versioned Blender source files for every mascot
- Editable high-resolution and game-ready Blender source for the final ONE GUN weapon
- Gun reference, mechanism, sockets, animations, skins, LODs, effects hooks, and Godot integration
- Reproducible helper/export scripts
- Approved turnaround and proportion references
- High-resolution source meshes and optimized LOD meshes
- UVs, textures, masks, material documentation, and palette definitions
- Shared authoring/export rig documentation
- Animation actions and animation library
- Facial shape/control documentation
- Weapon and accessory socket documentation
- Godot GLB imports and mascot scenes
- AnimationTree/controller integration
- Customization resources, catalog, compatibility data, and proof assets
- Save/load and multiplayer serialization hooks
- Performance and ten-player test scenes
- Final turntables, expression reels, animation reels, lineup renders, and Godot captures
- Asset licenses for any third-party material, font, texture, sound, or tool content used
- Exact list of modified gameplay-facing files and reasons

Run final project validation and confirm there are no missing resources, broken imports, orphan nodes, animation errors, invalid cosmetic IDs, shared-material contamination, or unrelated gameplay regressions.

Provide a concise final report with completed deliverables, test results, known limitations, and any future customization content that can now be added without architecture changes.
```

---

# Final Acceptance Standard

The roster is successful when:

- Every mascot reads immediately as its approved concept design.
- Characters are smooth, rounded, polished, expressive, and lively.
- No character resembles a crude primitive assembly or unfinished low-poly placeholder.
- The Blue Cat proves the complete pipeline before the remaining roster is built.
- Every character shares a compatible skeleton and gameplay animation interface while retaining a unique silhouette and personality.
- Animations use anticipation, arcs, squash and stretch, overlap, follow-through, facial acting, and clean settles without changing gameplay balance.
- The approved final gun works in first-person, third-person, pickup, drop, disarm, reload, menu, podium, skin, and multiplayer contexts.
- Gun, melee, throwable, shield, menu, podium, and emote requirements work in Godot.
- The complete approved customization system is supported from the beginning.
- Ten differently customized mascots remain readable and performant together.
- Blender source, Godot assets, documentation, renders, and validation evidence are preserved.
