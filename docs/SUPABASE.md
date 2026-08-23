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
- the seven-slot `loadout`, including `ceremony_theme`

UI observes manager signals and never makes raw Supabase calls. Profile,
currency, inventory, and loadout reads require a valid session. The public shop
query requests only rows where `active=true` and `shop_visible=true`.

Purchases call `purchase_shop_item(p_item_id)` and then refetch currency,
inventory, and shop data. Existing cosmetic equips call
`equip_cosmetic(p_slot, p_item_id)`; ceremony themes call the isolated
`equip_ceremony_theme(p_item_id)` RPC. Both refetch the loadout after success.
The client never writes `player_currency`,
`player_inventory`, or `player_loadouts` directly and contains no grant/debug
method for those tables.

## UI and local cosmetic mapping

The main menu's **Account & Prize Counter** cabinet supplies email/password
account creation and sign-in, sign-out, Gun Tokens, the public Prize Counter,
and an owned-only Locker. Hidden grants such as `founder_crown` and the default
Ceremony March can appear in the Locker without appearing in the Prize Counter.

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

The `ceremony_theme` slot maps only the seven approved stable IDs to packaged
audio keys. Ceremony March is the permanent starter/default. Neon Victory,
Western Toybox, Grand Arena, Pixel Champion, Champion Groove, and Deep Orbit
are purchasable unlockables. The winning player's sanitized equipped ID travels
through the existing ENet cosmetic dictionary and frozen result snapshot, so
every peer hears the champion's choice. Unknown IDs always fall back to Ceremony March.

The Winners Circle's `match_reward_preview.gd` is intentionally not a Supabase
economy client. It previews +1 Trophy only for the classified Official Classic
winner, leaves XP/Gun Token amounts unset, marks every preview unpersisted, and
never changes profile/currency/inventory tables. No reward SQL is required for this
presentation stage. A future authenticated server-authoritative reward receipt
and season tables will replace that boundary before rewards become real.

## Multiplayer

Only the sanitized seven-slot cosmetic ID dictionary enters `NetworkManager`'s
existing ENet roster. The host relays it with the normal authoritative roster,
and `RoundManager` includes it in human spawn data. Peers resolve supported art
locally. Access/refresh tokens, user IDs, currency, and inventory are never put
in roster or spawn payloads. Supabase is not used for movement, combat, lobby,
or match synchronization.

## Backend migration required

The public catalog was verified readable with the publishable key on 2026-08-23.
To activate Winners Circle ownership/equipping, run this committed migration
once in the Supabase SQL Editor as the project/database owner:

```text
supabase/migrations/20260823_winners_circle_themes.sql
```

It adds `player_loadouts.ceremony_theme`, securely grants/backfills the free
default, inserts the six visible theme products at Beta starting prices, and
creates the ownership-checking `equip_ceremony_theme` RPC. It preserves the
existing six-slot `equip_cosmetic` function unchanged. No credential or SQL
write path is added to the shipped client.

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
sign in, confirm profile/currency/inventory/loadout, verify Ceremony March is in
the Locker, purchase a theme, equip it, restart, and verify restoration. Win an
online match and confirm every peer hears the champion's selection. Also test
insufficient funds,
duplicate/nonexistent items, offline behavior, a two-machine Tailscale match,
local splitscreen, and the exported itch-compatible Windows build. These tests
change real backend/player state and are intentionally not automated with
unknown credentials.
