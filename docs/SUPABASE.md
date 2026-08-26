# Supabase integration

One Gun uses Supabase only for persistent identity and cosmetic progression.
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
`RewardIdentityManager` loads immediately after `NetworkManager`. Responsibilities:

- `SupabaseManager`: Auth/session refresh, Account Name, Gun Tokens, owned inventory,
  base public catalog, and the 12-slot loadout (character, clothing/accessory,
  weapon skins, two independent celebration slots, ceremony theme, and profile badge).
- `ProgressionManager`: taxonomy/rotations, outfit components, favorites, usage,
  season/career/profile snapshots, roads/history/Legacy Hall, purchases/equips,
  and match-reward confirmation/polling.
- `RewardIdentityManager`: one random private confirmation secret per signed-in app
  session. Only its SHA-256 claim hash crosses ENet before a match.

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

The home screen has separate **Profile**, **Prize Counter**, and **Locker** routes.
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

`res://supabase/supabase_cosmetic_registry.gd` is the boundary between stable
database item IDs and local assets. Server values are sanitized identifiers;
they are never interpreted as resource paths. Existing character color IDs map
through `PlayerSkinRegistry`. The `emote` and `round_victory_move` loadout columns remain independent presentation
slots, but every animated catalog row now has the shared `victory_dance` type. All
fourteen production IDs plus Hip Hop and Swing resolve through one fixed local library,
can be assigned to either column, and are lazy-loaded only when selected or previewed. Unknown moves safely fall back without exposing a bind pose. Hat,
accessory, gun-skin, melee-skin, shirt/pants/shoes/profile-badge, outfit-component,
and general in-match emote attachment/render systems do not exist yet, so their IDs
remain safe data-only loadout entries. The Winners Circle keeps the default gun
model when an equipped gun skin has no renderer. The store UI labels other missing
mappings **ART PENDING**, and actors log one warning per missing mapping instead of
crashing. Add future visuals in this registry and their purpose-built local renderer.

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
```

`tools/supabase_cosmetic_network_validation.gd` is a two-process loopback test
for cosmetic roster synchronization and private-state non-disclosure. The
existing `tools/lobby_network_validation.gd` remains the broader lobby
regression.
`supabase/tests/local_supabase_bootstrap.sql` plus
`supabase/tests/progression_rewards_test.sql` and
`supabase/tests/victory_moves_catalog_test.sql` run the migrations against a disposable
plain-PostgreSQL copy of the linked public schema. They assert majority settlement,
exact reward totals, daily-grant uniqueness, separate Season/Career XP, idempotency, milestone unlocks, outfit proration/grants/equip,
favorites, progression/profile reads, all fourteen unified dance IDs, dual-slot assignment, baseline ownership, UNEQUIP,
outfit removal, model/color-preserving reset, permanent purchases, and token deductions. On 2026-08-24 the chronological
suite covers migrations through `20260830`, including progression, forfeit settlement,
placement Tokens, daily victory rewards, payload canonicalization, the new XP curves, and unified-dance/loadout tests; the linked CLI and a publishable-key REST read
verify the live catalog after each push.


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
