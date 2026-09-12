# Hideout entry and multiplayer migration — 2026-09-07

## Implemented entry and menu transfer

Normal client startup keeps the approved Barlow cinematic, then enters
`res://maps/hideout/hideout.tscn`. The player starts alone in the arrival hallway.
No socket opens until an explicit Host, Join, or Find a Match action.

The original `tools/live_lobby_preview/live_lobby_preview.tscn` remains the isolated
F6 rehearsal. Production scripts, scene and artwork live under `maps/hideout/`;
client/server exports exclude tools, so production has no dependency on that folder.

| Destination | Production behavior |
| --- | --- |
| Game Board → Play Here | Reuses game_setup through match_board.gd: all MapRegistry maps, modes, bot/roster slots, teams, rules, presets, private One of Us preference, ready, force start and countdown cancellation |
| Solo / two-player | Existing local and splitscreen match controllers |
| Host / Find a Lobby / Find a Match | Existing ENet browser, code/address, hosting and dedicated matchmaker interfaces |
| Squad | Current real roster, Friends & Invitations, teams/setup and explicit Leave |
| Player Hub | Existing Profile, Locker, Prize Counter and Progression screens and their persistence/backend contracts |
| Escape | Room navigation, settings, release notes, recovery, leave and quit |
| Match / results return | Shared Hideout in the same hosted session |
| Guest leave / host shutdown | Own offline Hideout; a guest leaving does not close the host |

Full-screen menus preserve movement while reserving the cursor for UI and suspend the room's hidden root 3D rendering. Text entry and rebinding reserve movement keys. Other players and host authority continue. The existing map-preview
SubViewport renders only while its Game Board is open. Settings keep their existing
transaction/cancel behavior. Map selection is remembered by HideoutSession;
personal settings and match rules remain owned by PlayerPrefs and GameConfig.

## Shared room authority

NetworkPractice subclasses the existing online Playpen/RoundManager. It reuses
stable RPC paths, actor IDs, MultiplayerSpawner, held-item routing and practice
refills. Hosting/joining upgrades the already-loaded room rather than rebuilding
its architecture during an ENet handshake.

A ready peer receives world inventory/held-gear, active deployable, range, course,
duel and toss snapshots before joining the scene event stream. Each human owns
movement; the host resolves practice effects and outcomes.

- Main hall and spectators are safe. A spatial guard limits effects to the same
  combat area. Crossing the Play Pen boundary clears carried gear, powers and
  owned thrown/deployed effects.
- Practice deaths clear inventory and respawn at the Play Pen entrance after 2s.
- Three range lanes independently cycle 5/10/15/25/30/40/50/75/90/100m. Distance
  and hit counts are shared.
- Course runs use host clocks and ordered checkpoints per actor. Falls add 2s;
  invalid/dead/departing runs cancel. Different movement rules and assisted runs
  have separate buckets. The lobby page is shared and survives match/Hideout returns in the same session; Your Best uses the viewing
  player's local account/profile storage. No world leaderboard service is claimed.
- Scrap Yard admits two actual players. Only the second player calls heads/tails.
  The host selects the result, grants one gun and one melee to the two fighters,
  and places a second melee, one enabled item and one permitted powerup.
  Extra Life/Sticky Hands are excluded. One elimination ends the round; all
  duel gear is retired. Disconnect/leave/countdown cancels the duel.
- Trickshot Toss is one host-simulated social ball with shared score.

Before match departure and return, every peer acknowledges stopping its owned
movement synchronizers. Actors despawn while all peers still have the old scene.
The existing asynchronous map loader and match-ready handshake then take over.

## Current scope and follow-up

This is the first multiplayer entry/return implementation, not completion of the
separate party/backend rollout:

- Access is **Only Me / Unlisted / Public**. Unlisted hides discovery; it is not
  authenticated Friends Only or Invite Only admission.
- Everyone in the current Hideout can play together with Play Here. Atomic
  whole-Squad travel to another host/queue, destination seat reservations,
  admission/rollback and squad-versus-resident membership remain follow-up work.
  Browser/queue actions are offered from the offline home; a shared room is never
  silently disconnected to perform a single-player join.
- The existing hosted transport and configured matchmaking services are reused.
  No service, coordinator, server deployment or public build was published.
- Network protocol is **8**. Both clients and the server need this revision.
  Existing hosted services must be rebuilt/updated before live-service testing.
- While the host is in a match, a late visitor has a local waiting Hideout and
  can spectate via the Game Board. A concurrently simulated waiting world while
  its owner plays elsewhere needs a separate persistent-world server.
- Course personal bests are account-keyed, saved locally, backed up/restored through
  Supabase, and shared with the current lobby on entry or later cloud restoration.
  New online finishes are host-accepted; imported history also includes solo runs
  and is not globally verified. World/verified rankings remain future.
- Human feel, maximum-party stress, adverse latency/reconnect and weaker-laptop
  frame pacing still require real playtesting.

## Verification

Reproducible commands from the project root:

```powershell
python tools/run_hideout_network.py
python tools/run_hideout_ui.py --render
& tools/run_dedicated_server_smoke.ps1 -TimeoutMilliseconds 150000
```

The two-instance harness exercises shared actors/cameras, safe hall, late-join
gear/range state, range settings/hits, host-ordered course records, coin call and
duel cleanup, and two complete match/Hideout return cycles. Course fixtures test
authority/record plumbing; they do not replace running the course by hand.

The menu harness opens real destination screens, checks input/render restoration,
settings cancellation, all ten local roster rows and map persistence. Forward+
1080p Low captures are in `artifacts/hideout_migration/`. Initial sampled room
frames on the development RTX 4060 Ti were around 109–114 FPS and menus 155–165
FPS; these are spot samples, not a weakest-machine or frame-pacing guarantee.
The dedicated suite exercises actual input-driven movement, gun pickup/fire/drop,
melee pickup/swing/hit/drop, item pickup/drop/throw and return.

Manual first test: run matching copies, open Game Board → Host a Hideout on one,
then Find a Lobby or enter its code/address on the other. Walk independently,
test the room activities, ready/start a match, return, then have the guest leave.
Also repeat on the weaker laptop at 1080p Low.

## Scrap Yard multiplayer repair and player HUD — 2026-09-07

The Join the Scrap terminal now stands at the front of the arena inside the room,
clear of the entrance hallway and both routes to the stands. Its interaction
volume and host admission check use the same terminal bounds. Fighters return to
two separate positions by the screen, avoiding overlapping respawn capsules.

Online signup previously left the Scrap panel open through ACTIVE, keeping both
players' input blocked; the original harness called controller methods directly
and missed that UI path. Signup now presents the second player's coin choices,
then dismisses the panel for the flip/countdown/combat. The host waits for each
movement owner's placement acknowledgement using the existing action RPC. Older
pre-teleport movement packets cannot cancel preparation. Arrivals have a 12-second
recovery timeout, and ring bounds remain enforced during combat. Concurrent clicks
from the idle board can claim the two available places. One elimination or a
fighter leaving ends the duel and clears its gear; the existing one-round rules
and allowed powerups are unchanged. All testers should use the updated revision.

`maps/hideout/player_hud.gd` binds the existing stamina, dash/recharge, three
inventory slots, powerups, reload and item-feedback widgets to the local actor in
both offline and shared Hideouts. It creates no extra viewport or match scoreboard.
It hides/suspends under menus and is recreated/rebound when home upgrades into an
online room. Inventory slot construction is shared with the online match HUD;
normal match behavior is unchanged. Match-only All Gun hearts are hidden here.

The regression now uses the actual signup/heads/tails button handlers, tests both
join orders, replays a stale movement position during preparation, checks actual
guest movement after the countdown, one-round cleanup and explicit cancellation.
It also verifies match/Hideout return cycles. The UI harness checks local HUD
binding, live stamina/dash values, menu visibility, and captures the terminal at
1080p Low/Forward+. Multi-machine latency and weaker-laptop playtests remain needed.

Production station authoring can be rebuilt with:
`Godot_v4.7.1-stable_win64.exe --headless --path . --script res://tools/build_hideout_station.gd -- --bake-live-lobby`.

## Selected course runs and live standings — 2026-09-07

Two physical buttons flank the start doorway: Standard and Power-Up Run. Both
clear carried powers (including active shoes), refill normal movement resources,
and arm the selected mode. Crossing the start line clears powers again; Standard
grants none, while Power-Up grants the normal pickup's five-second Speed Surge
and one consumable Extra Dash. The bonuses are not refreshed during the run.
Finish/cancel/death/exit removes course bonuses. No selection defaults to Standard.

Mode is selected explicitly, so an expired Surge does not move a Power-Up finish
into Standard standings. Existing Standard records retain their course bucket;
the controlled Power-Up category is separate from historical arbitrary assisted
runs. Old saved records are not deleted.

Both categories appear on the front wall with player names, ranked bests and live
running times. The open scoreboard updates its existing rows with personal best,
last finish, completed-run count, falls and checkpoint progress. Host acceptance
immediately publishes completed records, including each viewer's personal receipt.
Record details survive a match return with the lobby. Live clock snapshots omit
full record history; display refreshes at 5 Hz, with no per-frame world-tree scan.

Protocol 5 adds course selection/loadout messages. Host/server and every client
must use the updated revision. The coordinator's checked-in protocol setting is
also 5; deployment of that service is separate from client/server build publishing
and was not performed here.

Validation covers physical offline buttons, late-acquired power stripping, normal
Surge expiry, real Extra Dash consumption, owning-client grants/cancel cleanup,
open host personal-best and guest lobby panels updating without reconstruction,
and the existing Scrap/match-return suite. The 1080p Low render harness includes
entrance-button and ten-player wall-board captures.

## Persistent personal bests on lobby entry — 2026-09-08

The wall and Lobby page rank each present player's personal best for the current
course, movement settings and Standard/Power-Up category. Saved bests stay visible
on the wall during a run (an asterisk marks active runners); the opened board
also shows live progress. Last run, falls and finish counts describe this lobby,
not a lifetime total. Importing saved history does not invent new finishes.

Solo and online play now share `user://hideout/course_records.json`, keyed by the
hashed signed-in account ID (or the existing offline local profile). On load,
legacy `online_course_records.json` is merged by taking the faster time in each
identity/category bucket; the legacy file is preserved. A faster accepted finish
replaces the saved best; slower finishes cannot replace it. Records survive a
restart, leaving a lobby and changing the session actor ID. The 2026-09-10 recovery
adds Supabase account backup and restores hidden v2 bests into the current board;
these are still personal receipts, not independently verified world rankings.

After the full scene-ready snapshot, each client shares its own saved times, then
shares again only when the values change (including a delayed cloud restore).
The host binds that upload to the sender's actor ID, validates course buckets and
time bounds, merges faster times and immediately broadcasts the shared standings.
The host imports its own saved times before sending join snapshots. No account ID
is sent to other players; no per-frame file I/O or history upload is added. Protocol
6 adds this RPC, requiring matching clients, server and coordinator configuration.

Verification: `tools/hideout_persistence_validation.gd` exercises disk reload,
legacy migration, account/category isolation, invalid data and faster-only updates.
`tools/run_hideout_network.py` uses separate fixture files for host and guest to
exercise saved PBs on join, improvement/save/broadcast, a slower subsequent run,
match returns and loading the saved best back in the player's own home.

## Compact room UI, course selection and Scrap wins — 2026-09-08

Full-width top/bottom bars and the alias/FPS room labels are removed. The original
Friends orb returns at top right with live social badges; F1 opens Friends directly,
and holding Alt releases the cursor to click it. Escape opens the menu containing
all shortcuts. The real stamina/dash/inventory widgets remain, moved toward the
bottom edge. The redundant text inventory HUD is hidden, and the ready banner
appears only for an actual launch countdown. Normal match HUDs are unchanged.

The last course selection remains armed for retries and survives scene/match
returns in `HideoutSession.course_powerup_selected`. A joining client sends its
preferred mode along with its saved PB upload. Host-selected runs still clear
powers and grant the usual pickups only at the starting line. Wall controls are
flush panels at readable height; START and FINISH titles, trim and underlines use
green for Standard or orange for Power-Up, on the viewing client's instance only.
These accent meshes are excluded from static batching. Old AGILITY prefixes and
RUN / JUMP / DASH signage are removed; course geometry and record keys are intact.

`ScrapWinsBoard` faces the arena from the front wall. Online eliminations award one
host-authoritative win, then the normal reliable duel snapshot updates every board.
`HideoutSession.scrap_lobby_wins` survives normal match returns; NetworkManager's
session teardown clears it on leaving/joining a different Hideout. It is never
saved to disk. Local human wins count; demonstration bots and cancellations do
not. A repeated elimination in RESULT cannot award another win.

Online gear creation/attachment now occurs during the locked preparation phase,
not the frame combat unlocks. Both fighters acknowledge equipment readiness before
the three-second countdown advances; a stalled participant cancels after 12 seconds.
Coin results and the one-gun/two-melee rules are unchanged. Late join still uses the
existing complete-world snapshot. This improves the start transition without
claiming to fix network latency or every possible source of low FPS. Protocol 7
requires matching exported clients, server and coordinator configuration.

`tools/hideout_scrap_profile.tscn` provides repeatable 1080p Low entry/ring/stand and
local duel frame samples (`--hideout-test --profile-label=before`). On the development
RTX 4060 Ti, steady medians were about 6.1 ms, with a 28.4 ms maximum during the
coin/countdown/combat interval and a 93.9 ms local demo actor creation call. These
samples do not reproduce another PC's online latency and are not a weakest-machine
guarantee. Verify combat transitions with friends and on the weaker laptop.

### Minimal Escape menu

Escape now contains only Respawn at Arrivals, Player Settings, Release Notes,
Quit Game, and Leave Hideout when online. A muted, non-interactive two-column
shortcut list replaces the destination buttons: Tab Game Board, H Player Hub,
P Squad, L Locker, F1 Friends, F2 Scrap Yard, F3 Play Pen, F4 Firing Range,
F5 Agility, F6 Course Records. These shortcuts work directly in the room or
from the Escape menu. Escape returns to the room; existing quit/leave confirmation
behavior is retained. No extra navigation page was added.

While Escape is open, the local player can still walk, sprint, jump and dash.
The cursor stays visible and mouse/controller look is suppressed. Combat, pickup,
slot and aim input is suppressed while interacting with the menu; its buttons
accept pointer clicks without keyboard focus stealing movement or jump input.
Closing Escape restores normal look. All shortcut/kiosk menus and their destination overlays share this movement-only policy. Typing in a text field or capturing a new input binding temporarily reserves movement input for that control; gravity continues. Course timing continues while moving through menus. Opaque native menus still suspend hidden room rendering for performance, independently of actor movement.

## Approved purple clubhouse presentation — 2026-09-09

The shared frontend theme now uses plum #352C49, violet #705B87, apricot #F3AA7C, ivory #F4E5D2 and mint #9BCBB3. ThemeManager retains its existing semantic API so older home/setup menus, detailed destinations, standard controls and HUD accents inherit the same palette. OneGunUI uses the existing bundled Barlow Condensed ExtraBold for headings, Fredoka medium for body copy, thin non-glowing borders and compact matte panels. No gameplay-map resources are edited.

The Player Hub portal uses a skin/model-aware portrait on the left and a two-column destination grid on the right, with illustrated closet rack, logo-inspired gold star and ascending-step art. The original destination signals, account/status data and Back handling are retained; focus neighbors follow the grid. Portraits reflect model and color, using the existing static registry (they do not render equipped hats). New icons are 512px runtime imports; their source prompts are recorded in UI/assets/hideout/README.md. No additional portrait SubViewport or runtime image generation is used.

Escape preserves its five contextual actions, quiet shortcuts and movement-only input behavior. Its icons use a cached SVG set. Player Settings retains its transactional settings and preview/cancel contracts with apricot selected navigation and mint sliders. Returning from an overlay re-registers a removed cursor shortcut before checking incoming input.

Production Hideout authoring and station.tscn are recolored together, including the practice wings and matching service floors. Major wayfinding signs are apricot plaques. Small planters and seat upholstery are baked/batched cosmetic meshes with no extra colliders, lights, network messages or frame updates. Course geometry, record keys, gates and duel rules remain unchanged. This is an implementation of the approved palette and layouts, not a replacement of every prop with the concept illustration's invented architecture.

Validation for this presentation pass: headless editor import, frontend theme bake and production station bake passed. Rendered UI validation passed at 1280x720 and 1920x1080, including all four Hub routes/Back, menu cancellation preserving preferences, texture budgets, course controls and HUD restoration. The two-process host/client test completed both match/Hideout returns and Scrap/course checks. The external social service emitted a timeout warning during that test; it is not proof of internet friend-service availability.

The 1080p Low Scrap sample on the development RTX 4060 Ti remained near the prior baseline: duel median 6.042 ms versus 6.037 ms, p95 7.501 ms versus 7.328 ms, with about 129 draw calls in both samples. Transitions still have isolated spikes (33.724 ms maximum during countdown/start; local demo actor creation call 116.468 ms). These are single-run local measurements, not a claim that all hitches or online latency are fixed. A weaker-laptop and friends playtest remains required. Major direction plaques use an unshaded surface for legibility at every lighting tier.

Shortcut-menu input is reserved before UI dispatch by maps/hideout/menu_input.gd. It follows the player input prefix and saved movement bindings so jump/arrow/stick input cannot also activate a focused button. Pointer navigation stays active, and camera look/combat remain blocked until all menus close. Prelaunch, elimination and Scrap placement/countdown locks still take priority.

Validation of shared menu movement: rendered UI checks pass for all ten shortcuts, actual locomotion, fixed camera, jump-vs-button focus, text entry, rebinding and restoration on close. Host and guest checks pass after preserving menu_input during the local-to-host upgrade; two match/return cycles, duels, course records and disconnect cleanup complete without engine errors. No new rendering, physics-query or network synchronization work was added; the input guard checks only the active focus/capture state.

### Single player HUD while hosting

Practice network initialization previously created the inherited OnlineHUD in addition to the Hideout-owned PlayerHUD, duplicating inventory, stamina, dashes and effects after hosting/joining. Practice HUD construction now has a scene override: the standalone arena keeps its online HUD, while the Hideout uses only its own player_hud.gd bound through local_player_ready. Match scenes keep their regular online HUD. Neither duplicate widgets nor a hidden second HUD are instantiated in the Hideout.

Regression validation passes for hosting before any guest arrives, guest arrival, two match/Hideout return cycles, and each player leaving to their own home: exactly one inventory, stamina and dash widget exists and each references the local actor. Match scenes retain exactly one OnlineHUD; Hideouts contain exactly one PlayerHUD and no OnlineHUD. Existing duel, movement/menu, course and persistence checks also pass. The local test used direct loopback joining; discovery-port contention and an external social-service timeout were warnings, so this run does not qualify discovery/social availability.

## September 9 course, Scrap and input repairs

- Agility is a clean movement-only volume, separate from the Play Pen combat bound.
  Entering either door retires carried weapons/items, outside powers and owned effects.
  Both doors have layer-20 ordnance barriers. Bullets and loose loans cannot enter;
  actor effect/pickup guards reject attacks and outside grants in the course.
  Only the course start can grant its normal Speed Surge and Extra Dash.
- The centre divider extends to x=-10 without shifting its far end. Start and
  finish are both x=-12.5, 2.5m inside their doorway. Directional swept crossings
  span the lanes, including their wall edges, and require every checkpoint in order.
  Course geometry is `flow_circuit_v3`. The initial revision hid older-route PBs;
  the 2026-09-10 recovery merges their faster values into the current board while
  retaining their original buckets. Further geometry changes must not reset records.
- A four-sided overhead Scrap jumbotron presents the shared coin and fighter names
  to spectators. Fighter one is red and fighter two is blue, with a neutral VS.
  Spectators use the jumbotron exclusively for the coin; screen coin overlays are
  shown only to duel participants; offline Watch mode has no screen coin. It uses world labels/meshes, with no additional camera, viewport
  or lights. The existing 10Hz state presentation updates it; only the active coin
  flip interpolates its rotation each rendered frame.
- Disarm/drop/pickup preserve the remaining gun reload timer through reparenting.
  Host reload completion addresses the exact gun, including a loose one.
- The winner plays the selected victory animation during a 3s result phase. Fighters
  fade out, acknowledge readiness, return to separate terminal positions and fade
  back in after placement. The overlay is hidden by default and requires explicit
  local-fighter ownership on both fade calls. Spectators (including offline Watch
  mode) and other Hideout residents never fade. A bounded timeout prevents a missing acknowledgement
  from holding the room indefinitely. No room scene reload is needed.
- WindowFocus gates background input and releases stale actions on focus changes.
  Regaining focus restores mouse ownership; Hideout clears a missed Alt-release latch.
  The shared simulation continues while the local window is unfocused.
- Roster appearance changes now hydrate existing host and guest actors in the Hideout,
  so Locker changes are visible without respawning or rejoining.
- Listen-host migration is not enabled in this repair. Tailscale supplies connectivity;
  replacing ENet peer 1 requires a coordinated rehost/reconnect and state handoff.
  Existing dedicated sessions separately support lobby-controller replacement.

`tools/hideout_repair_validation.gd` exercises full-width/directional course crossings,
clean entry/exit, projectile barriers, reload continuity and focus gating. The ENet
harness additionally exercises replicated appearance, disarm during reload and the
victory/return flow. Real Alt-Tab behavior, internet latency, spectator sightlines
and weaker-laptop frame pacing still need human playtesting.


## Course recovery and account backup — 2026-09-10

The v2-to-v3 bucket change hid existing records rather than deleting their files.
Recovery merges the shared/legacy files plus backup/pending writes, keeps source
history, and takes the fastest value per account, movement setup and category.
`CourseCloud.store` is the common solo/online personal cache; the stable record ID
is owned by `course_records.gd`, separately from the room geometry ID.

The linked Supabase migration now stores minimum-only account PBs and improvement
history. Sign-in restores them; new bests save locally before asynchronous backup.
Late cloud replies refresh both the viewer and other lobby members without another
run. Account switches cannot upload/restore another account's pending response.
Cloud failure retains local progress and retries. See `SUPABASE.md` for schema,
recovery behavior, deployment verification, and isolated SQL/client tests.

The multiplayer test also checks delayed cloud restorations on both host and guest
and verifies they do not increment lobby finish counts. Automated peers no longer
restore the real saved Supabase session; fixture files are unique per test run.


## Reload duration after disarm — 2026-09-10

The previous reparent fix called `Timer.start(remaining)`, which also replaced
`wait_time`. The next shot used parameterless `start()` and inherited that short
remainder, sometimes nearly zero. Local and replicated shots now explicitly start
the configured two-second reload. Following the clarified pickup rule, a granted
pickup immediately clears any old reload in both Scrap Yard and regular One Gun.
The next shot still starts the full two seconds. Drops continue the old timer
until pickup; cosmetic reattachment preserves its remaining time/progress.

`tools/gun_reload_validation.tscn` reproduces a transfer with 0.05s remaining,
checks immediate pickup readiness, subsequent local/replicated reloads,
repeated-click rejection, cosmetic reattachment, forced reload and round reset.
The original test reproduced five failures in the shortened-duration code.
The two-peer `tools/run_hideout_network.py` also transfers late in a reload, fires
immediately through the host combat gate with both owners, checks the guest's
replicated reload, rejects repeated requests and waits for normal completion.
No new timers, per-frame work, rendering, or network messages were added.
