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
- Network protocol is **4**. Both clients and the server need this revision.
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
