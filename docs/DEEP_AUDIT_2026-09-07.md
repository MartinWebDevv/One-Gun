# One Gun — Deep application audit

> Follow-up: [quality repair pass and remaining checks](QUALITY_PASS_2026-09-07.md). Findings below describe the pre-fix audit snapshot.

Audit performed September 6–7, 2026. This is an audit of the current working tree, including the uncommitted Hideout prototypes and existing user changes. No production gameplay code, balance, assets, or account data was changed to make checks pass.

**Overall assessment: the core is functioning, but I would not call the entire game quality-cleared yet.** The most important work is cover-consistent combat, correct online bullet presentation, predictable session teardown/loading, and performance on weaker hardware. More content should follow those improvements. Preserve the default one-gun scarcity loop, quick local play, expressive characters, readable combat, and the Forward+ visual identity.

Evidence labels below distinguish **reproduced** behavior, **source-confirmed** problems, **visual recommendations**, and **unresolved** failures. A passing automated check covers its scenario; it is not certification of every possible match.

## What was actually checked

- Read the current architecture, rules, design, performance requirements and known gaps; inspected the relevant gameplay, UI, networking, asset, and prototype code.
- Ran the installed Godot 4.7.1 executable, including headless startup, 37 initial headless suites, 11 initial rendered suites and 4 further rendered checks/diagnostics. Additional targeted probes covered resource loading, collision, deterministic character bounds, startup, package references, and current Trippy camera presentation.
- Loaded and ran **all six registered maps twice**, each with one human actor and nine expert bots, at a 1920×1080 window using Low, Forward+, and D3D12 on the **RTX 4060 Ti**. Checked actor/gun/spawn counts, navigation availability, cleanup counters, and short frame-time samples. Captured each map during gameplay.
- Ran 12 initial localhost multiplayer scenarios plus the original match repeat, a Neon match, diagnostic recovery run, private admission check, lobby authority/M/F/chat check, dedicated match-ticket smoke, and fake-coordinator matchmaking check.
- Inventoried **642 GLBs and 554 PNG/JPEG images**, inspecting GLB mesh/triangle/embedded-texture metadata and image sizes. Attempted 210 scene/material resources; 209 returned resources and the disabled Terrain3D importer failed. Other unused Terrain3D scripts also reported missing extension classes. This is not a claim that every prop was manually viewed from every angle.
- Checked all eight registered human models; six gift models × six rendered poses; 12 hats × eight models × four preview angles; 12 hats × eight models × two gameplay camera modes. Inspected selected fresh gameplay, character, equipment, map, and Hideout captures.
- Ran the new in-project Hideout: **291 checks, zero failures**. Ran the separate older lobby lab too, including its **40 departure/return cycles** and create/free checks.

Runtime tests used isolated application-data folders so normal saved preferences and account sessions were not the test fixture. Native computer-control initialization was unavailable in this environment; rendered Godot automation and captured frames were used. I did not perform a human mouse/gamepad play session. Actual two-machine internet/Tailscale play, packet loss/latency behavior, real-account transactions/rewards, a fresh distributable installation, and the weaker laptop remain unverified by this audit.

## Good — preserve and build on these

| Area | Assessment and evidence |
|---|---|
| One Gun's core identity | In Standard mode, all six map runs contained exactly **one gun**, ten actors and ten authored player-spawn points. Alternative modes and training intentionally have different weapon rules; those are not scarcity bugs. Combat, overtime, new-mode, and player-capacity validations passed. |
| Male/Female models and animation plumbing | Female validation passed **33 bones, 19 named animations, 13 colors, 13 portraits**, decoy behavior and customization. Separate target-rest animation handling is present. Rendered M/F Locker checks passed independent P1/P2 pending choices and transactional save/cancel. Male gameplay/held-weapon captures and six gift-model pose sheets rendered without gross rig explosions. |
| Fair body collision across skins | All eight models use the shared gameplay capsule. When Idle was explicitly reset to the same animation time, all eight bounds checks passed. Larger cosmetic silhouettes do not automatically enlarge the collision body. Keep this separation; do not give a large hat or tail extra damageable area. |
| Crosshair and shot alignment | Production projectile/camera validations passed in solo and splitscreen. The fixture checks the rendered center ray over successive physics frames with a 0.5-pixel tolerance and perturbed camera/muzzle arrangements. This supports the current paired origin/direction calculation; preserve it while improving server validation. |
| Camera collision and pause behavior | Player spring-arm retraction against map geometry passed; irrelevant collision layers did not block it. ADS framing/FOV and camera pause/resume behavior passed. The spectator collision probe passed too. The hat/camera matrix passed all 192 combinations. |
| Input and local splitscreen | Keyboard, mouse, controller button/axis remapping, primary-device switching, P1/P2 routing, pause and scoreboard checks passed. Rendered solo/split migration and input-related checks passed. Real pad hot-plug and long-session comfort still need hands-on verification. |
| Maps and basic navigation | Every registered map loaded and ran. Cat Tower, City environment/replacements/enterable buildings and Trippy runtime checks passed. Neon navigation connected all ten spawn points. Themes remain recognizably distinct in the inspected captures. |
| Network foundations | Named hosting/joining, authoritative lobby controls/readiness/kick, config transfer, M/F roster updates and synthetic localhost chat passed. Online bots, overtime, Playpen, late spectators, and dedicated movement/combat scenarios passed. The unchanged basic match test subsequently passed, as did the Neon repeat. |
| Existing QoL and accessibility | Remappable prompts, inventory/HUD controls, reduced motion/flashing, color/contrast/text options, camera bob/shake controls, settings persistence, friends/presence interfaces and results/readiness flows already exist. They should not be listed as missing. The rendered accessibility adapter and smoke-effect checks passed their focused contracts. |
| Winners Circle and character presentation | Current Winners Circle validation and rendered checks passed, including the user's existing changes. Model/cosmetic/pose integration, progression/catalog and equipment visibility checks passed their local fixtures. Real account settlement was not exercised. |
| Hideout as a local prototype | The shared controller, menus, training, Scrap Yard, contained practice, soft-ball activity, cancellation and return behavior passed its 291 checks. Preferences/match rules stayed intact and networking stayed offline. The warm cream/turquoise space and service fronts are visually coherent. |
| Cleanup in the sampled map loop | After every map unload, tracked tree nodes returned to **29**. In the second cycle, tracked rendering memory returned to **425.8 MiB** each time, with resources/static allocations settling. No monotonic retained-map growth appeared in this limited loop. This does not prove a multi-hour leak-free session. |

## Bad — concrete defects or requirements not currently met

**B1 · High priority · Host shot-origin validation can accept an origin beyond cover.**

Reproduced using the actual `gun.gd` server fire function with a minimal valid-owner/epoch fixture: actor at z=0, wall at z=-5, submitted origin at z=-6.5. The server accepted and broadcast the shot. The current rule permits an origin within seven metres of the holder and has no world-occlusion check. This is a validator weakness; the audit did not establish that the normal client routinely sends this origin.

**Make it Good:** retain the current camera-aligned firing ray, but validate its allowed origin against the authoritative actor/camera envelope and obstructing world geometry. Include finite-value, direction and epoch/ownership checks already present. Allow a deliberate latency tolerance, not an arbitrary seven-metre free origin. Acceptance: normal close/ADS/split shots still track the reticle; a submitted origin across solid cover is rejected; a legitimate shot through an opening is accepted. Evidence: [gun.gd:117](<D:/Godot Projects/one-gun/gun.gd:117>), audit `melee_obstruction_probe.log` and `projectile_probe.gd`.

**B2 · High priority · Dedicated melee candidate selection ignores solid cover.**

The production swing query selects player-layer bodies without querying world obstruction. The isolated probe found a target behind a solid thin wall; the following local/server hit-resolution paths contain no world-visibility rejection. This is source-confirmed with a reproduced candidate query; I did not perform an end-to-end human swing against that fixture.

**Make it Good:** use a shared world-obstructed swing/sweep policy for local, listen-host and dedicated paths. Preserve the intended active window, Reach powerup and weapon reach; test walls, closed corners, doors, openings, very close targets and thrown weapons separately. Acceptance: cover consistently blocks a melee strike without making valid close combat unreliable. Evidence: [melee_weapon.gd:839](<D:/Godot Projects/one-gun/melee_weapon.gd:839>), `:995`, `:1075`; audit `melee_obstruction_probe.log`.

**B3 · High priority · Client-only bullet visuals can continue through a wall after the authoritative bullet is gone.**

Reproduced: the local authoritative bullet was removed on impact; the client-visual bullet still existed at z=-36.3 after passing a wall at z=-5. The fixture wall uses a valid world layer with mask zero. Non-server bullets disable contact monitoring and set their collision mask to zero, and the network path has no per-shot impact/retirement message. Some other wall-mask combinations can stop physical motion, but there is still no general authoritative impact reconciliation. Host hit authority remains separate; this finding concerns visible shot behavior.

**Make it Good:** assign shot IDs, send authoritative impact position/retirement events, and permit immediate cosmetic collision prediction followed by reconciliation. Release the tracer promptly at a confirmed impact. Acceptance: host and client see the shot stop at the same wall/target with no long-lived ghost tracer. Keep the intended projectile speed and damage rules. Evidence: [bullet.gd:13](<D:/Godot Projects/one-gun/bullet.gd:13>), gun spawn broadcast and round-manager event path; audit collision probe.

**B4 · High priority · Live assets exceed the project's performance budgets.**

- The active bot GLB is **660,544 base triangles, 24.7 MiB**, with four 2048² textures. `round_manager.gd` preloads `DummyModel.tscn`, which reaches this model through `botmodel.tscn`.
- The active baseball bat is **89,296 triangles**, with **three 4096² embedded textures**, despite a file size of only 4.3 MiB. Checking only the ten-megabyte threshold misses it.

**Make it Good:** optimize the bot mesh/skin and bat while retaining their silhouette, pivots, skeleton/socket relationships and collision/timing. For the bat, target the existing roughly 15k-triangle/1024² prop budget unless close-view evidence justifies more. Audit generated LODs, texture compression and actual visible cost. The bot already has import LOD generation, so base triangle counts are not a claim that every bot always draws its highest LOD. Acceptance: same combat/cosmetic appearance, lower measured frame time and memory with maximum actors. Evidence: audit `asset_inventory.json`, [botmodel.tscn:3](<D:/Godot Projects/one-gun/botmodel.tscn:3>), [baseball_bat.tscn:3](<D:/Godot Projects/one-gun/baseball_bat.tscn:3>).

**B5 · High priority · Stable Low-preset frame pacing is not established and visible long frames were measured.**

In the warm map pass, Woods had a **100.4 ms** maximum frame and Trippy **73.8 ms**. Woods p95 was **16.88 ms** even on the development GPU. The colder first cycle recorded larger spikes on several maps. These are short engine frame-delta samples with randomized bot activity, not controlled GPU-only benchmarks; they establish a need for profiling, not a root cause by themselves.

**Make it Good:** capture CPU/render/physics events around spawn, first use of effects, death, and map transitions. Start with the confirmed bot/bat outliers and Woods' high draw-call sample. Apply sharing, distance LOD/culling and appropriate batching where measured, retaining nearby atmosphere and combat cues. Re-test the weaker laptop at 1080p Low and splitscreen. Acceptance: approximately 60 FPS with stable frame pacing, plus no recurring spawn/combat/transition stalls. Preserve Forward+.

**B6 · Medium priority · Online teardown/rejection paths are not consistently clean.**

Several functional lobby/exit/One of Us tests completed their intended actions but logged Forest resource-load errors and renderer/object leaks during shutdown. The map itself loaded successfully in the map runs. The version-mismatch test rejected the client correctly, then logged an RPC attempt after disconnection from delayed appearance/session restoration. The dedicated match-ticket runner printed PASS but also logged an unauthorized despawn/cache error.

**Make it Good:** scope asynchronous appearance and map-load completion to the current connection/scene generation; verify admitted/connected status before sending; centralize teardown ordering for spawners, actors and peers. Investigate outstanding threaded menu loads at exit—the code does not clearly own/drain their completion. Make runners fail on actionable engine errors, not only missing PASS markers. Acceptance: rejected join, kick, host exit, guest exit and match-to-lobby return produce no stale RPC, spawn/despawn or unfinished-load errors. Evidence: audit `online_version_mismatch.log`, `online_lobby.log`, `online_exit_flow.log`, `match_ticket_server.log`; [network_manager.gd:995](<D:/Godot Projects/one-gun/network_manager.gd:995>), [menu_map_cycler.gd:137](<D:/Godot Projects/one-gun/menu_map_cycler.gd:137>).

**B7 · Medium priority · Trippy Mountains' first-round intro violates the current documented interior-camera contract.**

The authored marker begins at x/z=(68.235, -56.269), outside the validator's inner PlayArea, and gameplay falls back to **180°** instead of the **40° interior sweep** specified by `docs/ARCHITECTURE.md`. The static validator detects this for all ten spawns. The newer lobby/menu camera presentation check passes; that is a different camera path.

**Make it Good:** re-author the intro marker and per-map sweep override so the whole camera trajectory remains inside the intended presentation area for every spawn. Validate the rendered first-round path, solo and split, with Reduced Motion too. If a deliberate new exterior flyover is intended, reconcile the design/validator and inspect that entire route before accepting it. Evidence: [maps/test/TrippyMountainsMap.tscn:159](<D:/Godot Projects/one-gun/maps/test/TrippyMountainsMap.tscn:159>), [round_manager.gd:2418](<D:/Godot Projects/one-gun/round_manager.gd:2418>), audit `validate_trippy_mountains_map.log`.

**B8 · Medium priority · “Private” is discovery privacy, not admission control.**

A fresh client joined a private localhost lobby through its endpoint without providing its share code. The code controls discovery responses; `_register_client_hello` does not validate a private invite/code. Users can reasonably read “Private” as restricting who may enter.

**Make it Good:** either require host-validated invitation/join proof at admission or explicitly label this mode **Unlisted** and explain that anyone with the endpoint can join. Do not imply account/friends restrictions that are not enforced. Acceptance: UI wording and actual join rules agree, including direct-IP fallback. Evidence: [network_manager.gd:154](<D:/Godot Projects/one-gun/network_manager.gd:154>), `:1617`, audit `private_lobby_host.log` and `private_lobby_client.log`.

## Needs improvement — recommendations

| Area | What needs improvement | Recommendation / completion criterion |
|---|---|---|
| Loading responsiveness | `NetworkManager._start_game` uses synchronous `change_scene_to_file`; lobby preview uses `load(path)`. The warm Trippy resource load alone took about 1.38 seconds in the audit harness. Existing scene-ready/loading recovery does not remove the blocking load. | Give scene loading one owner, show a responsive overlay before heavy work, request resources asynchronously, warm high-cost resources and spread safe instantiation work. Show which peer is loading and a useful retry/cancel path. Profile real UI transitions; harness load times are not a measurement of the final loading screen duration. |
| Online round recovery | The original match run failed HUD/living-state and round-reset assertions; the unchanged repeat, Neon repeat and diagnostic recovery run passed. | Treat as an unresolved race or test-order issue. Add event/epoch timestamps and repeat the lifecycle under latency. Do not mark respawning universally broken or dismiss the first failure without tracing it. |
| Dark-character readability | The captured blue character becomes a very dark silhouette in Woods and Western under Low. Neon also warrants a contrast pass. | Check every color against representative backgrounds; improve restrained character lighting, material response or depth-respecting contrast. Preserve atmosphere and avoid revealing concealed players through walls or smoke. |
| Neon wayfinding | Current asset-dressed Neon keeps color lanes but lacks the `ZoneLabels` names/text checked by the old prototype test; the pre-asset snapshot contains them. Navigation passes. | Restore readable zone/vault callouts in the new art layer or define and test the replacement wayfinding. Avoid relying on color alone. This is a presentation/contract gap, not failed bot navigation. |
| Lobby roster sizing | A source-based validator expects `RIGHT_WIDTH >= 400`; the implementation is 380. This assertion alone does not demonstrate actual clipping. | Render ten-player rosters with long names/team controls at 720p, high text scale, keyboard and controller. Fix measured overflow or revise the obsolete threshold. |
| Animation transition feel | Named clips, retargeting, sockets, shared collision and sampled poses pass. These do not establish that every blend looks good in live combat. | Hands-on M/F and gift-model loops: idle→run→jump→land, held gun, reload, melee, throw, stagger, death and respawn; repeat for online puppets. Watch feet, hand grip, body twist, floating weapons and reset-to-Idle timing. Keep the shared collision dimensions. |
| Export/package hygiene | Very large hat masters have no live scene references, but `all_resources` exports do not explicitly exclude `models/cosmetics/hats/source/**`. The source White Fedora alone is 79.1 MiB. Docs/screenshots and other development resources also merit inspection. | Keep masters safely outside runtime import/export scope, or explicitly exclude them. Inspect the actual exported PCK and cold-install size; source file totals are not final package sizes. Keep optimized runtime hats. |
| Validation reliability | Bounds used a non-reset animation phase; a player-render test expected keyboard/controller focus while in mouse mode; menu tests still expect Neon to be newest after Trippy was added. Some runners accept PASS plus errors. | Reset animation time in bounds tests; enter the intended input mode before asserting focus; derive newest-map expectations from the registry; distinguish live assets from intentionally disabled editor tools; fail on actionable engine errors. Do not change correct gameplay merely to satisfy stale fixtures. |
| Documentation | `DESIGN.md` still describes local-only/stubbed online, eight actors, no bot consumable use, one shared human rig and no combat SFX. Current implementation/rules differ. | Reconcile DESIGN with current GAME_RULES/ARCHITECTURE and separate future intent from shipped behavior. This prevents future “fixes” from undoing working features. |
| Hideout usability | The physical space is attractive and functional, but reaching services can involve substantial traversal. Activity destinations and shortcuts need to stay obvious. | Keep direct service shortcuts alongside walk-up kiosks, consistent contextual prompts and a short first-visit orientation. Preserve the open social space; test travel time rather than filling every empty area. |
| Hideout frame outlier | The short spectating sample had a 229.6 ms frame while its p95 was 9.35 ms. Other Hideout views were smooth in the sample. | Trace first-use/spectator transitions and warm required assets. Reproduce in an isolated longer run before assigning a cause. Do not call the entire Hideout slow based on one outlier. |
| Disabled Terrain3D / old content | Explicitly loading unused Terrain3D editor/example content fails because its native classes are disabled. Live maps work and exports exclude it. | Keep the extension disabled and excluded until a compatible build is deliberately adopted. Isolate/archive reference-only content and tag it in resource audits. Do not enable it just to make an indiscriminate scan green. |

## Map-by-map results

Short warm samples: 8 seconds warm-up followed by 6 seconds recorded per map, one human + nine expert bots, Low at a 1920×1080 window (Low's normal 75% 3D render scale), uncapped. These are observed engine-frame intervals. Bot action/camera visibility varied; some earlier checks ran concurrently. They do not establish comparable fixed-camera performance rankings or weaker-laptop readiness.

| Map | Median / p95 / maximum frame | Draw calls sampled | Audit judgment and next improvement |
|---|---:|---:|---|
| Whispering Woods | 12.87 / 16.88 / 100.41 ms | 2,641 | Loaded, played and cleaned up; highest priority for draw-call/visibility profiling and dark-character contrast. No authored OccluderInstance3D was found in this sample; choose occlusion only where measured useful. |
| Western Town | 6.89 / 11.84 / 24.04 ms | 318 | Theme and gameplay load intact; inspect character lighting and interior camera/collision comfort. Warm load + instantiation was approximately 1.0 second. |
| Gun Square | 9.43 / 13.50 / 36.56 ms | 903 | City geometry/building checks passed; keep the readable art direction and profile first-use/transition spikes. |
| Cat Tower | 6.97 / 11.52 / 28.15 ms | 784 | Runtime and dedicated map checks passed; human vertical navigation, ledge encounters and tight camera angles still need a playtest. |
| Neon Circuit | 6.76 / 11.65 / 20.19 ms | 560 | Spawn/navigation and repeated online match passed; restore/reconcile zone callouts and check low-light silhouette readability. |
| Trippy Mountains | 9.67 / 15.11 / 73.80 ms | 1,071 | Runtime collision/navigation validation passed; fix/reconcile the intro path and improve load/frame spikes. Lobby/menu camera presentation already passes. |

**Hideout:** split Scrap Yard median/p95 6.02/8.50 ms; populated Hideout 5.93/7.73 ms; spectating 6.43/9.35 ms with the isolated 229.6 ms outlier. Tracked rendering memory was roughly 760–772 MiB in these views. These are development-machine samples, not laptop qualification.

## Missing features and One Gun QoL — suggested order

These distinguish unfinished functionality from proposed new conveniences. Friends, invites, customization, progression, remapping, accessibility and practice are already present in some form.

1. **A real Hideout entry and session handoff.** The new Hideout is F6-only, unreferenced by main menu/map selection and excluded with tools from exports. Its squad/privacy/directory/travel behavior is an in-memory rehearsal. Connect it through a defined authoritative provider, preserve the party across lobby/match/return, and keep direct quick play available. Do not expose mock public/friends behavior as a finished online service.
2. **Recovery from brief disconnects.** Reconnect/rejoin reservation and a clear listen-host-loss policy remain unfinished. Prioritize returning to the same match/role when possible, with an understandable reason when impossible. Dedicated continuity is useful; full peer host migration need not be the first implementation.
3. **Enforced Friends Only admission.** The live online screen explicitly disables Friends Only. Existing friendship/invitation UI is not the same as a friends-only join rule. Enforce accepted-friend identity at admission before enabling it.
4. **An optional in-match connection-quality display.** I did not find a player-facing latency/loss/connection-health display in the reviewed UI. Show concise connection trouble and who is still loading, and provide a copyable diagnostic summary. Do not cover the combat HUD with developer counters.
5. **A short, playable One Gun introduction.** Account/startup onboarding exists, but a guided combat lesson was not found. Use the Hideout to teach taking/disarming the single gun, reload exposure, melee/throw timing, stamina/dash, recovery and useful cover. Make it optional and replayable.
6. **Clearer shot/hit outcome feedback.** This is a proposed refinement: brief, consistent cues distinguishing world impact, shield/protection, disarm and elimination. It should explain a confusing encounter without granting hidden positional information or adding screen clutter. Fix actual cover and bullet-visual errors first.
7. **Optional named local guest profiles.** P2 appearance is intentionally session-only. Allow a returning local player to restore their preferred name, model, color and controls without changing the quick guest default.
8. **Live, validated Hideout records.** Course/world-record presentation has a local/provider seam, but remote authoritative records are not connected in the prototype. Publish a clear local-best experience first; attach authenticated validation before presenting global competition.
9. **Finish visual mappings for existing cosmetic categories.** Hats are the main mapped wearable art today; clothing/accessories and some badge/weapon-skin/pose mappings remain incomplete according to current integration docs. Finish the models/preview/equipment consistency before broadening the catalog. Hidden gift models being entitlement-only is intentional, not a missing public selector.

## What should happen first

1. Fix/reconcile B1–B3 and add cover/impact checks that use the same paths in local, listen-host and dedicated play.
2. Optimize the confirmed live bot/bat outliers, then profile Woods/Trippy and transition spikes at 1080p Low. Re-test a build on the weaker laptop.
3. Make network rejection/exit/loading clean, resolve the intermittent reset failure, and align private-lobby wording/admission.
4. Repair the Trippy intro and validation/documentation mismatches; complete human M/F/controller/camera and real two-machine checks.
5. Integrate Hideout/session recovery and the highest-value QoL in small steps, retaining instant local play.

## Evidence and reproduction notes

The audit folder contains raw logs, JSON results, asset metadata, fresh captures and narrowly scoped diagnostic fixtures. An automatically generated result index appears below. Initial failures are retained; diagnostic repeats are additional evidence, not replacements for the original record.

- `map_runtime.log` and its original metadata came from an early incorrectly ordered audit harness and are **not application findings**. Use `map_runtime_valid.log` and `maps/runtime.json`.
- The original character bounds failures disappeared after explicitly resetting Idle to time zero. No production model was resized.
- The original player-render return-focus failure disappeared when the diagnostic entered controller mode. Pointer mode intentionally leaves controller focus unset. No production focus behavior was changed.
- Trippy's lobby/menu camera pass does not override its separate first-round intro failure.
- Resource counts and tracked rendering memory are Godot counters, not the process's total RAM/driver allocations.
- Four tracked camera reference PNGs refreshed by the existing validator were copied into the audit folder and restored to their original repository bytes. Existing user code edits were preserved.

[Audit evidence folder](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906>) · [Asset inventory](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/asset_inventory.json>) · [Map samples](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/maps/runtime.json>) · [Character/camera contact sheet](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/character_camera_contact.jpg>)

### Initial suite results

These show exit status and engine-error lines separately. Interpret failures using the findings above.

| Suite | Exit | Error lines |
|---|---:|---:|
| [camera_collision_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/camera_collision_validation.log>) | 0 | 0 |
| [character_size_hitbox_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/character_size_hitbox_validation.log>) | 1 | 7 |
| [combat_rules_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/combat_rules_validation.log>) | 0 | 0 |
| [female_player_v2_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/female_player_v2_validation.log>) | 0 | 0 |
| [player_v2_asset_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/player_v2_asset_validation.log>) | 0 | 0 |
| [goldfish_bag_character_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/goldfish_bag_character_validation.log>) | 0 | 0 |
| [cosmetic_body_binding_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/cosmetic_body_binding_validation.log>) | 0 | 0 |
| [new_character_integration_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/new_character_integration_validation.log>) | 0 | 0 |
| [damage_direction_indicator_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/damage_direction_indicator_validation.log>) | 0 | 0 |
| [decoy_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/decoy_validation.log>) | 0 | 0 |
| [city_asset_replacement_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/city_asset_replacement_validation.log>) | 0 | 0 |
| [cat_tower_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/cat_tower_validation.log>) | 0 | 0 |
| [city_environment_map_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/city_environment_map_validation.log>) | 0 | 0 |
| [enterable_city_buildings_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/enterable_city_buildings_validation.log>) | 0 | 0 |
| [player_capacity_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/player_capacity_validation.log>) | 0 | 0 |
| [space_station_prototype_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/space_station_prototype_validation.log>) | 1 | 1 |
| [gameplay_packet_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/gameplay_packet_validation.log>) | 0 | 1 |
| [high_priority_09_18_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/high_priority_09_18_validation.log>) | 1 | 1 |
| [all_gun_overtime_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/all_gun_overtime_validation.log>) | 0 | 0 |
| [new_game_modes_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/new_game_modes_validation.log>) | 0 | 0 |
| [overtime_transition_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/overtime_transition_validation.log>) | 0 | 0 |
| [input_remap_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/input_remap_validation.log>) | 0 | 0 |
| [hat_fitting_tool_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/hat_fitting_tool_validation.log>) | 0 | 0 |
| [menu_systems_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/menu_systems_validation.log>) | 1 | 1 |
| [playpen_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/playpen_validation.log>) | 0 | 0 |
| [equipped_cosmetic_visibility_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/equipped_cosmetic_visibility_validation.log>) | 0 | 0 |
| [social_system_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/social_system_validation.log>) | 0 | 1 |
| [progression_catalog_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/progression_catalog_validation.log>) | 0 | 0 |
| [winners_circle_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/winners_circle_validation.log>) | 0 | 0 |
| [supabase_ui_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/supabase_ui_validation.log>) | 0 | 0 |
| [victory_move_integration_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/victory_move_integration_validation.log>) | 0 | 0 |
| [supabase_main_menu_validation](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/supabase_main_menu_validation.log>) | 1 | 6 |
| [validate_trippy_mountains_map](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/validate_trippy_mountains_map.log>) | 1 | 12 |
| [validate_trippy_mountains_runtime](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/validate_trippy_mountains_runtime.log>) | 0 | 0 |
| [migration_solo](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/migration_solo.log>) | 0 | 0 |
| [migration_split](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/migration_split.log>) | 0 | 0 |
| [hideout_full](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/hideout_full.log>) | 0 | 0 |
| [render_projectile_solo](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_projectile_solo.log>) | 0 | 0 |
| [render_projectile_split](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_projectile_split.log>) | 0 | 0 |
| [render_new_characters](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_new_characters.log>) | 0 | 0 |
| [render_player_v2](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_player_v2.log>) | 1 | 12 |
| [render_ads](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_ads.log>) | 0 | 0 |
| [render_menu_clicks](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_menu_clicks.log>) | 0 | 0 |
| [render_winners_circle](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_winners_circle.log>) | 0 | 0 |
| [render_hat_interactions](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_hat_interactions.log>) | 0 | 0 |
| [render_hats](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_hats.log>) | 0 | 0 |
| [render_gameplay_hat_camera](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_gameplay_hat_camera.log>) | 0 | 0 |
| [render_hideout](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_hideout.log>) | 0 | 0 |
| [online_match](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_match.log>) | 1 | 2 |
| [online_lobby](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_lobby.log>) | 1 | 5 |
| [online_named_lobby](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_named_lobby.log>) | 0 | 0 |
| [online_exit_flow](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_exit_flow.log>) | 1 | 10 |
| [online_client_exit](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_client_exit.log>) | 1 | 5 |
| [online_online_bots](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_online_bots.log>) | 0 | 0 |
| [online_overtime](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_overtime.log>) | 0 | 0 |
| [online_one_of_us](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_one_of_us.log>) | 1 | 5 |
| [online_playpen](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_playpen.log>) | 0 | 0 |
| [online_late_spectator](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_late_spectator.log>) | 0 | 0 |
| [online_dedicated](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_dedicated.log>) | 0 | 0 |
| [online_version_mismatch](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_version_mismatch.log>) | 0 | 1 |

### Additional evidence

- [bounds_diagnostic](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/bounds_diagnostic.log>)
- [melee_obstruction_probe](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/melee_obstruction_probe.log>)
- [render_player_diagnostic](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_player_diagnostic.log>)
- [render_character_customization](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_character_customization.log>)
- [render_accessibility](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_accessibility.log>)
- [render_smoke_cloud](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/render_smoke_cloud.log>)
- [trippy_camera_current](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/trippy_camera_current.log>)
- [map_runtime_valid](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/map_runtime_valid.log>)
- [online_match_repeat](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_match_repeat.log>)
- [online_match_neon](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_match_neon.log>)
- [online_diagnostic_host](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_diagnostic_host.log>)
- [online_diagnostic_client](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/online_diagnostic_client.log>)
- [private_lobby_host](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/private_lobby_host.log>)
- [private_lobby_client](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/private_lobby_client.log>)
- [lobby_authority_host](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/lobby_authority_host.log>)
- [lobby_authority_client](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/lobby_authority_client.log>)
- [match_ticket_server](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/match_ticket_server.log>)
- [matchmaking_fake_coordinator](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/matchmaking_fake_coordinator.log>)
- [standalone_lobby_lab](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/standalone_lobby_lab.log>)
- [startup_flow](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/startup_flow.log>)
- [resource_audit](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/resource_audit.log>)
- [client_package_source](<D:/Godot Projects/one-gun/artifacts/deep_audit_20260906/client_package_source.log>)
