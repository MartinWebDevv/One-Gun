# Course records: isolated now, replaceable for multiplayer

The scene is still F6-only. There are no networking or backend calls in these
scripts. Mock party visitors never receive invented run times. A completed local
run is the only gameplay path that submits a record.

## Current ownership

- `agility_space.gd`: course geometry/version, ordered checkpoints and recovery.
- `training.gd`: local pilot's running clock, cancellation, fall penalties,
  movement-assistance classification and accepted finish. It owns the provider.
- `course_records.gd`: roster-scoped lobby records and separately persisted local
  personal bests. Integer milliseconds; a slower finish cannot replace a best.
- `course_board_ui.gd`: Lobby / Your Best / World pages. The physical wall board
  shows the current lobby's standard-run leader and next three recorded runners.

`training.set_records_provider(provider)` is the replacement point for the record
data. The board has no knowledge of ENet, accounts, RPC paths or database tables.
The provider implements:

| Member | Contract |
|---|---|
| `changed` | Emit when available data changes; refreshes wall and open pages. |
| `save_error` | `OK` or local-persistence failure for user-facing feedback. |
| `set_members([{id, name}])` | Stable IDs, current roster; names are presentation. |
| `submit_completed_run(bucket, actor_id, time_ms)` | Accepted positive completed finish; returns success. |
| `lobby_rows(bucket)` | Current members, ascending best time; `-1` means no run. |
| `personal_best(bucket, viewer_id)` | That viewer's best, or `-1`. |
| `world_available()` | False until genuine world records are available. |
| `world_rows(bucket)` | Actual world results, using the same row fields. |

Rows contain `id`, `name`, and `time_ms`. Buckets include the authored course
version, dash capacity, sprint gate, jump launch and standard/assisted class.
Movement-affecting powers/launches/slows encountered during a run permanently mark
it assisted. Gear is not stripped at the course door and GameConfig is never set.

The local file is `user://live_lobby_preview/course_records.json`. It contains
personal records only, not old lobby standings. A hashed signed-in account key is
used when available; signed-out play uses a separate local profile. `Your Best`
resolves the viewer at read time and the runner is captured at start; an identity
change cancels the active run. Automation uses an empty path or its own temporary
artifact file, never this actual personal file.

## When real multiplayer is authorized

1. Supply actual lobby roster IDs through the session/roster boundary and track
   checkpoint order, starts, penalties, cancellation and finish for every runner
   on the host. The current course controller deliberately follows only the F6
   pilot; replacing record data alone does not enable multiplayer gameplay.
2. Replace the local records provider with a host-backed provider. Use existing
   actor IDs and lobby/round epochs; accept host-validated completion, never a
   client's arbitrary elapsed milliseconds. Broadcast record changes as events,
   include a snapshot for late joins, and prune departed members from Lobby.
3. Back personal/world records with authenticated, authoritative course receipts.
   Use a stable authenticated identity for Your Best on each viewer. Keep account
   credentials out of the lobby wire format. Turn on World only once genuine data
   is available; provide pagination and a failure/empty state.
4. Preserve version/rule/category separation and decide the online pause policy
   explicitly (local F6 menus pause the clock). Revalidate late joins, reconnects,
   simultaneous finishes, rejected shortcuts, stale epochs and course revisions.

The board pages and local data contract are ready for those adapters. Transport,
online timing authority and world persistence remain intentionally unconnected.
