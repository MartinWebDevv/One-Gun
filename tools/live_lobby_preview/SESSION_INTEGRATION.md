# Hideout session and Scrap Yard integration boundary

The F6 scene is isolated. No session action calls NetworkManager, opens a peer,
invites an account or loads a match. Native account/Locker overlays still retain
their normal deliberate user-save behavior. Global autoloads initialize normally.

## Session provider

`live_lobby_preview.gd` creates `Session.new()` from `session.gd` in one place.
`game_board_ui.gd` reads that provider and sends actions through the preview root.
It has no transport logic. A future provider should preserve this contract:

| Boundary | Current contract |
|---|---|
| Signals | `changed`, `notice(message)`, `friend_added(name,index)`, `friend_removed(index)` |
| Host and roster | `is_host`, `host_name()`, `guests` (traveling squad), `residents` (other occupants), `member_count()` |
| Access/setup | `set_access(index)`, `set_destination(index)`, `set_local(humans,bots)`; host-only while idle |
| Group travel | `browse()`, `request_join(id)`, `accept()`, `cancel()`, `leave_together()` |
| Readiness/start | `request_ready()`, `all_ready()`, `start_match()`; all-ready never auto-starts |
| Lifecycle | HOME → FOUND → DEPARTING → AWAY; AWAY is only a placeholder screen here |
| Local rehearsal only | `simulate_confirmations()`, `add_public_visitor()`, `start_match(true)` and sample directory |

Real integration must replace simulation controls with authenticated participant
responses, stable peer/account IDs (mock names are not identities), real lobby
access enforcement and authoritative snapshots. Reserve the entire squad's slots
atomically, then commit or cancel all members. A destination filling/disappearing,
refused confirmation, disconnect or timeout must not strand part of a squad.
Treat squad leadership and destination lobby ownership as separate capabilities.
Define host migration/return-home policy before enabling live sessions. A provider
swap alone does not implement that transport and lifecycle work.

Use the existing NetworkManager flow only when the user authorizes connection.
Translate approved setup into GameConfig at that future boundary; UI data in this
preview never shadows production match rules. Keep scene-ready handshake and
host-only match start semantics. Remove simulation-only actions from live UI.
Course records have their own contract in `RECORDS_INTEGRATION.md`.

## Scrap Yard authority

`ScrapYard` is a preview-owned Node, independent of Session and RoundManager.
Its phases are IDLE → CALLING → FLIPPING → COUNTDOWN → ACTIVE → RESULT.
One epoch owns both fighter IDs, second-entrant call, committed random outcome,
start timeline, equipment and result. The UI and both local cameras read this
same state. Public spectators have no fighter capability. Leaving invalidates
combat, destroys equipment/effects and frees extra actors/render views.

For live play, the host must own entrance reservations, second-entrant ordering,
coin generation, equipment spawning and hit/death result. Accept exactly one call
from that second player's peer, publish the same result/start timestamp to both
fighters, and send a snapshot to late spectators. Replicate through stable
actor/round IDs with stale-epoch rejection following existing project conventions.
Do not let clients request their own coin outcome, equipment or result. Preserve
exactly one gun, two melee total, one enabled item and one allowed power, excluding
Extra Life and Sticky Hands. Define fighter-disconnect cancellation and spectator
capacity, then validate simultaneous joins, duplicate calls and delayed packets.

The local demo AI is a simple opponent for F6 testing; it does not replace the
production bot implementation. No account rewards or permanent duel rankings exist.
Trickshot Toss also remains a local toy: a later host-owned ball/score simulation
must broadcast its actual shared state rather than individual clients' scores.
