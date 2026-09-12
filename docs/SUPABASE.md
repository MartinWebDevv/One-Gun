# Supabase integration

One Gun uses Supabase for persistent identity, cosmetic progression, authenticated friends/presence, and agility personal-best backups.
Godot/ENet remains responsible for lobbies, Tailscale discovery, gameplay,
authority, and match replication. itch.io and GitHub remain distribution paths.

## Client configuration and security

The shipped client configuration is `res://supabase/supabase_config.json`:

```json
{
	"enabled": true,
	"project_url": "https://PROJECT.supabase.co",
	"publishable_key": "sb_publishable_..."
}
```

`ONEGUN_SUPABASE_URL` and `ONEGUN_SUPABASE_PUBLISHABLE_KEY` override those
values for a launch or build environment. A publishable/anon key is expected in
the client and relies on database grants plus Row Level Security. Never put an
`sb_secret_`, service-role, admin, database, or Supabase management credential
in this file, an export, a command-line script, or source control. The manager
rejects obvious secret/service-role credentials at startup.

The current client-safe project URL and publishable key supplied for One Gun are
already installed in the JSON file. Passwords are sent only to Supabase Auth and
are not saved by One Gun. Successful Auth sessions are restored from
`user://supabase_session.json`, which contains the returned access token,
refresh token, user ID, expiry, and a pending sanitized Account Name claim when
email confirmation delays the first session. Sign out removes that file. Treat the local
OS account and its `user://` directory as the session security boundary.

## Runtime architecture

`SupabaseManager` is loaded after `PlayerPrefs`; `ProgressionManager` follows it.
`SocialManager` and `RewardIdentityManager` load after the transport/session autoloads. Responsibilities:

- `SupabaseManager`: Auth/session refresh, Account Name, Gun Tokens, owned inventory,
  base public catalog, and the 13-slot loadout (character color/model, clothing/accessory,
  weapon skins, two independent celebration slots, ceremony theme, and profile badge).
- `ProgressionManager`: taxonomy/rotations, outfit components, favorites, usage,
  season/career/profile snapshots, roads/history/Legacy Hall, purchases/equips,
  and match-reward confirmation/polling.
- `SocialManager`: friend requests/responses/removal, accepted-friend snapshots,
  low-frequency presence heartbeats, short-lived named-lobby invitations, and invite responses.
- `RewardIdentityManager`: one random private confirmation secret per signed-in app
  session. Only its SHA-256 claim hash crosses ENet before a match.
- `CourseCloud`: one shared local personal-best cache, account-bound minimum-only
  cloud sync on sign-in/improvement, restoration, and retry after connection failure.

UI observes manager signals and never makes raw Supabase calls. Private reads require
a valid player JWT. Catalog strings are data and are never loaded as Godot paths.
`one_gun_catalog.gd` is the shared taxonomy, rarity, rotation, and sort contract.

All persistent writes are authenticated security-definer RPCs. Purchases call
`purchase_shop_item`; equips use ownership-checking slot/theme/outfit RPCs;
favorites use `set_shop_favorite`; results use `confirm_official_beta_match`.
The client never directly writes currency, inventory, loadout, progression,
receipt, road, archive, popularity, or ledger tables and has no grant/debug path.
Outfits cost `ceil(85% × unowned component sum)`, atomically grant the bundle and
every component, and record original price, discount, paid price, and balance.

## UI and local cosmetic mapping

The home screen's **Player Hub** groups Profile, Prize Counter, Locker, Progression,
and Friends behind one route while Play, Settings, and Quit remain on the title rail.
Profile owns email/password account creation, sign-in, sign-out, account rename,
and the freely editable in-game Display Name. Create Account requires a unique
3–20-character Account Name. Account Name is cloud identity and can be renamed
only once every 14 days; Display Name remains local gameplay identity and can be
changed independently. Overview, mode-by-mode Stats, Legacy Hall, and Match History
consume the live `get_player_progression` snapshot.

Prize Counter shows Gun Tokens and filters the active public rotation into
Featured, Character, Weapons, Victory, and Audio. Subcategories cover skins/colors,
hats/shirts/pants/shoes/outfits, gun/melee skins, poses, shared dances,
and Winners Circle themes. Daily, Monthly, and Seasonal Starter are explicit
rotation scopes; unassigned/placeholder rows never silently become live. Beta's
Starter Pool is the six purchasable Winners Circle themes, paged three at a time.
The Locker uses the same taxonomy but lists owned items only; base colors remain free.
Hidden gifts and road prizes remain browsable there forever.
Gift-only character models appear as owned Locker rows with Preview/Equip controls,
but never enter the public model selector or Prize Counter rotation. The Locker resolves
trusted packaged gift metadata from the owned inventory ID even if the RLS-gated hidden
catalog request finishes later, so catalog timing cannot make an owned character disappear.
Selecting a locally mapped dance in the Prize Counter replaces the generic inspector
monogram with a compact full-body preview using the player's current character model
and color. The Locker retains its larger owned-item preview. Every owned animated dance
has separate EQUIP PODIUM and EQUIP ROUND controls, and the same dance may occupy both.
Previewing a Winners Circle theme pauses menu music until preview playback ends
or the player leaves the preview area, preventing the two tracks from overlapping.
Each route has an independent full-screen presentation: Profile is an official
competitor record hall, Prize Counter is an arena prize booth with a focused
item inspector, Locker is a cool-toned armory with the existing live character
preview, and Progression is the live season-road cabinet. Blender backgrounds are static runtime textures;
interactions, ownership, filtering, and Supabase state remain native Godot UI.

The home screen and online lobby expose Friends through the separate upper-right mascot
orb, while Player Hub groups Profile/Locker/Prize Counter/Progression at home and
Locker/Prize Counter/Progression in the lobby. The Friends
panel accepts an exact Account Name for outgoing requests, presents incoming Accept/Deny
actions and outgoing status, lists accepted friends with online/activity state, and
offers Invite while the local player is in a joinable named Tailscale lobby. Accepting
an invitation from either the panel or controller-ready toast passes its sanitized address/port to the existing `NetworkManager.join_game()`
path; social code never implements a second gameplay transport.

`res://supabase/supabase_cosmetic_registry.gd` is the boundary between stable
database item IDs and local assets. Server values are sanitized identifiers;
they are never interpreted as resource paths. Existing character color IDs map
through `PlayerSkinRegistry`. The `emote` and `round_victory_move` loadout columns remain independent presentation
slots, but every animated catalog row now has the shared `victory_dance` type. All
fourteen production IDs plus Hip Hop and Swing resolve through one fixed local library,
can be assigned to either column, and are lazy-loaded only when selected or previewed. Unknown moves safely fall back without exposing a bind pose. The hidden
Gold Fish Bag Man, Eye Wizard, Mr. Mushroom, Mr. Poop, Mr. Salt, and Spooky Witch
entitlements map only to their packaged local scenes. They keep their authored textures,
use the shared animation/socket contract across gameplay, home, Locker, and Winners Circle,
and never appear in the public model selector or Prize Counter. The wearable registry and character
skeleton binder now provide one trusted local renderer for Hat, shirt, pants, shoes,
and accessory slots. Rigid art such as Hats or glasses follows a semantic animated
bone socket; deforming shirts/pants require a per-model skinned scene with named binds
compatible with the live character skeleton. Hats are the only wearable art mapped
today, so the other slot IDs remain safe data-only entries until compatible local assets
are registered. Gun-skin, melee-skin, profile-badge, outfit-component, and general
in-match emote renderers remain art/system pending. The Winners Circle keeps the default gun
model when an equipped gun skin has no renderer. The store UI labels other missing
mappings **ART PENDING**, and actors log one warning per missing mapping instead of
crashing. Add future wearable visuals only in `wearable_cosmetic_registry.gd`; backend
strings never become resource paths.

The `ceremony_theme` slot maps only the seven approved stable IDs to packaged
audio keys. Ceremony March is the permanent starter/default. Neon Victory,
Western Toybox, Grand Arena, Pixel Champion, Champion Groove, and Deep Orbit
are purchasable unlockables. The winning player's sanitized equipped ID travels
through the existing ENet cosmetic dictionary and frozen result snapshot, so
every peer hears the champion's choice. Unknown IDs always fall back to Ceremony March.

The Winners Circle first shows the deterministic local formula as **verifying**.
Each remaining finisher privately submits the same frozen result plus only their own
claim secret. Supabase hashes it, matches the pre-match claim hash, validates the
three-plus starting roster and DNF/forfeit flags, requires a majority of the finishers,
then settles confirmed finishers in one transaction. One sole finisher settles immediately.
Match IDs,
per-player reward rows, and wallet ledgers make settlement idempotent. PostgreSQL—not
the display calculator—determines persisted XP, Gun Tokens, Trophies, levels, road
unlocks, career/mode stats, Match History, and the once-per-UTC-day victory grant.

## Multiplayer

Only the sanitized 12-slot cosmetic ID dictionary enters `NetworkManager`'s
existing ENet roster. The host relays it with the normal authoritative roster,
and `RoundManager` includes it in human spawn data. Peers resolve supported art
locally. Reward claim hashes are the only extra reward identity data exchanged;
private secrets go only to Supabase over HTTPS. Access/refresh tokens, Supabase user
IDs, currency, inventory, and claim secrets never enter roster/spawn/result payloads.
Supabase is not used for movement, combat, lobby, or gameplay synchronization.
Friend presence is an authenticated, expiring cloud snapshot rather than a gameplay
heartbeat. The three social tables have all direct table privileges revoked. Each
security-definer RPC binds its operation to `auth.uid()`: only request recipients can answer,
only accepted friends can see one another's live presence or send lobby invites, and only
the invite recipient can accept/deny an invite. Lobby endpoints are therefore hidden from
anonymous users and non-friends even though accepted friends can see a joinable friend's
current named-lobby endpoint.

## Backend migrations and CLI workflow

The repository is initialized and linked for Supabase CLI. Migrations are ordered:

```text
supabase/migrations/20260823_winners_circle_themes.sql
supabase/migrations/20260824_profile_account_names.sql
supabase/migrations/20260825_catalog_progression_rewards.sql
supabase/migrations/20260826_victory_moves_catalog.sql
supabase/migrations/20260827_unified_victory_dances_and_loadout_controls.sql
supabase/migrations/20260828_economy_forfeit_progression.sql
supabase/migrations/20260829_season_career_daily_victory.sql
supabase/migrations/20260830_reward_payload_canonicalization.sql
supabase/migrations/20260831_friends_presence_invites.sql
supabase/migrations/20260901_hat_catalog_and_road_rebalance.sql
```

The progression migration adds taxonomy/rotations/popularity, favorites/usage,
outfit bundles and purchase ledger, the expanded loadout, seasons/progression/mode
stats, archives/roads/unlocks, official confirmations/rewards/wallet ledger, locked
Beta formulas, and authenticated RPCs. It seeds Beta Season and data-only road prizes.
It removes fake products from public rotations while preserving already-owned rows
through RLS. The six purchasable ceremony themes become the three-month Starter Pool.

The economy/forfeit migration replaces match Token performance bonuses with fixed
250/200/150/100 placement awards, introduced the earlier stacked XP curve,
settles against the remaining-finisher quorum after an Official start, grants a sole
finisher a forfeit win, and records Season plus Career rank snapshots in Legacy Hall.

The Season/Career/daily-victory migration replaces that earlier XP curve with 20–100
base match XP, gradual `150 + 2 * (level - 1)` Season requirements, and flat 400-XP
Career levels. A unique `(player_id, UTC date)` database receipt grants the first Official
Classic victory 25 extra Season XP plus 100 Gun Tokens atomically; clients have read-only
access to their own grant history and cannot choose the date or award themselves.
The reward-payload canonicalization migration removes Winners Circle's
per-client `local_peer_id` presentation field before the Official result is
hashed. The client removes it as well. This guarantees every finisher confirms
the same shared evidence while preserving local row highlighting and Ready UI.

The friends/presence migration adds one normalized unordered friendship row per account
pair, expiring self-owned presence, and short-lived lobby invitations. It revokes direct
table access and exposes only authenticated requester-bound RPCs for send/respond/remove,
presence set/clear, social snapshot, and invite send/respond. The migration is fully
covered by the disposable PostgreSQL social-graph suite. On 2026-08-26 the explicitly
authorized linked `db push` applied `20260831` successfully; the follow-up migration
ledger reports matching local and remote `20260831` entries, so the social backend is live.

Migration `20260901` adds ten purchasable Prize Counter hats, renames the two stable road IDs to Rice Hat and Pimp Hat, moves Rice Hat from Level 30 to Level 10, and moves Pimp Hat from Trophy 20 to Trophy 5. Existing ownership is never revoked, and accounts already beyond the new thresholds are backfilled idempotently into inventory and the unlock ledger. On 2026-08-27 it passed PostgreSQL parsing plus a disposable clone of the linked public schema with synthetic pre-migration player state; first-run and repeat-run tests both report `HAT_CATALOG_REWARD_TESTS_OK`. The explicitly authorized linked `db push` then applied `20260901` successfully. The local/remote migration ledger matches, and a publishable-key REST verification confirms all ten public purchasable hats, Level 10 Rice Hat, Trophy 5 Pimp Hat, and removal of the old Level 30/Trophy 20 rows.

Migration `20260902` applies the rarity-stepped Hat price pass without touching the two non-purchasable road rewards: Common hats are 850 Gun Tokens, Uncommon 1,250, Rare 1,650, and Epic 2,200. On 2026-08-27 a schema-only disposable clone of the linked public database passed the `20260901` + `20260902` migrations and all Hat catalog/reward/price assertions twice, including the idempotent rerun. A linked dry run identified only `20260902`, the linked push succeeded, local and remote migration ledgers match through it, and a publishable-key REST verification returned exactly ten purchasable Hat rows at the requested prices.

Migration `20260903` adds the nullable `character_model` loadout slot and the active but
non-purchasable/non-visible `character_goldfish_bag_man` catalog record. Ownership can
only be granted by a trusted manual inventory insert; the authenticated equip/unequip RPCs
still enforce ownership. The client falls back to the player's last public Male/Female
choice when the gift is unequipped. On 2026-08-28 the explicitly authorized linked push
applied `20260903`; the local/remote migration ledger matches through it and a follow-up
linked dry run reports the remote database fully up to date.

Migration `20260904` adds active catalog records for `character_eye_wizard`,
`character_mr_mushroom`, `character_mr_poop`, `character_mr_salt`, and
`character_spooky_witch`. Every record is price zero, non-purchasable, non-visible,
non-featured, and outside every rotation. The client exposes each model in Locker Skins
only when its trusted inventory entitlement is owned. On 2026-08-29 the explicitly
authorized linked push applied `20260904`; the local/remote migration ledger matches
through it and the follow-up linked dry run reports the remote database fully up to date.


The original victory-move migration added fourteen priced products with stable IDs.
The follow-up unified-dance migration preserves every purchase while moving all animated
rows into Victory > Dances. It grants Original One Gun, Original Melee Finish, Hip Hop,
Swing Dance, and Ceremony March as hidden permanent baseline ownership; adds authenticated
UNEQUIP, outfit removal, and atomic Reset Loadout RPCs; and allows any owned dance in
either independent celebration column. Reset clears cosmetic pieces, restores the
baseline weapons/Hip Hop/Ceremony March, leaves the podium at idle, and preserves the
character model/color choice.

Normal database updates do not require the web SQL Editor:

```powershell
npx -y supabase migration list --linked
npx -y supabase db push --linked
```

`supabase/config.toml` contains only link/config metadata. CLI login credentials live
in the developer's Supabase CLI profile outside the repository. The shipped JSON has
only the publishable key. `supabase/.gitignore` excludes CLI temp/cache files, and root
ignore rules reject service-role/secret-key environment files. Never run admin or
service-role operations from the game client.

## Validation

Focused local validations (they do not create accounts or mutate the backend):

```powershell
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script res://tools/supabase_ui_validation.gd
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script res://tools/progression_catalog_validation.gd
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script res://tools/victory_move_integration_validation.gd
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script res://tools/social_system_validation.gd
```

`tools/supabase_cosmetic_network_validation.gd` is a two-process loopback test
for cosmetic roster synchronization and private-state non-disclosure. The
existing `tools/lobby_network_validation.gd` remains the broader lobby
regression.
`supabase/tests/local_supabase_bootstrap.sql` plus
`supabase/tests/progression_rewards_test.sql`,
`supabase/tests/victory_moves_catalog_test.sql`, and
`supabase/tests/social_graph_test.sql` run the migrations against a disposable
plain-PostgreSQL copy of the linked public schema. They assert majority settlement,
exact reward totals, daily-grant uniqueness, separate Season/Career XP, idempotency, milestone unlocks, outfit proration/grants/equip,
favorites, progression/profile reads, all fourteen unified dance IDs, dual-slot assignment, baseline ownership, UNEQUIP,
outfit removal, model/color-preserving reset, permanent purchases, token deductions,
friend-request transitions, relationship privacy, presence expiry, accepted-friend endpoint visibility, and invite authorization. On 2026-08-26 the chronological
suite covers local and linked migrations through `20260901`, including progression, forfeit settlement,
placement Tokens, daily victory rewards, payload canonicalization, the new XP curves, unified-dance/loadout tests, and the social graph; the linked CLI and a publishable-key REST read
verify the live catalog after each push.

`supabase/tests/hat_catalog_rewards_seed.sql` and `supabase/tests/hat_catalog_rewards_test.sql` specifically cover the Hat catalog and road rebalance. The seed creates disposable pre-migration road/catalog/player state; the test asserts the Level 10 Rice Hat and Trophy 5 Pimp Hat, retired old milestones, exactly ten live Prize Counter hats, the rarity-stepped prices, preservation of replaced milestone ownership, eligible-player backfills, unlock-ledger updates, and migration idempotency.


A real test account is still required for end-to-end Auth/RLS/RPC verification:
create an account with an available Account Name, confirm that its separate
Display Name is unchanged, verify the rename cooldown, confirm
profile/currency/inventory/loadout, verify Ceremony March is in Locker, purchase
a theme, equip it, restart, and verify restoration. Win an
Official three-human Tailscale match and confirm each signed-in participant settles
once, the winner receives one Trophy, result panels show the banked receipt, roads/
Profile update, and every peer hears the champion's selection. Also test insufficient
funds, already-owned outfit pieces, duplicate/nonexistent items, an early quitter,
offline behavior, local splitscreen (results-only), repeated transitions, and the
exported itch-compatible Windows build. These tests change real backend/player state
and are intentionally not automated with unknown credentials.


## Agility personal-best recovery and cloud backup — 2026-09-10

`20260910_agility_personal_bests.sql` is applied to the linked project. Live checks
confirmed the migration ledger, table RLS, denied direct client access, and
signed-in-only RPC execution. Recovered records were uploaded with the existing
player session and read back through the same RPC; an empty sync preserved them.

`CourseCloud` loads `user://hideout/course_records.json` before sign-in. It merges
the old online file, valid `.bak` and `.tmp` files, and known v2 buckets into the
current v3 record identity, always taking the faster time for the same account,
movement setup and category. Original version buckets and legacy files remain.
Writes retain a previous-file backup and use a flushed temporary file plus rename;
unreadable primary files are copied aside before replacement. Geometry edits must
not silently reset record identity again. A deliberate record reset/new competitive
season requires an explicit design decision and a visible historical record path.

`sync_agility_personal_bests(p_bests)` derives identity from `auth.uid()` and returns
only that account's records. No player ID is accepted from the client. The RPC
validates bucket/time limits, serializes an account's concurrent imports, and
updates only improvements. `agility_personal_best_history` records the initial best
and each improvement; empty or slower imports never erase a best or append history.
Both tables deny direct client reads/writes/deletes. The security-definer RPC pins
an empty search path and is executable only by authenticated accounts.

Cloud replies merge into the local cache and immediately update/share the lobby
board, including replies arriving after the first scene snapshot. Account changes
invalidate pending replies and bind uploads to the original account across token
refresh. Signed-out local-profile records are not silently assigned to an account.
Offline improvements remain local and retry after 45 seconds; requests are
asynchronous and coalesced, with no per-frame network or disk activity. The board
shows backup status. Dedicated/headless automation never syncs these records;
`--hideout-test` also prevents restoring/rotating the real saved Auth session.

Players must run this client revision on the PC containing their old saves and
sign into the same account to upload recovered records. After upload, another PC
can restore their bests at sign-in. Standard, selected Power-Up, legacy arbitrary
assisted runs, and different movement setups remain separate. This is backup of
personal receipts (including solo/legacy runs), not a verified World leaderboard.

Validation from the project root:

```powershell
& '.\Godot_v4.7.1-stable_win64.exe' --headless --path . --script res://tools/course_cloud_validation.gd -- --hideout-test
npm install --prefix artifacts/course_cloud_validation/db --no-audit --no-fund @electric-sql/pglite
node tools/run_course_database_test.mjs
python tools/run_hideout_network.py
```

The SQL runner uses disposable in-memory PostgreSQL with synthetic accounts,
checking auth isolation, grants, validation rollback, minimum-only updates, history,
and migration reapplication. It never runs fixture writes against the live project.
The Godot test covers legacy/backup recovery, empty-device restore, offline retry,
a faster run during a request, and account-switch isolation. Network fixtures use
unique files per run so backup recovery cannot import an earlier test's scores.
`tools/recover_course_records.gd -- --recover-course-records --hideout-test` is an
explicit local recovery utility; normal graphical startup performs the same merge.
