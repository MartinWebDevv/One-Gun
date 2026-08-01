# Blue Cat Section 4 - High-Resolution Form Notes

Date: 2026-07-17  
Source: `art_src/mascots/blue_cat/blend/BC_HighRes_v001.blend`  
Status: Rejected after user review; retained as v001 provenance only. Section 5
remains locked while `BC_HighRes_v002.blend` is rebuilt.

## Outcome

The approved Section 3 silhouette has been converted from separate blockout
masses into a polished high-resolution Blue Cat source. The arms are now
continuous curved trunks, not bead or sphere chains. Rounded shoulder and hip
bridges make the limbs flow into the torso, while the hands retain the approved
three-finger-plus-thumb arrangement and the feet retain broad stable contact.

The first fused-shell review exposed tearing on the arms, legs, and tail
because the construction curves were open. That pass was rejected internally.
The final source caps every construction curve, uses one connected watertight
body shell, applies dense surface relaxation, and uses a satin temporary review
material that does not exaggerate surface faceting.

After the first user review, the eye whites and colored layers were recessed,
the blue socket rims were moved behind the whites, the tail was rebuilt from a
wide root embedded deeply in the rear pelvis, and the palm pads were flattened
and buried into the hand surface. The regenerated side and closeup views in
this package include those corrections.

## Saved-source audit

- Blender: 5.1.2
- Evaluated visible height: 1.3875 m
  - Difference from the concept's approximate 1.40 m target: -0.0125 m / -0.9%
- Visible bounds:
  - X: -0.4939 to 0.4939 m
  - Y: -0.4415 to 0.6705 m
  - Z: 0.0011 to 1.3886 m
- Body shell: 112,034 vertices / 112,032 faces
- Body shell connected components: 1
- Non-manifold edges: 0
- Boundary edges: 0
- Total visible base triangles: 276,008
- Visible review objects: 37
- Hidden editable construction objects: 36
- UV layers: 0
- Armatures: 0
- File texture images: 0
- Remaining body modifier: one non-destructive render subdivision modifier

The triangle count is intentionally above the runtime budget because this is
the Section 4 high-resolution form source. Section 5 will create controlled
deformation topology and the packet's 35-60k LOD0, 15-25k LOD1, and 6-10k
LOD2 meshes.

## Review package

- `renders/S4_BlueCat_HighRes_ReviewSheet_v001.png`
- `renders/S4_BlueCat_HighRes_DetailCloseups_v001.png`
- `renders/S4_BlueCat_HighRes_ReferenceOverlay_v001.png`
- `renders/S4_BlueCat_HighRes_BlackSilhouette_v001.png`
- `renders/S4_BlueCat_HighRes_WireReview_v001.png`
- `renders/S4_BlueCat_HighRes_Turntable_v001.webp` (48 unique views)
- `renders/S4_BlueCat_HighRes_TurntableContact_v001.png`
- Individual front, side, back, three-quarter, wire, and face/shoulder/hand/
  feet/tail closeup PNGs use the same `S4_BlueCat_*_v001.png` convention.

## Form decisions carried forward

- Approved proportions, stance, depth, and silhouette remain the governing
  blockout lock.
- Arms are continuous rounded trunks from shoulder to wrist.
- Hands are chunky and grip-capable, with three simplified fingers and a thumb.
- Feet remain broad and stable with three readable toe pads per foot.
- Face uses separate eyeballs, projecting muzzle volume, socket/lid rims,
  brows, nose, mouth, cheek volume, inner ears, tufts, and bold whiskers.
- Eyeballs are shallow-set; socket rims remain behind the whites, and the
  iris/pupil/highlight stack adds only a few millimeters of front projection.
- Palm pads are shallow embedded domes with their perimeter buried in the hand.
- Tail root uses a wide internal blend volume rather than a narrow surface join.
- Tail uses the approved inferred rest direction and a separate cream tip.
- Surface detail remains bold and gameplay-readable; there are no fur strands,
  pores, or noisy microdetail.

## Intentionally deferred

- Retopology, deformation loops, production UVs, masks, and LODs: Section 5
- Full facial pose/shape-key library: Section 6
- Production shaders, palette masks, and textures: Section 7
- Rigging, weighting, sockets, animation, Godot export, and integration: later
  packet sections after their required approval gates

No Godot runtime or gameplay file was changed by Section 4.
