# Blue Cat — Section 2 Reference and Turnaround Record

Corrected review package prepared from the approved
`docs/design/ONE_GUN_MASCOT_CONCEPT_SHEET.png`. Section 2 contains source
extraction, measurements, and explicitly labeled 2D construction proposals
only. No 3D model or Section 3 work has started.

## Review deliverables

- `renders/S2_BlueCat_LockedEvidenceAtlas_v002.png` — every packet-required
  source region, labeled as locked evidence.
- `renders/S2_BlueCat_MeasuredProportions_v002.png` — normalized 1.40 m front
  view, landmarks, complete requested measurement table, uncertainty classes,
  and isolated proposal depths.
- `renders/S2_BlueCat_TurnaroundReview_v002.png` — front and back-three-quarter
  evidence plus true-side, true-back, and relaxed A-pose construction
  proposals at one common vertical scale.
- `renders/S2_BlueCat_DetailGuides_v002.png` — neutral face, eyes, muzzle,
  hands, feet, tail, contradictions, and inference register.
- `ref/BlueCat_Palette_sampled_v002.png` — sampled palette swatches.
- `ref/crops/native/*.png` — exact native-pixel source crops.
- `ref/crops/*.png` — aspect-preserving presentation copies.

The earlier `v001` sheets are retained for provenance but are superseded. They
should not be used as modeling approval: the v001 “side” mirrored the same
near-profile evidence, the v001 “back” was an unapproved filled silhouette,
and its measurement record omitted required dimensions.

## Official scale

**LOCKED: approximately 1.40 m from floor contact to the highest ear tip.**

The concept's printed `PLAYER HEIGHT: ~1.4m` statement and the production
packet agree. The decorative 0–2.5 m panel grid does not agree with its own
cat and human silhouettes; both span implausibly similar grid heights. The
grid is therefore preserved as visual evidence but rejected as a metric
ruler. All front measurements normalize visible ear-tip-to-floor height to
1.40 m (171 source pixels, 122.14 px/m).

## Visible measured proportions

Values inherit roughly ±0.02–0.05 m illustration uncertainty unless noted.
`Estimated` means the feature is visible but its boundary or joint center is
partly occluded or softly painted. It does not mean a hidden form was guessed.

| Feature | Result | Class | Basis |
|---|---:|---|---|
| Overall height | 1.40 m | Locked | Written height; ear tip to floor |
| Overall width | 0.89 m | Measured | Widest visible body/arm span |
| Head height | 0.68 m | Measured | Ear tip to chin; dome-only 0.58 m |
| Head width | 0.75 m | Measured | Widest cheek span; dome span 0.65 m |
| Iris size | 0.13 × 0.16 m | Measured | Visible green iris ellipse |
| Inner-eye separation | 0.16 m | Measured | Nearest iris edges |
| Muzzle size and position | 0.34 × 0.18 m at ~0.86 m | Estimated | Soft cream boundary |
| Torso length | 0.37 m | Measured | Shoulder line to crotch |
| Shoulder width | 0.47 m | Estimated | Joint centers obscured by arms |
| Arm length | 0.41 m | Estimated | Shoulder-to-wrist curved path |
| One hand | 0.17 × 0.21 m | Estimated | Hanging mitten silhouette |
| Leg length | 0.28 m | Measured | Crotch to floor vertically |
| One foot | 0.25 × 0.16 m | Estimated | Front foot silhouette |
| One outer ear | 0.17 × 0.27 m | Estimated | Visible ear boundary |
| Tail thickness | 0.10–0.12 m | Measured | Scale and action views |
| Stance width | 0.59 m | Measured | Outer foot contact span |

### Height landmarks above the floor

| Landmark | Height | Landmark | Height |
|---|---:|---|---:|
| Ear tip | 1.40 m | Shoulder | 0.65 m |
| Head dome | 1.30 m | Hand bottom | 0.32 m |
| Eye center | 1.00 m | Crotch | 0.28 m |
| Nose | 0.90 m | Tail root | 0.26 m |
| Chin / head bottom | 0.72 m | Foot top | 0.15 m |

The character is therefore approximately two chibi heads tall. The unusually
large head, oversized eyes, rounded body, chunky hands, sturdy feet, and clear
tail remain the silhouette priorities.

## Sampled palette

| Region | Hex | Region | Hex |
|---|---|---|---|
| Primary blue | `#386CA8` | Cream | `#C4C5BD` |
| Lit blue | `#4976A8` | Inner-ear pink | `#C65C7A` |
| Shadow blue | `#274B7A` | Iris green | `#57852D` |
| Deep shadow | `#1A3961` | Pupil / nose | `#040802` |

These are concept-sheet samples, not final shader values. Section 7 owns the
production material response and lighting validation.

## Locked evidence

The v002 atlas includes the lineup front, scale-panel front and
back-three-quarter/near-profile, toy-style guide, neutral and expression
heads, animation examples, weapon-hold examples, rig diagram, and environment
example. Native crops are exact rectangles from the 1536 × 1024 approved
sheet. Presentation resizes preserve aspect ratio and do not reshape the art.

The source does **not** contain a true orthographic side, true back, neutral
three-quarter, or relaxed A-pose turnaround. The rig diagram is a T-pose and
is evidence of rig intent, not approval to model in that pose.

## Inferred areas awaiting approval

1. **True side depth** — proposal: head depth ~0.62 m, body depth ~0.42 m,
   muzzle projection 0.06–0.08 m, and toe reach ~0.30 m. These values are
   isolated in orange on the v002 sheets.
2. **True back** — proposal: plain blue back and ear backs with no new
   markings. Small crown tufts remain visible. No seam or rear patch is added.
3. **Tail rest carry** — root is ~0.26 m above the floor and visible thickness
   is 0.10–0.12 m. The blue tail and rounded cream tip are locked; the exact
   rear curl is proposed.
4. **Hand and foot markings** — the lineup master shows blue mitts with cream
   palm patches and blue feet with cream toe caps; the toy guide reads as
   mostly cream paws/feet. Proposal: use the lineup master because it is the
   roster-defining view and agrees best with the weapon-hold examples.
5. **Hand construction** — proposal: a rounded mitten with three sculpted
   fingers plus an opposable thumb, separated enough for gun, melee,
   throwable, and shield grips. Exact finger topology belongs to later model
   and rig gates.
6. **Modeling pose** — proposal: relaxed symmetric A-pose, arms about 32° away
   from the torso, softly bent elbows, palms inward/back, legs straight, feet
   forward at the 0.59 m stance, neutral face, and readable tail clearance.
7. **Muzzle and limb depth** — only front and near-profile information exists;
   final volume remains subject to Section 3 silhouette review.

Directly visible and retained: large expressive head, oversized green eyes,
blue body, cream muzzle/belly/palm/toe areas, pink inner ears, small head
tufts, rounded limbs, chunky hands, sturdy feet, cream-tipped readable tail,
three cream whiskers per cheek, and cream brow/forehead accents.

No realistic fur, sharp anatomy, excessive muscle definition, clothing, or
unapproved markings were introduced.

## Approval gate

**APPROVED by the user on 2026-07-17.** The approval accepts the four proposals
summarized on the turnaround sheet: lineup-master hand/foot treatment, the
side-depth envelope, the plain-back and cream-tipped tail-rest interpretation,
and the relaxed A-pose with a three-finger-plus-thumb hand plan.

Section 3 modeling is now unlocked but has not started.
