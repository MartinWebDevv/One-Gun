# Blue Cat — Section 3 Proportional Blockout Review

Section 3 review build: `BC_Blockout_v001.blend`  
Created with Blender 5.1.2 from the user-approved Section 2 v002 package.

This is a silhouette/proportion blockout made from separate editable masses.
It is not production topology and contains no rig, skinning, UVs, textures,
character animation, shape keys, Godot export, or gameplay integration. The
root's rotation driver exists only to produce the required turntable.

## Locked blockout measurements

- Evaluated bounds: X `-0.5100..0.5100 m`, Y `-0.4200..0.6546 m`,
  Z `0.0000..1.3970 m`.
- Evaluated floor-to-ear height: **1.397 m**, 3 mm below the approved
  approximately 1.40 m target.
- Head mass: 0.75 m wide, 0.62 m deep, 0.58 m dome-to-chin.
- Torso depth: 0.42 m.
- Front stance: approximately 0.59 m.
- Muzzle projection, short legs, large feet, A-pose arm placement, and tail
  root/curl follow the approved Section 2 construction envelope.

The scene contains 38 editable character masses (37 mesh objects and one
curve), four fixed orthographic cameras, a neutral studio, and one non-rendered
root control. The model has zero UV layers and zero armatures.

## Fixed cameras

- `CAM_BC_FRONT`
- `CAM_BC_SIDE`
- `CAM_BC_BACK`
- `CAM_BC_3Q`

Front, side, and back cameras use a 1.70 m orthographic scale and target
Z = 0.70 m. The side camera faces the same direction as the approved
near-profile evidence. The overlay sheet uses the identical camera mapping;
the source side image is still correctly labeled as back-three-quarter /
near-profile rather than true orthographic evidence.

## Review deliverables

- `renders/S3_BlueCat_Blockout_ReviewSheet_v001.png`
- `renders/S3_BlueCat_Blockout_Front_v001.png`
- `renders/S3_BlueCat_Blockout_Side_v001.png`
- `renders/S3_BlueCat_Blockout_Back_v001.png`
- `renders/S3_BlueCat_Blockout_ThreeQuarter_v001.png`
- `renders/S3_BlueCat_Blockout_BlackSilhouette_v001.png`
- `renders/S3_BlueCat_Blockout_ReferenceOverlay_v001.png`
- `renders/S3_BlueCat_Turntable_v001.webp` — 48 unique angles, looping 360°
- `renders/S3_BlueCat_TurntableContact_v001.png` — eight-angle static check
- `qa/turntable_frames_v001/*.png` — lossless turntable source frames

The pale blue, cream, pink, green, and dark materials are temporary region
guides for reading the volumes. They are not Section 7 production materials.

## Largest remaining proportion / silhouette mismatches

1. **Rear cranium fullness:** the true-side blockout reads approximately
   0.05–0.08 m fuller behind the face than the painted near-profile. The
   source is not a true side view, and the model matches the approved 0.62 m
   depth proposal, so this needs silhouette approval rather than silent
   reduction.
2. **Tail rest height:** the blockout cream tip finishes approximately
   0.15–0.20 m higher and farther back than the low painted near-profile tail.
   This follows the more readable v002 rear-curl proposal that the user
   approved, but it remains the largest visible departure from locked art.
3. **Ear projection:** the overall ear height is correct, but the temporary
   triangular wedges read narrower and more slab-like in side/three-quarter
   than the rounded concept ears. Broader roots and softer front/back volume
   are needed if the silhouette direction is approved.
4. **Torso taper:** the blockout torso is an even oval and reads roughly
   0.03–0.05 m fuller around the middle. The concept is subtly more pear-shaped
   with smoother neck/hip transitions.
5. **A-pose arm span:** the approved modeling pose is intentionally wider than
   the arms-down lineup reference. The bead-like shoulder/elbow transitions
   are temporary mass boundaries, not the intended final silhouette.
6. **Crown tufts:** their height is now below the ear tips, but they remain
   simplified rounded markers rather than the final swept tufts.

## Approval gate

**APPROVED by the user on 2026-07-17** for proportions, stance, depth, and
silhouette. This approval accepts the Section 3 dimensional direction and
unlocks Section 4, but it does **not** approve the temporary segmented or
blocky surface treatment as final art.

The user explicitly requires the Section 4 arms to become continuous rounded
limb “trunks,” with no visible sphere-to-sphere or ball-joint construction.
The same condition applies to the whole character: sharp wedges, bead-like
limbs, hard mass boundaries, and blockout seams must be replaced with the
smooth, cohesive, polished premium-toy finish shown in the approved concept.

Section 4 is unlocked but has not started.
