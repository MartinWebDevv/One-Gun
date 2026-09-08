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

Full-screen menus suspend the local character's input and the room's root 3D
rendering. Other players and host authority continue. The existing map-preview
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
- Network protocol is **5**. Both clients and the server need this revision.
  Existing hosted services must be rebuilt/updated before live-service testing.
- While the host is in a match, a late visitor has a local waiting Hideout and
  can spectate via the Game Board. A concurrently simulated waiting world while
  its owner plays elsewhere needs a separate persistent-world server.
- Course personal bests are device-local receipts of host-accepted runs, not
  globally authenticated records. World/verified record storage remains future.
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
