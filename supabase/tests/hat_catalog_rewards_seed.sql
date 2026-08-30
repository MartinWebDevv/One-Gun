\set ON_ERROR_STOP on

-- Disposable-only fixture for hat_catalog_rewards_test.sql. This simulates a
-- player who had already earned the rewards occupying Level 10 and Trophy 5,
-- plus permanent ownership from the retired Trophy 20 milestone.

insert into auth.users (id) values
    ('10000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

insert into public.profiles (id, username) values
    ('10000000-0000-0000-0000-000000000001', 'hat_test_player')
on conflict (id) do nothing;

insert into public.game_seasons (
    id, display_name, starts_at, ends_at, active, ruleset_id
) values (
    'beta-season', 'Beta Season', now() - interval '30 days',
    now() + interval '300 days', true, 'classic_beta_v1'
) on conflict (id) do nothing;

insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope
) values
    ('beta_s1_level_10_color', 'Beta Circuit Color', 'character_skin',
     'Existing Level 10 fixture.', 0, 'common', false, false, true,
     'character', 'colors', false, 'reward'),
    ('beta_s1_level_30_hat', 'Range Tester Hat', 'hat',
     'Existing Level 30 fixture.', 0, 'uncommon', false, false, true,
     'character', 'hats', false, 'reward'),
    ('beta_s1_trophy_5_gun', 'Five-Win Finish', 'gun_skin',
     'Existing Trophy 5 fixture.', 0, 'rare', false, false, true,
     'weapons', 'gun_skins', false, 'reward'),
    ('beta_s1_ace_outfit', 'Beta Ace Outfit', 'outfit_bundle',
     'Existing Trophy 20 fixture.', 0, 'epic', false, false, true,
     'character', 'outfits', false, 'reward'),
    ('beta_s1_ace_hat', 'Beta Ace Hat', 'hat',
     'Existing bundle hat fixture.', 0, 'epic', false, false, true,
     'character', 'hats', false, 'reward')
on conflict (id) do nothing;

insert into public.season_reward_milestones (
    season_id, road_type, threshold, display_name, gun_tokens, item_id, rarity
) values
    ('beta-season', 'level', 10, 'Beta Circuit Color', 0,
        'beta_s1_level_10_color', 'common'),
    ('beta-season', 'level', 30, 'Range Tester Hat', 0,
        'beta_s1_level_30_hat', 'uncommon'),
    ('beta-season', 'trophy', 5, 'Five-Win Finish', 0,
        'beta_s1_trophy_5_gun', 'rare'),
    ('beta-season', 'trophy', 20, 'Beta Ace Outfit', 0,
        'beta_s1_ace_outfit', 'epic')
on conflict (season_id, road_type, threshold) do update set
    display_name = excluded.display_name,
    gun_tokens = excluded.gun_tokens,
    item_id = excluded.item_id,
    rarity = excluded.rarity;

insert into public.player_season_progress (
    player_id, season_id, season_level, trophies
) values (
    '10000000-0000-0000-0000-000000000001', 'beta-season', 12, 6
) on conflict (player_id, season_id) do update set
    season_level = excluded.season_level,
    trophies = excluded.trophies;

insert into public.player_inventory (player_id, item_id, source) values
    ('10000000-0000-0000-0000-000000000001',
        'beta_s1_level_10_color', 'pre_rebalance_level_10'),
    ('10000000-0000-0000-0000-000000000001',
        'beta_s1_trophy_5_gun', 'pre_rebalance_trophy_5'),
    ('10000000-0000-0000-0000-000000000001',
        'beta_s1_ace_outfit', 'pre_rebalance_trophy_20')
on conflict (player_id, item_id) do nothing;

insert into public.player_reward_unlocks (
    player_id, season_id, road_type, threshold, item_id
) values
    ('10000000-0000-0000-0000-000000000001', 'beta-season', 'level', 10,
        'beta_s1_level_10_color'),
    ('10000000-0000-0000-0000-000000000001', 'beta-season', 'trophy', 5,
        'beta_s1_trophy_5_gun')
on conflict (player_id, season_id, road_type, threshold) do update set
    item_id = excluded.item_id;
