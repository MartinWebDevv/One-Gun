# Blue Cat Section 4 v002 - Organic Sculpt Checkpoint

Date: 2026-07-17  
Source: `art_src/mascots/blue_cat/blend/BC_HighRes_v002.blend`  
Status: Early clay direction review; Section 4 is not complete or approved.

## Why v002 exists

The user rejected the v001 high-resolution model because the overall result
still read as smoothed procedural parts. V002 is a ground-up Section 4 rebuild,
not another correction pass on that model.

## Construction direction

- One cohesive implicit sculpt volume forms the head, neck, torso, shoulders,
  arms, hands, pelvis, legs, feet, and buried anatomical tail root.
- The visible tail is one clean high-resolution swept subtool entering deeply
  into that root; it contains no chain of visible sphere or voxel segments.
- Eye whites are shallow caps embedded in the head. Eyelid lines remain behind
  the front of the whites, and iris/pupil layers are nearly flush.
- The muzzle is one unified implicit cream subtool.
- Palm markings are paper-thin domes seated at the evaluated hand surface.
- Three tapered crown tufts replace the ball-like v001 hair construction.

## Early audit

- Evaluated visible height: 1.3803 m (scale correction is deferred until the
  organic direction is accepted)
- Body sculpt: 102,180 vertices / 204,360 base triangles
- Visible review objects: 41
- UV layers: 0
- Armatures: 0
- No production topology, UVs, LODs, rig, skinning, textures, Godot export, or
  runtime integration

## Early review images

- `renders/S4_BlueCat_OrganicClay_Front_v002.png`
- `renders/S4_BlueCat_OrganicClay_Side_v002.png`
- `renders/S4_BlueCat_OrganicClay_ThreeQuarter_v002.png`
- `renders/S4_BlueCat_OrganicClay_Face_v002.png`
- `renders/S4_BlueCat_OrganicClay_Hand_v002.png`
- `renders/S4_BlueCat_OrganicClay_Tail_v002.png`

The full Section 4 orthographic, overlay, silhouette, wire, closeup, and
turntable package is intentionally deferred until the user accepts this new
sculpt direction.
