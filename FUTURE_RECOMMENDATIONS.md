# One Gun Future Recommendations

These are planning recommendations only. They are not implemented by this audit and do not begin a new development phase.

## Guiding principle

Stabilize and prove the current game before adding systems. One Gun already has a wide interaction surface: local play, splitscreen, bots, three maps, gun/melee/items/powerups, scoring, runtime UI, and online authority. Every new feature currently multiplies testing across those dimensions.

## Priority 0: Preserve a trustworthy baseline

### 1. Establish a clean source-control checkpoint

- Review the pre-existing dirty worktree and identify intended changes.
- Commit a known-good playtest baseline before broad work.
- Do not mix cleanup, scene resaves, feature changes, and asset changes in one checkpoint.
- Record the exact Godot version, export build ID, and Tailscale test pair.

Success evidence:

- A reproducible commit/hash that both test machines can export and run.
- No uncertainty about which uncommitted changes are required.

### 2. Reconcile current documentation

Treat code/scenes plus these audit documents as the current observed state, then update older documents deliberately:

- Remove the claim that online is stubbed.
- Record that bots use items online/local.
- Reconcile the one-melee design statement with 6-8 current authored placements.
- State that powerups remain fixed while visible and reroll on respawn.
- Separate unresolved TODOs from completed history.
- Correct current map/navigation claims after validation.
- Keep `GAME_RULES.md` as the balance source only after every number/behavior is rechecked.

Success evidence:

- A new developer can read the docs without encountering mutually exclusive behavior claims.

## Priority 1: Stabilize existing online gameplay

### 3. Isolate the Magnet Hands smoke failure

Reproduce on Western V2 first because it failed twice, then compare Forest and City.

Capture:

- Item stable ID/type.
- Actor ID and peer authority.
- Item start/end global position.
- Map root scale and parent.
- Whether the magnet overlap area sees the item.
- Request cadence and host validation result.
- Client presentation versus host authoritative state.

First decide whether the gameplay is wrong or the test assumption is wrong. Do not redesign Magnet Hands until that distinction is proven.

Success evidence:

- Repeated passes on all three current maps, or a precisely documented deterministic limitation.

### 4. Revalidate navigation on all current maps

- Check `NavigationMesh` polygon counts in the editor.
- Turn on navigation debug visualization.
- Verify paths from every spawn to the gun, every item/powerup cluster, and every intended elevation route.
- Test each bot difficulty with moving actors and blocked routes.
- Specifically test Western rooftops/catwalk/tower and City interiors/brownstone landing.

Do not rebake and save until the current missing-serialization state is confirmed and a map-specific backup/checkpoint exists.

Success evidence:

- Nonzero source-controlled nav data or a documented intentional runtime-bake path.
- Route matrix passes without direct-wall movement or persistent stuck states.

### 5. Run a real two-machine Tailscale matrix

Loopback smoke tests cannot prove the actual product path.

Minimum matrix:

- Each machine hosts once.
- Named lobby join and direct `100.x` fallback.
- Repeated leave/rejoin before match.
- All three maps.
- Human-only and host-bot match.
- Gun, every melee interaction class, every item, every powerup, death/spectate, multiple rounds, set/match return.
- Host Return to Lobby, host Main Menu, client-only Main Menu, and host Alt+F4.
- Simulated latency/jitter if practical.

Success evidence:

- Test record with build hash, machines, Tailscale versions, outcomes, and logs.

### 6. Clean up smoke-test lifecycle signal quality

After gameplay correctness is established, classify ObjectDB/RID leaks, freed lambda captures, missing-node sync, and despawn warnings.

Success evidence:

- Passing smoke output has no unexplained engine errors.
- A host assertion failure does not obscure the client's primary diagnostic.

## Priority 2: Verify development and release pipelines

### 7. Verify Godot editor and Terrain3D intent

- Close all Godot processes and perform one clean editor start.
- Confirm whether Terrain3D loads without native-library temp/copy errors.
- Determine whether any current or planned map still depends on Terrain3D or `desertTerrain/`.
- Do not remove the plug-in or terrain data until dependency intent is explicitly approved.

Success evidence:

- Clean editor startup on the development machine.
- Written keep/remove decision for Terrain3D based on actual use.

### 8. Establish a documented Windows export process

- Correct/verify the Windows output target format.
- Use one build/version source for preset metadata and UI.
- Document whether packaging is direct EXE+PCK or a post-export ZIP step.
- Test on a machine without the Godot editor/project installed.
- Confirm Tailscale CLI discovery and direct-IP fallback in the exported build.

Success evidence:

- One command/checklist produces a launchable, versioned package.
- Both test machines can identify that they run the same build.

### 9. Make Blender generators portable

Only after gameplay stabilization:

- Resolve project/output paths relative to each script or accept arguments.
- Remove the personal Claude scratch output from preview tooling.
- Record Blender version and command examples in one pipeline document.
- Add a safe warning/confirmation around full-map builder overwrite behavior.
- Keep City builder explicitly retired.

Success evidence:

- A second checkout/location can regenerate one sample asset without editing source paths.

### 10. Create an asset provenance manifest

Record for every third-party/AI asset:

- Source URL/vendor/tool.
- Creator/license.
- Date acquired/generated.
- Allowed distribution/modification.
- Original backup location.
- Optimization steps.
- Final in-project path.

Success evidence:

- Public-distribution rights can be reviewed without reconstructing history.

## Priority 3: Correct bounded data and performance risks

### 11. Repair configuration-default integrity

After a test is written for preset/default behavior, make the default item registry match the live seven-item registry and verify category/per-item UI after reset/save/load.

Success evidence:

- Reset, save, load, local spawn, and online config sync preserve all seven items and toggles.

### 12. Address the orange bot model budget

This should be a dedicated asset task, not an incidental replacement.

- Preserve the current rig, skeleton/bone names, scale, materials, animation compatibility, and hold-point behavior.
- Produce measurable triangle/texture targets.
- Compare render, collision, animation, and network puppet appearance with 1-7 bots.
- Keep the current file backed up until visual/animation parity is verified.

Success evidence:

- Model falls within an approved budget and a full bot match remains visually correct.

### 13. Define placeholder versus intentional minimalist art

Make an explicit keep/replace list for:

- Powerup sphere.
- Bullet sphere.
- Grenade flash.
- Bubble-gum trap.
- Emoji/text weapon identities.
- Main-menu background.
- Missing gameplay sounds.

This is a style decision before an asset-production task.

### 14. Complete audio feedback and mixing plan

- Confirm source licenses.
- Decide whether to add dedicated Music/SFX/UI buses.
- Add only approved missing event cues: pickup, drop, disarm, round start/end, death, grenade.
- Review the unused 11 MB track and large WAV compression/import settings.

Success evidence:

- Every important gameplay state has intentional feedback and sliders behave consistently.

## Priority 4: Improve maintainability after behavior is locked

### 15. Add focused regression coverage

Before refactoring, create narrow tests/checks for:

- GameConfig defaults/presets.
- Marker counts and groups per selectable map.
- Navigation polygon presence.
- Round/set/match transitions.
- Gun pickup/fire/elimination epoch validation.
- Shield versus bullet/melee semantics.
- All item and powerup authoritative paths.
- Host/client exit flows.
- Online bot ownership and scoring.

Tests should isolate failures so one early assertion does not hide later systems.

### 16. Plan, do not immediately execute, responsibility boundaries

The largest scripts need clearer ownership eventually, but behavior must be protected first. Candidate boundaries for a future design review include:

- Local match state versus online match replication.
- Actor spawn/reset registry versus scoring.
- Item/powerup authoritative coordinator versus deployed-effect presentation.
- Human movement versus inventory/effects/animation/network adapter.
- Lobby data model versus runtime widget construction.

This is not a recommendation for a broad rewrite. Any extraction should be incremental, behavior-preserving, and covered by the new checks.

### 17. Decide how human/bot parity should be maintained

Current duplication is explicit. Before changing it, decide whether parity is a goal or whether different constants/behavior are intentional. A future approach could centralize data while retaining separate controllers, but that requires an approved architecture decision.

### 18. Harden animation identity

Replace or validate fragile numeric action ordering only in a dedicated animation pipeline task. Preserve the cat rig and all current clips while establishing named/action metadata that survives re-export.

### 19. Add UI visual regression coverage

Capture a manual or automated screenshot matrix for:

- Main menu.
- Local lobby.
- Online host/client lobby.
- Settings and rebind screen.
- Local full-screen HUD.
- Local splitscreen P1/P2 HUD.
- Online HUD and scoreboard.
- Spectator state.
- Pause overlays.
- Long player names and non-default resolutions.

## Priority 5: Online robustness and polish

Only after priorities 0-4 produce a reliable baseline:

1. Remote interpolation/lag smoothing.
2. Client-side firing feedback/prediction with host reconciliation.
3. Graceful reconnect/session resume if product scope requires it.
4. Better host-left messaging and cleanup.
5. Deliberate in-progress join policy.
6. Online team assignment if teams are truly required.
7. Host migration only if its complexity is justified by the target audience/session length.

These are separate features and should not be bundled into one networking rewrite.

## Priority 6: Content and feature development

After stabilization, pipeline, and scope decisions:

- Character customization can be designed with explicit art/data/network requirements.
- New maps can follow the marker and asset-budget contracts.
- Additional VFX/audio polish can replace approved placeholders.
- Legacy maps can be either archived as test content or migrated deliberately.
- Any future melee purchase/upgrade concept should begin with a new design decision; the old tier and `upgrade_tier()` systems have been removed.

## Recommended phase gates

| Gate | Required evidence before moving on |
|---|---|
| Baseline gate | Clean commit, reconciled current-state docs, matching build ID |
| Gameplay stability gate | Magnet Hands classified/fixed, navigation verified, smoke passes cleanly |
| Network gate | Two-machine Tailscale matrix passes with each host |
| Pipeline gate | Clean Godot startup, repeatable Windows export, portable sample Blender generation |
| Asset gate | Provenance manifest and bot model plan |
| Maintainability gate | Focused regression coverage exists before structural changes |
| Feature gate | New work has explicit local/splitscreen/bot/online/UI/map test scope |

## Do-not-touch list until an approved phase

- Current map marker transforms and authored melee/item/powerup placements.
- Gameplay preview behavior.
- Cat mascot rig, materials, animation sources, and hold-point hierarchy.
- GameConfig/GameEvents roles and autoload order.
- Online actor-ID/owner-ID separation.
- Host-authoritative gameplay outcomes and round epochs.
- CityMap full-scene builder retirement status.
- Legacy/unused assets, Terrain3D, temporary scenes, and duplicate textures until dependency/provenance checks are complete.

## Stop point

This recommendation document completes the audit phase. It does not implement any item above and does not begin Phase 2.
