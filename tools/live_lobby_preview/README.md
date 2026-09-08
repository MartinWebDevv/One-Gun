# The Hideout — standalone F6 preview

Open **`res://tools/live_lobby_preview/live_lobby_preview.tscn`** in One Gun and
press **F6**. F5 still starts the normal game. This scene has no main-menu,
match-setup or map-registry entry. The existing `tools/**` export exclusion applies.

## Layout

The 54 × 60 metre Hideout keeps its central social pit and generous
walking routes. **Player Hub fills the west wall:** a 59.5 metre canopy, four
14.6 metre service bays, tiled apron, warm practicals, benches and recessed desks.
The main Player Hub sign hangs from the ceiling on brass rods. Locker and Prize
Counter form the Appearance half; Profile and Progression form the Career half.

Squad and Game Board use matching cream walls, masonry, painted canopies and timber.
Their service fronts retain breathing room at the corner. A continuous L of
world-aligned one-metre checker tiles joins both wings, with matching colors and grout.
The Hub's backing, canopy and tiled apron now terminate at both end walls, and
its rear is flush to the west wall. The combined Squad/Game Board unit is against
the north wall, with no walkway left behind it.

The welcome entrance is a real recessed hallway beyond the south wall. The pilot starts on
its raised floor behind closed sliding doors, waits 1.4 seconds, then the doors
open at the wall plane over 0.85 seconds. A landing and six 0.2 metre treads lead
down into the concourse. The 13 metre hallway has room for the normal camera.

The Play Pen entrance is now flush with the north wall. Its orange boundary is
at the wall; a short stair vestibule descends into the arena. All weapons and
items rest on the floor in the two outer grid groups, with their individual
visual origins accounted for. The black podiums and small front shooting bays
have been removed.

The **firing range branches east** from the Play Pen: three separate lanes with
independent wooden targets, each adjustable through **5, 10, 15, 25, 30, 40, 50,
75, 90 and 100 metres**, then back to 5. Distances use the painted firing line.
Interact at a lane console to cycle its distance, or use **Esc → Firing Range /
Distances** to select a distance directly for any lane. Real gunshots flash the
targets and update reusable hit counters. Bring a gun from the floor-loot grid.

The **agility room branches west**, opposite the range. Its 82 × 44 metre flow
circuit has one start and one finish door: a long launch straight, a 0.9 metre
vault, an 8 metre gap with a 16 metre landing, a broad rounded turn, low cover
with alternate racing lines, knee-height step transitions, and a finish dash.
It fits the existing 10 m/s run, 7 m/s jump launch, 6 metre dash burst and 0.55 m
step-up. Sprint is normally disabled; no movement tuning or GameConfig is changed.
The old beam and tight slalom are removed.

Enter to start; five checkpoints must be cleared in order. Falls return to the
last checkpoint and add two seconds. Menus pause the clock; death, rule/identity
changes or leaving early cancel the run. Existing movement powers remain usable,
but assisted runs have separate records. **Esc → Agility / Time Trial** explains
the route and returns the player to the start door.

The physical **record board sits between Start and Finish**. Interact, or choose
**Esc → Course Record Board**, to open Lobby / Your Best / World. Lobby lists only
current participants and their best completed times this session; unrun visitors
show no fabricated score. Your Best resolves from the viewing player's stable
identity and persists locally across F6 runs. Standard/assisted records and
different course versions, dash counts, sprint settings and jump settings stay
separate. World is explicitly unavailable until the online course opens.

The local provider never hosts, joins or calls a backend. Personal records use
`user://live_lobby_preview/course_records.json`, isolated from match/profile
progression. Signed-in identities are hashed; signed-out play has its own local
profile key. Automation uses memory or a disposable file under `artifacts/`.
See `RECORDS_INTEGRATION.md` for the provider contract and future multiplayer work.

All three areas remain connected in the same scene. Range and agility belong to
the Play Pen containment boundary; crossing between them preserves equipment.
The warm palette uses cream floors, turquoise walls, coral panels, honey/brass trim and lavender seating. Room proportions stay the same for solo players and larger groups.

The pilot instances the existing `player.tscn`, using saved P1 controls, camera,
character skin/model and cosmetics. A preview-only script subclass adds spatial
combat checks; the production player/controller is unchanged. All eight current
character rigs remain supported. The nine optional party visitors use existing
character visuals. A separate local sparring actor lives inside Play Pen.

## Contained Play Pen

- Real guns, melee, items and enabled powerups use their existing gameplay scenes.
- The documented Playpen supply set defines 46 slots: two sets of two guns,
  five melee weapons, nine items and seven powerups. All four practice guns remain in their floor-grid slots. Disabled items/powers follow GameConfig and leave
  their slots empty; the preview does not change match settings.
- Fixed supplies refill after two seconds. Unheld loose equipment is cleaned up
  after two seconds at rest. Active deployed effects retain their normal lifetimes.
- Walking or dashing out clears weapons, both item slots, powers, shoes and
  temporary combat effects immediately. Carried gear is destroyed, not dropped
  into the main hall. The departing owner's deployed/thrown gear is also retired.
- The barrier admits players and cameras while stopping bullets and thrown gear.
  Script-driven projectiles are also checked against the room bounds. Main-hall
  actors cannot collect practice gear or receive practice damage/status effects.
- Death returns the pilot to the safe side of the entrance line after two seconds,
  with empty inventory and the same gameplay camera. No match spectator is created.
- The sparring partner starts as a passive target. Use the arena's entrance-side terminal, or **Esc → Play Pen / Sparring**, to enable return fire or
  disable it. The partner also respawns at the barrier, on its inner side.

This is local practice in the unlinked F6 scene. The existing online Playpen map,
round manager, match rules and network implementation are unchanged. No actual
match rewards, scoring, matchmaking or invitations are created by this preview.

## Player Hub and controls

The four physical bays open the existing Locker, Prize Counter, Profile and
Progression screens on deliberate Interact input. H opens the existing Player Hub.
Closing a screen preserves position and camera direction. The Profile display
uses the saved portrait and alias; its runtime texture avoids changing the shared
UI asset importer. Decorative prizes/milestones make no ownership or price claims.

**Shared Hub screens retain normal preference/account behavior.** Deliberate
saving, equipping or purchasing has its usual effect. Automated verification
previews and cancels without purchases, grants or preference changes.

| Action | Control |
|---|---|
| Move, aim, jump, dash, sprint, fire, throw, inventory | Existing saved P1 controls |
| Use kiosk / request nearby pickup | Saved Interact action |
| Game Board / Player Hub / Locker / simulated Squad | Tab / H / L / P |
| Confirm readiness or travel / cancel rehearsal | R / X, or on-screen buttons |
| Preview menu, including sparring controls | Esc / controller Menu |
| Low preview / saved graphics | F1; does not save a graphics change |
| End the test | F8 in Godot, or Stop Preview in the menu |

Controller users can reach stations and sparring settings through the focusable
preview menu. Prompts follow the saved Interact binding. Pickup names appear
within 12 metres; large armory signs provide distant wayfinding.

## Squad, Game Board and Match Status

The Hideout begins **Invite Only**; there is no extra Host step before inviting
friends. **P / Squad** simulates invitations and shows the traveling group
separately from other lobby occupants. **Tab / Game Board** has two choices:

- **Play Here**: the host chooses the map, bots and Invite Only / Friends Only /
  Public access. Public access exposes a simulated visitor button. Joining humans
  release bot capacity to preserve the ten-actor cap. Ready Up requests each
  occupant's confirmation; even when everyone is ready, the host must press Start.
- **Find a Lobby**: show only sample rooms with capacity for the whole squad.
  The local player confirms travel; Simulate Others Confirming rehearses the
  remaining responses. Capacity is checked again at commit. If it changed, nobody
  moves. A thirty-second travel timeout also keeps the group in place.

After joining a sample lobby, its host controls setup and start. The visitor can
ready themselves or rehearse the host's start, clearly marked as simulation.
**Leave Together** returns just the squad to its original Hideout, restoring its
map/access. Returning from a match rehearsal keeps the current host and roster.

The former departure area is **Match Status**. It displays the chosen map and
opens for the explicit three-second start countdown. Walking into it never
starts or joins a match. Start ends at an F6 preview screen; Return brings the
player back without changing scenes. Invitations, visibility, directory entries,
readiness and group travel are memory-only; no network calls or GameConfig writes.
See `SESSION_INTEGRATION.md` for the integration boundary.

## The Scrap Yard

A new room opens through the **back centre of the Play Pen**, where the middle
supply bay used to be. The two outer floor grids remain. The room is now
54 × 50 metres with an 11.2 metre ceiling height, surrounding a
30 metre circular ring (previously 36 × 34 metres / an 18 metre ring). Cover,
starts, hurdles and equipment positions spread across the larger fighting floor.
Three tiers of longer seats and wider aisles surround the perimeter rails.
The entry sign sits beside the foyer so the view into the ring stays open.

Interact in the foyer, or choose **Esc → The Scrap Yard**:

- **Join as Player 2**: the F6 pilot calls heads or tails against a practice bot.
- **Local two players**: P1 and P2 use the existing movement/controller actions
  in two views of the same arena. P2 needs a controller (one pad with keyboard P1,
  or a second pad with controller P1). Device routing is temporary and restores
  on leaving. Character skins and cosmetics use the existing player scene.
- **Watch demo duel**: two practice bots fight while the pilot walks the stands.
  Existing mock visitors gather in the stands and return to their prior spots
  after the round. These are local audience visuals, not connected friends.

The second entrant calls once. A single committed coin outcome drives the
animated coin and identical reveal in both split views. A correct call gives P2
the gun; an incorrect call gives P1 the gun. The other fighter starts with one
random melee weapon. Combat unlocks after the reveal and three-second countdown.
There is **one gun and two melee weapons total**, including one spare floor
melee, plus one random enabled item and one enabled powerup. **Extra Life and
Sticky Hands are excluded**. If all eligible items or powers are disabled, that
spawn stays empty rather than rewriting saved match rules.

Actual gun/melee/item behavior is reused, including ordinary melee disarming and
gun reload. One elimination ends the round; there is no within-round respawn.
Return to Foyer resets the pilot and removes all duel gear/effects. The foyer and
stands are noncombat; the ring boundary blocks weapons/projectiles from the
spectators. Practice inventory cannot enter the duel, and duel equipment cannot
leave it. Escape/menu freezes fighter controls in this local rehearsal.

`scrap_yard.gd` owns the state machine and epoch; `scrap_actor.gd` adapts P2 and
practice bots without modifying the production controller. Demo fighters pursue
the sole loose gun after a disarm, aim from its actual muzzle and can target an
opponent jumping overhead. `scrap_space.gd`
authors the room. No match rewards, ranked record, live queue or networking is
created. Two render views are only allocated for the local duel and freed on exit;
Low applies independently to both. Human playtests are still needed for duel
balance, input comfort and cover choices.

## Central social activity

**Trickshot Toss** adds soft balls and two baskets to the central pit. Aim using
the regular camera and use Interact near the ball basket. A basket scores one
point; a bounced shot scores two. One lightweight ball is simulated at a time,
resets after six seconds or leaving the pit boundary, and stops processing while
idle. It has no combat behavior or match inventory. Scores last only for this F6
session. A real shared multiplayer toy can use a separate authoritative adapter
later; the current score belongs to the local rehearsal.

## Editing and verification

`station.tscn` contains editable geometry, signs, collisions, occluders, interaction
areas and lights. Authoring sources are `station.gd`, `arcade.gd`, `dispatch.gd`,
`playpen_space.gd`, `training_space.gd`, `agility_space.gd`, `arrival_space.gd`,
`service_floor.gd`, `scrap_space.gd` and `bounded_concourse.gd`. Rebuilding overwrites manual edits
to the saved station, so choose one authoring path per revision.

`playpen.gd` owns supply/refill, boundary, effect cleanup and respawn lifecycles.
`preview_actor.gd` gates the original controller's combat APIs by position.
`training.gd` owns independent target distances, hit counts and time-trial state.
`course_records.gd` owns local records, and `course_board_ui.gd` renders the three
viewer-specific record pages;
`range_target.gd` provides a light wooden target without another character rig.
Scene-added events track projectiles/effects; there are no per-frame scene scans.
Static visuals batch by room/material/spatial section at runtime, retaining colliders.
Main-hall and Play Pen batches are separate, with wall occluders around the portal.
No local lights cast shadows. Forward+ remains the renderer.

```powershell
python tools/live_lobby_preview/run_checks.py bake
python tools/live_lobby_preview/run_checks.py validate
python tools/live_lobby_preview/run_checks.py playtest
python tools/live_lobby_preview/run_checks.py capture
python tools/live_lobby_preview/run_checks.py capture --saved
python tools/live_lobby_preview/run_checks.py capture --hideout-revision
python tools/live_lobby_preview/run_checks.py capture --hideout-revision --saved
```

The runner uses the project's Godot executable. Captures use the actual player
camera in an off-screen window. Logs, images and profiles go to `artifacts/`,
ignored by Godot and Git. Validation covers navigation, all current rigs, shared
menus, party/rehearsal lifecycle, real combat, exit cleanup and respawns. See
`VALIDATION.md` for measured results and remaining human playtests.

F6 honors saved graphics by default. Optional Low uses 75% 3D scale and disables
AA, glow and SSAO without saving settings. Test the scene at 1080p Low on the weaker
laptop before live integration; development-GPU samples do not qualify that target.
The older separate-project study is retained under `tools/live_lobby_lab/`.
