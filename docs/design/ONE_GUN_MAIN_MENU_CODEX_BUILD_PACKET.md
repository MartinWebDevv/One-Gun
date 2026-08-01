# ONE GUN Main Menu — Codex Implementation Packet

## Purpose

Recreate the supplied main-menu concept as closely as possible in Godot while making these approved changes:

- The background is a **live 3D preview of an existing game map**.
- The active map preview changes automatically every **10 seconds**.
- The menu interface is a **2D Godot Control/CanvasLayer UI** over the 3D scene.
- Use the **existing player character and gun assets**. Do not create or replace those models yet.
- Remove **TOY BOX LEAGUE** from the logo.
- Remove the **TOY BOX ARENA** sign and all other Toy Box wording.
- Preserve the concept's composition, scale, color hierarchy, materials, lighting, depth, and presentation as closely as the available game assets allow.

## Codex Operating Rules

Codex should work directly inside the existing ONE GUN repository. It must inspect before editing, preserve unrelated user changes, implement rather than only explain, and verify each completed section before stopping. It may use Godot, Blender, command-line tools, and reproducible Blender Python scripts available in the environment.

For every section, Codex must:

- Read applicable project instructions such as AGENTS.md and existing development documentation first.
- Inspect git status and preserve unrelated or pre-existing changes.
- Reuse existing project structure and assets before creating replacements.
- Make only the changes required by the current section.
- Run the safest relevant Godot validation, script parsing, project startup, or automated checks available.
- Visually inspect the running menu or captured screenshot whenever the section changes appearance.
- Never claim a 1:1 visual match without comparing a fresh capture against the supplied concept.
- Report the exact files changed, validation performed, result, and any blocker.
- Stop after the requested section so the user can approve it before the next section begins.

## How to Use This Packet

Give Codex access to the ONE GUN repository, the reference image, and this file. Send the prompts below **one at a time and in order**. Review each completed section in Godot before sending the next prompt.

The supplied concept is a 16:9 image. Use **1920×1080** as the primary matching resolution while supporting other 16:9 and common desktop resolutions.

---

# Section 0 — Permanent Project Rules

## What This Controls

These are the non-negotiable rules Codex should follow through the entire build.

## Prompt for Codex

```text
You are rebuilding the ONE GUN main menu from the supplied concept art inside the existing Godot project. Treat the concept art as the visual composition target, not as permission to replace existing game systems.

Permanent rules for every step:
1. Use Godot's live 3D renderer for the background, character, gun, pedestal, lighting, particles, and map previews.
2. Build the interactive menu as Godot 2D Control nodes in a CanvasLayer above the 3D scene.
3. Use the existing player character and gun assets. Do not model, redesign, or permanently modify either asset.
4. The background must show live previews of existing maps and rotate to a different map every 10 seconds.
5. Remove all TOY BOX LEAGUE and TOY BOX ARENA wording. Do not add substitute Toy Box branding.
6. Preserve the supplied concept's left-panel/right-showcase composition, premium toy-like materials, warm cinematic lighting, rounded bevels, depth, and strong color hierarchy.
7. Do not modify unrelated gameplay, networking, combat, map, save, or character scripts.
8. Reuse existing project conventions, autoloads, input actions, theme resources, and folder structure where practical.
9. Before editing, inspect the project and identify the Godot version, renderer, main-menu files, map scenes, player scene, gun scene, UI theme/fonts, autoloads, and current navigation methods.
10. Keep all new menu-specific code modular and typed where the existing code style supports it.
11. Do not continue into later packet sections unless I explicitly give you the next prompt.

Start by reporting the assets and systems you found, the relevant existing git status, the files you expect to create or edit, and any genuine blockers. Then implement only the section I provide. Do not stop at a plan when implementation is possible.
```

---

# Section 1 — Overall Screen Composition and Scene Architecture

## Visual Breakdown

The concept divides the screen into two major zones:

- **Left 35%:** a tall, dark navy menu cabinet with a metallic gold outer rim.
- **Right 65%:** the live 3D map preview and centered player showcase.

At 1920×1080, use the concept's approximate proportions:

- Left panel begins about **3.1% from the left edge**.
- Panel top and bottom margins are about **2.3%**.
- Panel width is about **32.5% of the screen**.
- The character/pedestal visual center is around **65% of screen width**.
- The bottom of the pedestal sits around **89% of screen height**.

The 3D scene fills the entire screen behind the interface. The left panel is opaque enough to remain readable while the right half stays visually dominant.

## Prompt for Codex

```text
Implement the main-menu scene foundation and match the supplied concept's overall composition.

Requirements:
- Create or refactor a dedicated MainMenu scene with a live Node3D background and a CanvasLayer containing the 2D UI.
- The 3D background must fill the viewport edge to edge.
- Create a left UI panel whose reference layout is approximately x=3.1%, y=2.3%, width=32.5%, height=95.4% of a 16:9 viewport.
- Keep the remaining right side unobstructed for the live map, character, gun, and pedestal.
- Place the 3D showcase center at approximately 65% of the screen width and the pedestal base near 89% of screen height when viewed at 1920×1080.
- Use anchors and containers so the layout remains stable at 1280×720, 1600×900, 1920×1080, 2560×1440, and ultrawide screens. Preserve the intended 16:9 composition inside a safe area on ultrawide displays rather than stretching it.
- Establish clear nodes or components for MapPreviewHost, CharacterShowcase, Pedestal, MainMenuUI, LogoArea, ButtonList, and StatusFooter.
- Add temporary debug guides that can be toggled from the inspector to show the target panel rectangle and showcase center. Disable them by default in the finished scene.
- Do not build the detailed panel art or buttons yet. Use simple temporary blocks so we can confirm the composition first.

Run the scene at 1920×1080 and provide a screenshot plus a concise list of created and edited files. Stop after the composition and architecture are working.
```

---

# Section 2 — Live 3D Map Preview Background and 10-Second Rotation

## Visual Breakdown

The reference background is a colorful arena with strong depth:

- Foreground ground plane is sharp enough to read.
- Midground architecture frames the character.
- Distant background is softer and less contrasty.
- Warm highlights come from the upper-right.
- The background supports the character rather than competing with it.

The final version replaces the pictured arena with previews of the game's actual maps. Each preview should feel like the same menu even when its environment changes.

## Prompt for Codex

```text
Build the live map-preview system for the main menu.

Requirements:
- Inspect the existing map scenes and choose the safest method to display them without starting a match or running gameplay-only systems.
- Prefer lightweight menu-preview variants or an explicit preview mode that disables networking, round logic, AI, damage, pickups, match UI, player spawning, and unnecessary physics processing.
- Create a reusable preview configuration for each supported map. Each entry should identify the map scene, a menu camera transform or marker, optional look-at target, environment override, and optional showcase/pedestal placement marker.
- Never hard-code a single map path directly into the switching script. Use exported resources, an inspector array, or another project-consistent data structure.
- Display the first preview immediately when the main menu opens.
- Automatically switch to the next preview every exactly 10 seconds, loop after the final map, and avoid immediately repeating the same map when more than one exists.
- Use threaded/asynchronous resource loading if supported by the current project and Godot version so switching does not freeze the menu.
- Hide scene replacement with a polished 0.6–1.0 second transition. Prefer a subtle darkened crossfade or full-screen fade that keeps the UI stable and does not flash an empty viewport.
- Keep the map live: retain appropriate ambient animation, moving props, particles, water, foliage, or environmental motion, but disable expensive or distracting gameplay activity.
- Do not show map names unless the existing project already requires them.
- Add pause/resume behavior so the 10-second timer and unnecessary preview processing pause when the menu is not visible.
- Cleanly free the previous preview after the transition and confirm that repeated cycling does not leak nodes, resources, audio, or viewports.
- Do not place TOY BOX ARENA or any Toy Box wording in any preview.

Verify at least three consecutive automatic transitions, or every available map if fewer than three exist. Report which maps are configured, how preview mode disables gameplay, and the files changed. Stop after the map cycler works.
```

---

# Section 3 — Existing Character and Gun Showcase

## Visual Breakdown

The reference character is the focal point:

- Full body visible from ears/head to feet.
- Character faces mostly forward with a slight three-quarter turn.
- Gun is held diagonally across the torso and remains easy to read.
- Character occupies roughly the central-right third of the screen.
- Silhouette is clean against the background.
- Pose feels confident, friendly, and ready for play.

The current game character and gun replace the concept's blue cat and toy blaster for now.

## Prompt for Codex

```text
Add the existing ONE GUN character and gun to the main-menu showcase without creating new character or weapon models.

Requirements:
- Locate and instance the existing player character and gun scenes through a dedicated menu showcase wrapper. Do not permanently alter the gameplay versions.
- Disable gameplay scripts, collision, damage, networking, input capture, camera control, and weapon firing while they are displayed in the menu.
- Present the character full body on the right side, centered near 65% of screen width, standing on the pedestal location established earlier.
- Match the reference pose as closely as the existing rig allows: mostly front-facing, slight three-quarter body rotation, feet planted, and gun held diagonally across the torso.
- If an appropriate existing idle or weapon-hold animation exists, use it. If none exists, create only a menu-specific AnimationPlayer/AnimationTree setup or non-destructive pose override. Do not rewrite the gameplay animation state machine.
- Add a subtle menu idle: gentle breathing, tiny weight shift, occasional head movement, and very small weapon motion. Keep the feet locked and avoid exaggerated movement.
- If the existing game supports player-selected characters or loadouts, show the currently selected character and gun through the existing save/profile system. Otherwise use the current default assets through exported scene references.
- Ensure the character and gun receive the menu lighting and cast controlled contact shadows onto the pedestal.
- Use a rim or edge light to separate the silhouette from every cycling map background.
- Preserve readable framing at all target resolutions. Do not let the character overlap the left menu panel.

Run the menu using the current assets and provide a screenshot at 1920×1080. Report any limitations caused by the current rig, pose, or gun attachment. Stop after the showcase is stable.
```

---

# Section 4 — Trophy Pedestal

## Visual Breakdown

The pedestal grounds the character and provides the main foreground prop:

- Low, wide, circular display platform.
- Dark bronze/black base with stepped beveled rings.
- Bright warm-gold illuminated ring around the upper edge.
- Dark top surface divided into subtle radial panels.
- Front plaque with rivets, beveled gold trim, star accents, and the words **ONE GUN TROPHY**.
- Strong contact shadow anchors it to the map floor.

## Prompt for Codex

```text
Create and integrate the trophy pedestal shown in the concept art. This is a new menu prop; do not modify the existing character or gun assets.

Requirements:
- First search the project for a suitable existing podium/pedestal. Reuse it if it can reach the target look cleanly. Otherwise create a new optimized model in Blender, preferably with a reproducible Python script stored with the source asset.
- Build a low, broad, circular pedestal with 2–3 stepped beveled tiers, a dark bronze/near-black body, a raised top deck, and a front-facing plaque.
- Add a continuous warm-gold illuminated ring below the top deck. Use restrained emission plus actual lighting or baked support so it glows without clipping to flat yellow.
- Give the top surface subtle radial panel segmentation and enough roughness variation to read under cinematic lighting.
- Add a beveled front plaque with gold trim, four visible fasteners/rivets, small star accents, and centered text reading ONE GUN TROPHY.
- Keep the lettering readable at 1920×1080 but avoid making the plaque taller than the reference.
- Use physically plausible materials: dark painted/oxidized metal body, brushed gold/brass trim, slightly worn edges, and no photorealistic grime.
- Add modest bevels so highlights define every tier. Avoid razor-sharp edges.
- Optimize topology and material count for real-time Godot use. Generate sensible UVs and use project-consistent texture sizes.
- Import the asset into Godot with correct scale, transforms, material settings, and collision disabled unless a menu-specific simple collider is required.
- Center the existing character on the platform with feet contacting the top surface. The pedestal should occupy roughly 39% of screen width and sit near the bottom center-right, matching the concept.

Provide the Blender source/script if a new model was created, the exported game asset, and a 1920×1080 menu screenshot. Stop after the pedestal closely matches the reference.
```

---

# Section 5 — Camera, Lighting, Environment, and Depth

## Visual Breakdown

The concept uses a polished, cinematic toy-commercial look:

- Warm key light from the upper-right.
- Cooler blue fill from the left/front.
- Bright gold pedestal lighting from below.
- Soft contact shadows.
- Bloom on practical lights and emissive materials.
- Background depth of field, with character and pedestal kept sharp.
- Mild vignette and high color saturation without crushed blacks.

## Prompt for Codex

```text
Match the concept art's camera, lighting, depth, and final image treatment across all cycling map previews.

Requirements:
- Use a perspective Camera3D and tune FOV/distance to create the reference's slightly compressed showcase look. Start around a 38–45 degree vertical FOV, then match by eye.
- Frame the full character, gun, and pedestal with the showcase centered near 65% of screen width. Keep comfortable space above the head and do not crop the pedestal plaque.
- Add a warm soft key light from high camera-right, a cooler low-intensity fill from camera-left/front, and a controlled rim light behind or above the character.
- Let the gold pedestal ring contribute a subtle warm upward glow.
- Use soft shadows and contact shadowing without noisy or overly dark results.
- Configure the project-appropriate WorldEnvironment for tasteful bloom/glow, tone mapping, ambient occlusion, color adjustment, fog if useful, and a very mild vignette.
- Apply depth of field so the character, gun, and front of the pedestal are sharp while the map background becomes progressively softer. Do not blur the 2D UI.
- Keep exposure and character readability consistent when maps rotate. Use per-map overrides only where needed, while retaining one shared menu lighting identity.
- Avoid uncontrolled auto exposure changes during transitions.
- Target the reference's colorful, cartoony, premium-toy finish rather than gritty realism.
- Check for overexposed gold, crushed navy UI blacks, transparent hair/material artifacts, shadow acne, and background lights that compete with the character.

Provide before/after screenshots at 1920×1080 for at least two different map previews. Stop after lighting and composition remain consistent across the map cycle.
```

---

# Section 6 — Left Menu Cabinet and Gold Frame

## Visual Breakdown

The left side resembles a physical premium toy cabinet:

- Tall rounded rectangle with a thick gold metallic outer border.
- Thin bright inner highlight and darker outer shadow.
- Deep navy/near-black inset face.
- Large corner radius.
- Subtle scuffs, small scratches, specks, and panel texture.
- Strong depth created by multiple nested borders rather than a flat rectangle.

## Prompt for Codex

```text
Build the 2D left menu cabinet to closely match the concept.

Requirements:
- Use Godot Control nodes and reusable StyleBoxFlat/StyleBoxTexture resources, shaders, or 9-slice textures. Do not implement the panel as a fixed-resolution screenshot.
- Match the established panel bounds: approximately x=3.1%, y=2.3%, width=32.5%, height=95.4% in a 16:9 reference layout.
- Create a thick rounded metallic-gold outer frame, a narrow dark separator, a thin warm inner highlight, and a deep navy inset face.
- Use a large corner radius equivalent to roughly 4–5% of the panel width.
- Add convincing bevel depth with restrained highlights along the upper-left and warm shadows along the lower-right.
- The gold should vary from amber/orange shadow to pale gold highlight. Avoid a flat yellow border.
- The inset should be nearly black navy, not pure black, with a faint center lift or gradient.
- Add very subtle scratches, specks, edge wear, or stamped texture. Keep it quiet enough that text remains clear.
- Give the entire panel a soft exterior shadow so it separates from the live 3D background.
- Keep the frame crisp at all target resolutions and avoid blurry scaling.
- Leave organized internal regions for LogoArea, ButtonList, and StatusFooter. Do not build those detailed elements in this step.

Provide a 1920×1080 screenshot with the panel over two different map previews so readability can be checked. Stop after the cabinet and frame match the concept.
```

---

# Section 7 — ONE GUN Logo Area

## Visual Breakdown

The concept logo occupies the upper portion of the panel:

- Large stacked **ONE / GUN** title.
- Chunky, rounded, slightly irregular 3D lettering.
- ONE uses warm white/cream faces with dark navy sides and shadows.
- GUN uses yellow-to-orange faces with darker orange sides.
- Star motif replaces or sits beside part of the top line.
- Strong extrusion and drop shadow make it feel like a physical toy logo.
- The former TOY BOX LEAGUE ribbon must not appear.

## Prompt for Codex

```text
Implement the ONE GUN logo area inside the top of the left menu cabinet.

Requirements:
- Use the approved standalone ONE GUN logo asset if one already exists in the project or design packet. If it does not exist, recreate only the logo treatment needed for the menu; do not add TOY BOX LEAGUE or any subtitle ribbon.
- Preserve the concept's two-line stack: ONE above GUN, large enough to dominate the upper panel without touching the gold frame.
- Match the chunky rounded dimensional lettering, dark navy extrusion/shadow, warm cream ONE faces, and yellow-to-orange GUN faces.
- Retain the star motif associated with the main title if it is part of the approved logo asset.
- Center the logo horizontally in the panel and use the space freed by the removed subtitle to give the logo comfortable separation from the first button.
- Maintain aspect ratio and use high-resolution/vector/SDF-safe rendering so the logo is crisp at 1440p and 4K.
- Add a restrained shadow or depth treatment so the logo appears mounted inside the cabinet rather than printed flat.
- Do not include TOY BOX LEAGUE, TOY BOX ARENA, or replacement subtitle text.

Show the completed logo area at 1920×1080 and 2560×1440. Stop after the logo scale, spacing, and clarity match the concept.
```

---

# Section 8 — Four Main Menu Buttons

## Visual Breakdown

The reference contains four large stacked buttons:

1. **LOCAL PLAY** — gold/orange
2. **ONLINE PLAY** — blue
3. **PLAYER SETTINGS** — purple
4. **QUIT GAME** — red

Each button has:

- Tall rounded rectangular body.
- Dark outer shadow and colored bevel.
- Brighter upper highlight and darker lower edge.
- Separate square-ish icon compartment on the left.
- Large bold white or dark title.
- Smaller uppercase subtitle.
- Small star emblem at the far right.
- Even vertical spacing.

## Prompt for Codex

```text
Build the four interactive main-menu buttons and match the concept's physical toy-button styling.

Button order and copy:
1. LOCAL PLAY — subtitle: SOLO • BOTS • SPLITSCREEN
2. ONLINE PLAY — subtitle: HOST OR JOIN A LOBBY
3. PLAYER SETTINGS — subtitle: AUDIO • VIDEO • CONTROLS
4. QUIT GAME — subtitle: SEE YA LATER

Requirements:
- Use reusable Godot Button-derived scenes or composed Control scenes rather than four unrelated copies.
- Create gold/orange, blue, purple, and red color variants while preserving the same dimensions, bevels, typography, and interaction behavior.
- Each button needs a rounded dark outline, saturated body gradient, bright top/inner highlight, darker bottom edge, subtle texture, and soft drop shadow.
- Create a left icon compartment separated by a vertical divider. Use clear icons matching the concept: play triangle, globe/network, gear/settings, and exit/door arrow.
- Add a small star emblem near the right edge as a decorative accent. It must not resemble a checkbox or favorite toggle.
- Titles should be bold condensed uppercase. Subtitles should be smaller uppercase with increased spacing and high contrast.
- Use the project's licensed fonts if suitable. If new fonts are required, use only assets whose license is compatible with commercial distribution and record their license in the project.
- Match the concept's button proportions: each button spans about 89% of the panel's inner width, with height around 9–10% of panel height and consistent gaps.
- Support mouse, keyboard, and controller focus. Ensure text and icons remain readable at 1280×720.
- Connect buttons to the project's existing navigation methods. Do not invent replacement gameplay flows. If a destination does not yet exist, connect to an explicit placeholder method that logs a clear message without breaking the menu.
- Quit must use the project's normal confirmation policy if one exists; otherwise quit only after activation, not on focus.
- Do not implement detailed hover/press animation yet; establish correct normal-state art, layout, focus order, and navigation.

Provide a screenshot of the normal state and confirm each button's destination or current placeholder. Stop after the button stack visually matches the concept.
```

---

# Section 9 — Button Focus, Hover, Press, and Input Feel

## Visual Breakdown

The concept is static, but the finished UI should feel like a polished physical toy interface. Interaction must reinforce the same beveled style without changing the layout.

## Prompt for Codex

```text
Add polished interaction states to the completed main-menu buttons.

Requirements:
- Mouse hover and keyboard/controller focus must use the same clear selected state.
- On focus/hover, slightly brighten the button, strengthen its gold/white edge highlight, raise it by only a few pixels, and add a subtle scale increase around 1.01–1.025. Do not cause neighboring buttons to shift.
- Add a restrained moving sheen or highlight sweep if it remains readable and inexpensive.
- On press, move the button inward/down slightly, reduce scale briefly, darken the lower bevel, and return with a quick spring-like easing.
- Animate the left icon and right star very subtly. Avoid constant spinning or distracting motion.
- Make transitions quick and responsive: approximately 0.08–0.15 seconds for press and 0.15–0.25 seconds for focus/hover.
- Use the existing UI audio library if suitable. Add a quiet hover/focus tick and a stronger confirm sound, but do not add unlicensed audio or duplicate sounds on simultaneous hover and focus events.
- Respect an existing reduced-motion or UI-volume setting if the project has one.
- When the menu opens, set focus to LOCAL PLAY for controller/keyboard users without showing an ugly default focus rectangle.
- Prevent focus from escaping into hidden controls. Navigation order must be Local, Online, Settings, Quit and wrap only if that matches the project's UI convention.
- Maintain correct behavior while a map-preview transition occurs.

Demonstrate mouse and controller/keyboard navigation. Stop after every state is polished and no button layout shifts occur.
```

---

# Section 10 — Bottom Player and Build Status Footer

## Visual Breakdown

The footer is a compact recessed strip at the bottom of the panel:

- Small player portrait at far left.
- Player/display name and green ready/online indicator.
- Secondary status line beneath.
- Thin vertical divider.
- Build number and playtest/version information at the right.

The concept displays an IP-like number, but the final menu should not expose a user's public or private IP address.

## Prompt for Codex

```text
Build the compact status footer at the bottom of the menu cabinet.

Requirements:
- Match the concept with a dark recessed rounded strip, thin navy/blue border, subtle inner highlight, and organized left/right information groups.
- Left group: show the current player's existing portrait/avatar if available, display name, and a small green status dot with a short state such as READY, ONLINE, or LOCAL.
- If the project has no player profile system yet, use a clearly labeled local placeholder resource that can later be connected without redesigning the footer.
- Do not display, calculate, or store the user's IP address.
- Use the secondary line for a safe useful value such as LOCAL PROFILE, OFFLINE, NOT SIGNED IN, or the existing project status.
- Add a thin vertical divider.
- Right group: display the real build/version string from the project's existing version source if available, plus PLAYTEST, ALPHA, DEVELOPMENT, or the project's actual channel.
- Do not hard-code the version in multiple places. Read it from one project-consistent source.
- Keep the footer visually quiet and smaller than the action buttons while remaining readable at 720p.
- Reuse the same cream, muted blue-gray, gold, and green palette visible in the concept.

Provide a screenshot and identify which values are live versus placeholders. Stop after the footer matches the reference layout.
```

---

# Section 11 — Ambient Motion and Menu Life

## Visual Breakdown

The menu should feel alive even when the player does nothing:

- Character performs a restrained idle.
- Map preview contains subtle environmental motion.
- Pedestal glow gently breathes.
- Tiny dust motes or particles catch the warm light.
- Camera is stable; any motion is nearly imperceptible.

## Prompt for Codex

```text
Add restrained ambient motion to the finished main-menu scene while preserving readability and performance.

Requirements:
- Keep the existing character menu idle from the showcase section.
- Add a very subtle 8–14 second pedestal emission pulse. The ring must never turn off or visibly flash.
- Add sparse dust motes, soft sparks, or project-appropriate ambient particles in the 3D scene, concentrated in the warm upper-right light and around the pedestal. Keep them behind the 2D UI.
- Allow existing map ambience to continue in preview mode, but disable loud, chaotic, combat-related, or UI-obscuring effects.
- Optionally add extremely subtle camera drift or parallax with a long loop, but keep the character and pedestal locked to their intended screen composition. Skip it if it weakens the 1:1 match.
- Do not animate the menu cabinet continuously. The logo may have an extremely subtle light shimmer only if it does not reduce readability.
- Pause or reduce unnecessary animation when the application loses focus or when another menu covers the main menu.
- Check frame pacing during map transitions and confirm that particles, tweens, and timers do not multiply after returning to the menu repeatedly.

Provide a short description of every ambient loop and its duration. Stop after the menu feels alive without becoming busy.
```

---

# Section 12 — Responsive Layout and Accessibility Pass

## Visual Breakdown

The 1920×1080 layout is the master target. Other resolutions should preserve the same visual hierarchy instead of rearranging the entire design.

## Prompt for Codex

```text
Harden the main menu for resolution changes, input methods, and basic accessibility without changing the reference composition.

Requirements:
- Treat 1920×1080 as the master visual target.
- Verify 1280×720, 1600×900, 1920×1080, and 2560×1440.
- On ultrawide screens, preserve a centered 16:9 composition-safe region for panel and showcase placement while allowing the live map background to fill the extra width.
- Honor project stretch settings and avoid double scaling.
- Keep all text readable and prevent clipping, especially button subtitles and footer text.
- Maintain safe margins for windowed mode and display scaling.
- Confirm full keyboard, controller, and mouse operation.
- Add accessible labels/descriptions to icon-bearing controls where the current Godot version supports them.
- Ensure selected/focused states are distinguishable by more than color alone through border, brightness, scale, or motion.
- Check contrast for white/cream text on gold, blue, purple, red, and navy surfaces.
- Avoid rapid flashes, aggressive motion, and excessive bloom.
- Preserve the left panel's approximate 32.5% width and the showcase center near 65% at standard 16:9 resolutions.

Provide screenshots at all four requested resolutions and list any deliberate deviations from the 1920×1080 reference. Stop after no clipping, overlap, or broken focus behavior remains.
```

---

# Section 13 — Final 1:1 Visual Matching and QA

## Visual Breakdown

This is the comparison and correction pass. The goal is to match the concept's visual hierarchy even though the maps, player character, and gun differ.

## Prompt for Codex

```text
Perform the final visual-matching and technical QA pass for the ONE GUN main menu.

Use the supplied concept art side by side with a fresh 1920×1080 capture from Godot. Compare and correct the following in order:
1. Left panel position, width, height, corner radius, and gold-frame thickness.
2. Logo size, two-line placement, colors, and spacing above the first button.
3. Button widths, heights, gaps, icon compartments, title/subtitle alignment, and color order.
4. Footer height, portrait scale, dividers, and text hierarchy.
5. Character screen position, full-body scale, pose, gun readability, and silhouette separation.
6. Pedestal width, height, plaque position, glow intensity, and contact with the floor.
7. Camera perspective and the amount of background visible around the character.
8. Warm-right/cool-left lighting balance, shadow softness, bloom, depth of field, saturation, and vignette.
9. Map-preview transition timing and exact 10-second display interval.
10. Hover, focus, press, audio, keyboard, mouse, and controller behavior.

Non-negotiable final checks:
- No TOY BOX LEAGUE text.
- No TOY BOX ARENA text or sign.
- No replacement Toy Box wording.
- Existing character and gun assets are used and remain unmodified for gameplay.
- Background previews are live 3D and cycle every 10 seconds.
- The 2D UI stays visible and stable during preview changes.
- No gameplay match logic runs in menu previews.
- No IP address is shown.
- No errors, orphan nodes, resource leaks, or repeated timers occur after returning to the menu several times.
- No unrelated gameplay files were changed.

Use screenshot overlays or image-difference comparison where useful. Iterate until the layout and visual treatment are as close to the reference as the approved asset substitutions allow.

At completion, provide:
- A 1920×1080 final screenshot for each configured map preview.
- A concise list of created and edited files.
- A list of any remaining visual mismatches and the exact reason for each.
- Confirmation that the project launches and all four buttons still work.
```

---

# Final Acceptance Target

The implementation is successful when it reads immediately as the supplied concept:

- Premium dark-navy and gold menu cabinet on the left.
- Large dimensional ONE GUN logo with no subtitle.
- Four bold color-coded buttons in the same order and proportions.
- Compact player/build footer.
- Live current character and gun displayed heroically on a glowing ONE GUN TROPHY pedestal.
- Cinematic map preview behind the showcase.
- A different live map preview appears every 10 seconds.
- Warm, colorful, cartoony, polished presentation with strong depth and readable UI.

Because approved game maps and existing models replace the concept's pictured arena, character, and gun, “1:1” means matching the **layout, framing, materials, lighting, proportions, hierarchy, and polish**, while retaining the actual ONE GUN content.

