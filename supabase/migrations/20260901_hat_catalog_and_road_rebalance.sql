-- One Gun: ship the first locally-rendered hat catalog and move the two
-- requested Beta Road hats to Level 10 and Trophy 5.
--
-- Stable reward item IDs are intentionally retained so existing ownership and
-- equipped loadouts survive the art/name change. This migration is safe to run
-- once or repeatedly and does not revoke any previously-owned cosmetic.

begin;

update public.shop_items
set display_name = 'Rice Hat',
    item_type = 'hat',
    description = 'A woven arena hat earned at Level 10 on the Beta Season Level Road.',
    price = 0,
    rarity = 'uncommon',
    purchasable = false,
    shop_visible = false,
    active = true,
    category = 'character',
    subcategory = 'hats',
    featured = false,
    rotation_scope = 'reward',
    rotation_starts_at = null,
    rotation_ends_at = null
where id = 'beta_s1_level_30_hat';

update public.shop_items
set display_name = 'Pimp Hat',
    item_type = 'hat',
    description = 'An unmistakable champion hat earned at five Beta Season trophies.',
    price = 0,
    rarity = 'epic',
    purchasable = false,
    shop_visible = false,
    active = true,
    category = 'character',
    subcategory = 'hats',
    featured = false,
    rotation_scope = 'reward',
    rotation_starts_at = null,
    rotation_ends_at = null
where id = 'beta_s1_ace_hat';

insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope, rotation_starts_at, rotation_ends_at, sort_order
) values
    ('hat_chef', 'Chef Hat', 'hat',
     'A tall kitchen classic built for serving arena victories.',
     450, 'common', true, true, true, 'character', 'hats',
     false, 'daily', null, null, 210),
    ('hat_yellow_point', 'Yellow Point Hat', 'hat',
     'A bright pointed cap that is impossible to miss in a crowd.',
     450, 'common', true, true, true, 'character', 'hats',
     false, 'daily', null, null, 211),
    ('hat_cowboy_classic', 'Classic Cowboy Hat', 'hat',
     'A clean frontier silhouette for fast draws and faster escapes.',
     650, 'uncommon', true, true, true, 'character', 'hats',
     false, 'daily', null, null, 212),
    ('hat_fedora_black', 'Black Fedora', 'hat',
     'A sharp black fedora for competitors who keep their cool.',
     650, 'uncommon', true, true, true, 'character', 'hats',
     false, 'daily', null, null, 213),
    ('hat_straw_adventurer', 'Straw Adventurer Hat', 'hat',
     'A breezy straw hat made for roaming every arena.',
     650, 'uncommon', true, true, true, 'character', 'hats',
     false, 'daily', null, null, 214),
    ('hat_cowboy_wide', 'Wide-Brim Cowboy Hat', 'hat',
     'A dramatic wide-brim frontier hat with championship presence.',
     850, 'rare', true, true, true, 'character', 'hats',
     false, 'monthly', null, null, 215),
    ('hat_fedora_white', 'White Fedora', 'hat',
     'A polished white fedora for a clean winner-circle entrance.',
     850, 'rare', true, true, true, 'character', 'hats',
     false, 'monthly', null, null, 216),
    ('hat_top', 'Top Hat', 'hat',
     'Formal headwear for competitors with serious podium plans.',
     850, 'rare', true, true, true, 'character', 'hats',
     false, 'monthly', null, null, 217),
    ('hat_witch', 'Witch Hat', 'hat',
     'A crooked arena hat with a little midnight magic.',
     850, 'rare', true, true, true, 'character', 'hats',
     false, 'monthly', null, null, 218),
    ('hat_crown', 'Royal Crown', 'hat',
     'A jeweled crown for the competitor who owns the arena.',
     1200, 'epic', true, true, true, 'character', 'hats',
     true, 'monthly', null, null, 219)
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = excluded.item_type,
    description = excluded.description,
    price = excluded.price,
    rarity = excluded.rarity,
    purchasable = true,
    shop_visible = true,
    active = true,
    category = 'character',
    subcategory = 'hats',
    featured = excluded.featured,
    rotation_scope = excluded.rotation_scope,
    rotation_starts_at = null,
    rotation_ends_at = null,
    sort_order = excluded.sort_order;

-- Replace the occupied milestones, then retire the old locations. Previously
-- granted items remain in player_inventory and therefore remain permanent.
insert into public.season_reward_milestones (
    season_id, road_type, threshold, display_name, gun_tokens, item_id, rarity
) values
    ('beta-season', 'level', 10, 'Rice Hat', 0,
        'beta_s1_level_30_hat', 'uncommon'),
    ('beta-season', 'trophy', 5, 'Pimp Hat', 0,
        'beta_s1_ace_hat', 'epic')
on conflict (season_id, road_type, threshold) do update set
    display_name = excluded.display_name,
    gun_tokens = excluded.gun_tokens,
    item_id = excluded.item_id,
    rarity = excluded.rarity;

delete from public.season_reward_milestones
where season_id = 'beta-season'
  and ((road_type = 'level' and threshold = 30)
    or (road_type = 'trophy' and threshold = 20));

-- Backfill both new placements for players who had already crossed them.
insert into public.player_inventory (player_id, item_id, obtained_at, source)
select progress.player_id, 'beta_s1_level_30_hat', now(),
       'beta_season_level_road_rebalance'
from public.player_season_progress progress
where progress.season_id = 'beta-season'
  and progress.season_level >= 10
on conflict (player_id, item_id) do nothing;

insert into public.player_reward_unlocks (
    player_id, season_id, road_type, threshold, item_id, unlocked_at
)
select progress.player_id, 'beta-season', 'level', 10,
       'beta_s1_level_30_hat', now()
from public.player_season_progress progress
where progress.season_id = 'beta-season'
  and progress.season_level >= 10
on conflict (player_id, season_id, road_type, threshold) do update set
    item_id = excluded.item_id;

insert into public.player_inventory (player_id, item_id, obtained_at, source)
select progress.player_id, 'beta_s1_ace_hat', now(),
       'beta_season_trophy_road_rebalance'
from public.player_season_progress progress
where progress.season_id = 'beta-season'
  and progress.trophies >= 5
on conflict (player_id, item_id) do nothing;

insert into public.player_reward_unlocks (
    player_id, season_id, road_type, threshold, item_id, unlocked_at
)
select progress.player_id, 'beta-season', 'trophy', 5,
       'beta_s1_ace_hat', now()
from public.player_season_progress progress
where progress.season_id = 'beta-season'
  and progress.trophies >= 5
on conflict (player_id, season_id, road_type, threshold) do update set
    item_id = excluded.item_id;

commit;
