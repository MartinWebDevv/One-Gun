# Scrap Yard expansion — 2026-09-06

The room expanded from **36 × 34 m to 54 × 50 m**; the ring grew from **18 m to
30 m diameter**, with 2.78 times the fighting area. Floor-to-ceiling height is
11.2 m. Cover and hurdle heights remain character-sized; their spacing, fighter
starts, supply marks and audience positions now fit the larger ring. Three tiers
of longer spectator seats replace two. The original Play Pen entrance stays put.

Station bake passed. The rendered full suite passed 289/290 checks and exposed a
demo-bot stalemate after disarming in the larger arena. The preview-only bot now
seeks the loose gun, uses the actual muzzle for aim, handles overhead shots and
avoids zero-length facing updates. **All 51 focused rendered Hideout checks then
passed**, including a deliberately forced disarm followed by recovery and an
actual one-round combat victory. Pickup verification uses the event so an
immediate pickup/shot/win in one frame is captured. No script/resource errors
occurred in the final focused run; preferences/rules remain unchanged and the
network remains offline. Production player/bot controllers are unchanged.

Final entrance, stands and two-player images were reviewed. The expanded Low
split-screen sample (RTX 4060 Ti, 1080p window, 75% 3D scale, two fighters and
no mock audience) measured 5.998 ms median, 7.544 ms p95 and 12.267 ms maximum
over six seconds, with 197 draw calls and about 742.7 MiB tracked VRAM. This is
a short development-machine sample, not a weaker-laptop qualification. Test the
new spacing and controller feel in F6 and check 1080p Low on the weaker laptop.

The older checkpoint and measurements below describe the preceding smaller room.
Expansion captures use `63_larger_scrap_room`, `64_larger_scrap_stands` and
`65_larger_scrap_ring`. Reproduce with:

```powershell
python tools/live_lobby_preview/run_checks.py playtest --hideout-only
python tools/live_lobby_preview/run_checks.py capture --scrap-size-only
```

---

# Hideout / Scrap Yard checkpoint — 2026-09-06

**290 behavioral checks passed** in the off-screen rendered Godot 4.7.1 Forward+
suite, exit 0, with no script/resource errors. Station bake and headless startup
passed. The preceding headless revision passed 278 checks; the rendered suite
adds actual duel gunfire, spectator boundaries, P2 movement and ball scoring.

## Verified behavior

- Private-by-default session; inviting friends requires no separate Host step.
  Public visitors remain separate from the traveling Squad. Joining humans shrink
  bot capacity. Browser filtering and commit-time revalidation protect the entire
  squad, including when destination capacity changes after confirmation begins.
- One person's confirmation cannot travel the whole group. A visited lobby's
  host owns setup/start. Leave Together restores the squad's original map/access,
  leaving other occupants behind. All-ready never automatically launches; host
  starts the countdown explicitly. Cancelling preserves participants.
- Exactly two outer Play Pen supply grids (46 slots) leave the back-centre
  approach open. Scrap Yard coin accepts only the second entrant's first call;
  no reroll is accepted. Reveal/countdown lock combat before allocation. The
  second entrant's correct/incorrect call selects complementary gun/melee roles.
- Exactly one duel gun and two melee total; allowed power pool excludes Extra
  Life/Sticky Hands. Real gunfire eliminates the opponent using the unchanged
  projectile implementation. One elimination produces one result without the
  ordinary Play Pen respawn. Returning clears held/loose gear and extra actors.
- Opening cover blocks spawn-to-spawn shots. Full-height ring collision blocks
  projectiles above the spectator rail. Foyer/stands reject damage. Foreign
  practice equipment is not adopted by an active duel and is retired. An
  autonomous two-bot spectator match reaches a winner with real combat.
- Local P2 uses `p2_` movement actions with the production controller. Both views
  share one world and one coin state; each has a reticle and inventory/stamina/
  dash readout. Leaving restores the root camera and temporary input routing.
  Repeated entry/cancellation leaves no fighter nodes or SubViewports behind.
- Trickshot Toss throws only at its nearby station, scores a downward basket
  crossing, resets out of bounds/after its lifetime, and stops processing at rest.
- Previous full-wall Hub/corner clearance, shared flooring, recessed arrival
  doors and real controller navigation still pass. All current character rigs,
  skins/cosmetics, shared account menus and menu/control return paths pass.
- Three independent range targets and an actual 100 m projectile hit pass. The
  unchanged controller clears the agility vault, 8 m gap, rounded turn, cover
  lines, step transitions and finish dash. Ordered checkpoints, fall penalties,
  cancellation, assisted categories, local lobby/personal records and persistence
  all pass. Automation does not write the player's real preview record file.
- Saved preferences and GameConfig remain unchanged; the multiplayer peer stays
  offline. No replication nodes, live invitations, rewards or match loads occur.
  Shared Hub screens retain their normal deliberate manual account-save behavior.

## Visual review

Actual 1920 × 1080 player-camera images were captured at Low and saved quality.
The new foyer sign was moved to the side after the first capture showed it
blocking the arena. Final images show an open approach, turquoise/cream room,
coral cover, honey trim and lavender stands. Game Board, privacy/map setup,
whole-squad browser, solo coin, shared split coin, per-view HUD and central toss
were inspected. The full-wall Hub, wall-mounted doors, range and course remain.

Captures `50..62` are under `artifacts/` (Low) and `artifacts/saved_quality/`.
The rendered validation's `39..41` record-board captures contain actual automated
course results, not claimed human records. Native UI/3D geometry was reused;
no new generated meshes, textures or fonts were added.

## Performance and remaining limits

RTX 4060 Ti, Forward+ / D3D12, 1920 × 1080, six-second samples. Low uses 75% 3D
scale; saved settings used 100%. Both local split views inherit quality settings.
The root 3D render is disabled while those two views exist, avoiding a third
render. Static geometry batches remain separated by room/material/spatial region;
local lights are shadowless. The idle soft ball stops its physics processing.

Crowded samples contain ten Hideout visuals plus the regular sparring actor.
Spectator samples create two demo fighters, hide the regular sparring actor and
limit visible audience for a ten-person composition; hidden nodes still appear
in the JSON character count. Split samples contain the two fighters and two
mock visitors. The Low spectator sample reached RESULT; Saved remained ACTIVE,
so they are not identical combat workloads. No uncapped-headroom claim is made.

| Setting / view | Median ms | p95 ms | Max ms | Draw calls | VRAM MiB |
|---|---:|---:|---:|---:|---:|
| Low / Crowded Hideout | 6.100 | 9.784 | 145.823 | 385 | 758.7 |
| Low / Local split duel | 6.056 | 7.038 | 11.620 | 165 | 758.6 |
| Low / Spectator view | 6.059 | 6.524 | 24.038 | 106 | 770.5 |
| Saved / Crowded Hideout | 6.303 | 9.376 | 11.468 | 385 | 901.8 |
| Saved / Local split duel | 6.065 | 6.962 | 8.936 | 163 | 1044.5 |
| Saved / Spectator view | 6.414 | 9.736 | 44.827 | 105 | 916.7 |
| Low / isolated repeat | 6.077 | 7.519 | 9.507 | 385 | 751.0 |
| Low / after six duels | 6.062 | 6.868 | 17.945 | 385 | 754.6 |

The first Low crowded sample had an isolated 145.823 ms frame; it did not recur
in the focused repeat (max 9.507 ms) or post-cycle sample (max 17.945 ms). Its
cause was not established. Spectating also recorded 24–45 ms peaks. These are
retained in the results rather than described as fully hitch-free performance.
The focused diagnostic records process/physics timing with the worst frame for
future comparison. This is not a weaker-laptop qualification or sustained
combat/transition stress test.

Six full local-duel entry/exit cycles returned to **3,773 nodes every time**.
Post-exit VRAM stayed **791,252,992 bytes** across all six. Tracked static memory
changed from 195,423,486 to 195,439,590 bytes (~16 KiB), with no retained actor or
viewport count growth. Initial resource warming is separate from that comparison.
See `scrap_lifetime_profile.json`; this does not measure total process working set
or production map transitions.

Human F6 playtests are still needed for controller hardware/hot-plug behavior,
aiming, camera comfort, cover/racing-line choices, repeated death/ability stress
and duel balance. **Test 1080p Low on the weaker laptop before live integration.**
Online authority, real parties and shared world/course services remain disconnected.

## Reproduce

Open `res://tools/live_lobby_preview/live_lobby_preview.tscn` and press F6.
F5 still starts the normal game. Run GPU checks serially:

```powershell
python tools/live_lobby_preview/run_checks.py bake
python tools/live_lobby_preview/run_checks.py validate
python tools/live_lobby_preview/run_checks.py playtest
python tools/live_lobby_preview/run_checks.py capture --hideout-revision
python tools/live_lobby_preview/run_checks.py capture --hideout-revision --saved
python tools/live_lobby_preview/run_checks.py capture --hideout-profile-only
```

Logs/images/profiles are under ignored `artifacts/`. Original preview scripts for
this revision were backed up under `artifacts/before_scrap_yard/`. Unrelated
pre-existing project changes were preserved. `README.md` explains controls;
`SESSION_INTEGRATION.md` and `RECORDS_INTEGRATION.md` describe future provider work.
