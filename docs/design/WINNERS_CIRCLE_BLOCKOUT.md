# Winners Circle Blender/Godot Blockout

## Purpose

This blockout turns the approved Winners Circle concept into a working, replaceable production scaffold. Blender owns the static ceremony set. Godot owns live match data, character appearances, Victory Moves, the equipped ceremonial gun, the trophy drop, confetti, camera/lights, standings, personalized results, and Ready/return coordination.

The blockout is not final art. Its measurements and named anchors are the contract that final art should preserve.

## Source and outputs

- Blender generator: `tools/blender/generate_winners_circle_blockout.py`
- Editable master: `art_src/winners_circle/blockout/winners_circle_blockout.blend`
- Static room shell: `models/winners_circle/blockout/wc_stage_shell_blockout.glb`
- Podiums and Trophy landing plinth: `models/winners_circle/blockout/wc_podiums_blockout.glb`
- Signs, banners, shelves, bulbs, and toy silhouettes: `models/winners_circle/blockout/wc_decor_blockout.glb`
- Godot assembly: `UI/winners_circle_stage_blockout.tscn`
- Live-stage adapter: `UI/winners_circle_stage_blockout.gd`

All three GLBs are exported at a shared origin and instanced separately at `(0, 0, 0)`. A production artist can replace the room shell, podiums, or decor independently without changing match/result code.

## Stable Godot anchors

Do not rename these nodes when replacing art:

- `Anchors/FirstPlace`
- `Anchors/SecondPlace`
- `Anchors/ThirdPlace`
- `Anchors/TrophyStart`
- `Anchors/TrophyLanding`
- `Anchors/CeremonialGun`
- `Anchors/Confetti`
- `LookTargets/CameraTarget`
- `LookTargets/ChampionTarget`
- `LookTargets/SecondTarget`
- `LookTargets/ThirdTarget`

The first three anchors receive lightweight copies of the final top-three character appearances. `TrophyStart` and `TrophyLanding` define the entire drop path, keeping the Trophy in front of the champion and clear of every Victory Move. `CeremonialGun` receives the champion's equipped gun skin when a production mapping exists.

The podium-facing `DynamicLabels/FirstName`, `SecondName`, and `ThirdName` are Godot `Label3D` nodes, not baked Blender text. Player names therefore stay dynamic and readable.

## Regenerating the blockout

From the project root:

```powershell
& "D:\Blender\blender.exe" --background --python "tools/blender/generate_winners_circle_blockout.py"
```

Run Godot's editor import once after generating new GLBs, then run:

```powershell
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script "res://tools/winners_circle_validation.gd"
```

## Replacement checklist

1. Keep each production GLB under the repository asset budgets. Optimize any generated or purchased source before it enters Godot.
2. Preserve one shared origin and the approximate podium top heights. If heights change, move the corresponding Godot character anchor rather than placing characters inside Blender.
3. Keep the champion center clear for all supported static poses and animated Victory Moves.
4. Keep the Trophy landing plinth in front of the champion. The Trophy must never be parented to the character rig.
5. Keep signage/logo text separate from player names. Final `ONE GUN`/`OG` art can be mesh, texture, or emissive material; player names remain live Godot text.
6. Keep static dressing non-colliding. The result screen must not run physics, AI, inventory, or multiplayer synchronizers.
7. Retest Low and High quality after changing mesh density, transparent materials, lights, particles, or texture sizes.

## Performance contract

The current three GLBs total less than 6 MB, contain no collisions, and use shadowless stage lights. The ceremony renders in the existing isolated 960×540 SubViewport, which `GraphicsQualityManager` scales with the selected render quality. Confetti density is also quality-scaled, and Reduced Motion replaces dances with idle plus an immediate Trophy placement.

The final-art pass must retain Forward+ and be checked at 1080p Low on the weaker laptop. Repeated match-to-Winners-Circle-to-lobby transitions must not grow RAM/VRAM or produce a visible transition hitch.

## Deferred production assets

- Authored Trophy GLB at `models/rewards/winners_circle_trophy.glb`
- Final room, podium, shelf/toy, banner, logo, bulb, and ceremonial-gun-display art
- Final audio stingers and crowd/celebration ambience
- Production Victory Move catalog mappings
- Production gun-skin display mappings

The current placeholder Trophy and default gun path are deliberate fallbacks, so the full result flow remains testable before those assets arrive.
