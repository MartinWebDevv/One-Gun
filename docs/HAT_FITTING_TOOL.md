# Hat Fitting Tool

The Hat Fitting Tool provides a safe visual workflow for positioning every shipped Hat independently on every registered character model. It previews the same character scenes, animated head socket, Hat registry, and fitted runtime GLB used by gameplay, the Locker, Prize Counter, progression previews, lobby actors, spectators, decoys, and the Winners Circle.

The tool never edits a source or runtime GLB. It saves only small per-Hat/per-model overrides to `models/cosmetics/hats/hat_fit_profiles.tres`. The registry's original values remain the fallback, so every saved adjustment is reversible.

## Opening the tool

1. Open the One Gun project in Godot 4.7.1.
2. In the **FileSystem** panel, open `tools/hat_fitting_tool.tscn`.
3. Press **F6** or click **Run Current Scene**. Do not use F5; F5 launches the game instead of the fitting tool.
4. Maximize the tool window if the controls feel cramped. No network connection or Supabase login is needed.

## Safely fitting one Hat

1. Choose the Hat from **Hat** and choose any registered character under **Character Model**. Each combination can have its own saved fit. A model without an exact override displays its explicitly declared inherited fit until you save a dedicated one.
2. Turn **Play Idle** off while doing the initial alignment. Click **Front**, then **Reset Spin**, for a predictable starting view.
3. Adjust **Seat Depth** first. A more-negative value lowers the Hat into the fur; a less-negative value lifts it. Use `0.005 m` steps and stop once the base makes convincing contact without cutting too deeply through the forehead.
4. Adjust **X / Y / Z Offset** next:
   - **X** moves left or right.
   - **Y** is a fine vertical correction after Seat Depth.
   - **Z** moves toward the face or toward the back of the skull. This is the key control when a Hat looks centered from the front but is wrong from above.
5. Adjust **Target Hat Width** in `0.01 m` steps. This is uniform scaling, so it preserves the original proportions and materials. Values around `0.95–1.55 m` are the normal working range; move outside it only when the authored silhouette clearly requires it.
6. Use **Pitch / Yaw / Roll** last. Work in `0.5°` steps; large rotations usually indicate that Z Offset or Seat Depth should be corrected first.
7. Inspect **Front**, **Side**, **Top**, and **Full Body**. Drag directly on the preview—or use the controller right stick—to check a full 360-degree turn. The background, lights, podium, and camera remain fixed while only the character rotates.
8. Turn **Play Idle** on and watch at least one complete idle loop. Confirm that the Hat does not float, clip badly, touch the top of the frame, or expose a bad fit when the head moves.
9. Switch through every character model and repeat the inspection. **Copy to Next Model** copies the current values, advances through the registered model list, and creates an unsaved draft on the destination. Review it before saving; press it again to continue to the next model.
10. Click **Save This Fit** when the current Hat/model is correct. Use **Save All Drafts** only after reviewing every unsaved combination. A green status message confirms the resource write.
11. Stop the tool with **F8**. Test the saved Hat in the Locker, Prize Counter, a progression milestone preview, and at least one gameplay or lobby character before shipping.

## Undo and recovery controls

- **Revert Unsaved** discards only the current in-memory draft and returns to the last saved override (or registry base). It does not touch disk.
- **Reset to Base** loads the registry's original fit as a new unsaved draft. It does not remove a previously saved override until you save that draft.
- **Remove Saved Override** is a two-click destructive confirmation for only the selected Hat/model. It deletes that one override from the profile and immediately restores the registry fallback. It never deletes art.
- **Exit Tool** requires two clicks. If drafts are unsaved, Escape warns instead of silently closing.
- **Ctrl+S** saves all reviewed drafts.

For source-control recovery, revert only `models/cosmetics/hats/hat_fit_profiles.tres`; never revert or replace a GLB to undo a fit. Keeping fit data separate makes review diffs small and prevents accidental damage to optimized assets.

## Release checklist

- Check all 12 Hats on every registered model (currently 96 combinations across eight models).
- Check front, side, top, full body, 360-degree rotation, and one idle loop.
- Check that ears being covered looks intentional and that the Hat base does not visibly float.
- Verify the Locker, Prize Counter shoulder-up inspection, progression preview, lobby, gameplay, spectator view, and Winners Circle all agree.
- Run `tools/hat_fitting_tool_validation.tscn` and `tools/hat_asset_probe.tscn` headlessly or from the editor.
- Test the resulting build on the weaker laptop at 1080p Low to confirm preview opening and Hat changes do not cause a hitch or memory growth.

## Adding a future character model

1. Register its stable ID and visual scene in `player_skin_registry.gd`.
2. Add the same ID to `MODEL_HEADWEAR_PROFILES` with measured `height_offset`, `forward_offset`, and expected world-space `socket_height_range` values. Set `fit_fallback` to a compatible registered head shape; only the default Male model may end the chain without a fallback.
3. Open this tool. The new model appears automatically in **Character Model**; no Hat-tool UI edit is required.
4. Review all Hats using the inherited fits, then save exact per-model overrides wherever the head shape needs them.
5. Run `tools/hat_fitting_tool_validation.tscn`, `tools/hat_asset_probe.tscn`, `tools/hat_preview_interaction_validation.gd`, `tools/hat_render_validation.tscn`, and `tools/gameplay_hat_camera_validation.tscn`. These iterate `PlayerSkinRegistry.MODEL_IDS`, so the new character is included automatically. Registration without the explicit headwear contract fails validation.
