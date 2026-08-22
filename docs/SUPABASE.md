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
refresh token, user ID, and expiry. Sign out removes that file. Treat the local
OS account and its `user://` directory as the session security boundary.

## Runtime architecture

`SupabaseManager` is loaded after `PlayerPrefs` and before `NetworkManager`. It
owns all Auth and REST traffic, token refresh, error handling, and runtime state:

- `profile` (`id`, `username`)
- `gun_tokens`
- deduplicated `inventory` and `owns_item()`
- active, visible `shop_items`
- the six-slot `loadout`

UI observes manager signals and never makes raw Supabase calls. Profile,
currency, inventory, and loadout reads require a valid session. The public shop
query requests only rows where `active=true` and `shop_visible=true`.

Purchases call `purchase_shop_item(p_item_id)` and then refetch currency,
inventory, and shop data. Equips call `equip_cosmetic(p_slot, p_item_id)` and
then refetch the loadout. The client never writes `player_currency`,
`player_inventory`, or `player_loadouts` directly and contains no grant/debug
method for those tables.

## UI and local cosmetic mapping

The main menu's **Account & Store** cabinet supplies email/password account
creation and sign-in, sign-out, Gun Tokens, the public store, and owned inventory.
Hidden grants such as `founder_crown` can appear in owned inventory without
appearing in the store.

`res://supabase/supabase_cosmetic_registry.gd` is the boundary between stable
database item IDs and local assets. Server values are sanitized identifiers;
they are never interpreted as resource paths. Existing character color IDs map
through `PlayerSkinRegistry`. The `emote` loadout slot is the current Victory
Move slot: `hip_hop_dance`/`victory_hip_hop` and
`swing_dance`/`victory_swing` resolve to the two existing local podium clips.
Unknown moves safely fall back to an idle. Hat, accessory, gun-skin, melee-skin,
and general in-match emote attachment/render systems do not exist yet, so their
IDs remain safe data-only loadout entries. The Winners Circle keeps the default
gun model when an equipped gun skin has no renderer. The store UI labels other
missing mappings **ART PENDING**, and actors log one warning per missing mapping
instead of crashing. Add future visuals in this registry and their purpose-built
local renderer.

The Winners Circle's `match_reward_preview.gd` is intentionally not a Supabase
economy client. It previews +1 Trophy only for the classified Official Classic
winner, leaves XP/Gun Token amounts unset, marks every preview unpersisted, and
never changes profile/currency/inventory tables. No new SQL is required for this
presentation stage. A future authenticated server-authoritative reward receipt
and season tables will replace that boundary before rewards become real.

## Multiplayer

Only the sanitized six-slot cosmetic ID dictionary enters `NetworkManager`'s
existing ENet roster. The host relays it with the normal authoritative roster,
and `RoundManager` includes it in human spawn data. Peers resolve supported art
locally. Access/refresh tokens, user IDs, currency, and inventory are never put
in roster or spawn payloads. Supabase is not used for movement, combat, lobby,
or match synchronization.

## Backend permission required

A read-only check on 2026-08-20 returned PostgreSQL error `42501` for the anon
catalog query: the `anon` role currently lacks table `SELECT` privilege. Apply
the following in the Supabase SQL editor, then ensure the existing RLS SELECT
policy exposes only the intended public rows:

```sql
grant select on table public.shop_items to anon, authenticated;
```

Without that grant, signed-out catalog loading fails gracefully and signed-in
catalog access may also fail depending on the authenticated role grants. No
client change can or should bypass this database permission.

## Validation

Focused local validations (they do not create accounts or mutate the backend):

```powershell
& "D:\Godot Projects\one-gun\Godot_v4.7.1-stable_win64.exe" --headless --path "D:\Godot Projects\one-gun" --script res://tools/supabase_ui_validation.gd
```

`tools/supabase_cosmetic_network_validation.gd` is a two-process loopback test
for cosmetic roster synchronization and private-state non-disclosure. The
existing `tools/lobby_network_validation.gd` remains the broader lobby
regression.

A real test account is still required for end-to-end Auth/RLS/RPC verification:
sign in, confirm profile/currency/inventory/loadout, purchase an affordable item,
equip it, restart, and verify restoration. Also test insufficient funds,
duplicate/nonexistent items, offline behavior, a two-machine Tailscale match,
local splitscreen, and the exported itch-compatible Windows build. These tests
change real backend/player state and are intentionally not automated with
unknown credentials.
