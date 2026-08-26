\set ON_ERROR_STOP on

-- Plain PostgreSQL integration assertions for the One Gun progression
-- migration. The harness supplies auth.users/auth.uid and the linked public
-- schema before this file runs.

begin;

-- The schema-only linked dump intentionally has no production catalog rows;
-- seed the existing starter theme required by the live loadout trigger.
insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory, rotation_scope
) values
    ('base_one_gun', 'Original One Gun', 'gun_skin', '', 0, 'standard',
        false, false, true, 'weapons', 'gun_skins', 'none'),
    ('base_arena_melee', 'Original Melee Finish', 'melee_skin', '', 0, 'standard',
        false, false, true, 'weapons', 'melee_skins', 'none'),
    ('hip_hop_dance', 'Hip Hop', 'victory_dance', '', 0, 'standard',
        false, false, true, 'victory', 'dances', 'none'),
    ('swing_dance', 'Swing Dance', 'victory_dance', '', 0, 'standard',
        false, false, true, 'victory', 'dances', 'none'),
    ('wc_theme_ceremony_march', 'Ceremony March', 'ceremony_theme', '',
        0, 'standard', false, true, true, 'audio', 'winners_circle', 'seasonal_starter')
on conflict (id) do nothing;

insert into auth.users (id) values
    ('10000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000003');

insert into public.profiles (id, username) values
    ('10000000-0000-0000-0000-000000000001', 'RewardOne'),
    ('10000000-0000-0000-0000-000000000002', 'RewardTwo'),
    ('10000000-0000-0000-0000-000000000003', 'RewardThree');
insert into public.player_currency (player_id, gun_tokens) values
    ('10000000-0000-0000-0000-000000000001', 0),
    ('10000000-0000-0000-0000-000000000002', 0),
    ('10000000-0000-0000-0000-000000000003', 0);
insert into public.player_loadouts (player_id) values
    ('10000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000003');
insert into public.player_progression (player_id) values
    ('10000000-0000-0000-0000-000000000001'),
    ('10000000-0000-0000-0000-000000000002'),
    ('10000000-0000-0000-0000-000000000003');
insert into public.player_season_progress (player_id, season_id) values
    ('10000000-0000-0000-0000-000000000001', 'beta-season'),
    ('10000000-0000-0000-0000-000000000002', 'beta-season'),
    ('10000000-0000-0000-0000-000000000003', 'beta-season');

do $$
begin
    if public.one_gun_season_xp_required(1) <> 150
       or public.one_gun_season_xp_required(100) <> 348
       or public.one_gun_season_xp_required(200) <> 548
       or public.one_gun_season_xp_required(300) <> 748
       or public.one_gun_xp_required(100) <> 348
       or public.one_gun_career_xp_required(1) <> 400
       or public.one_gun_career_xp_required(545) <> 400 then
        raise exception 'Season or Career XP requirement curve is incorrect';
    end if;
end;
$$;


-- Put player one just below Level 5 to prove the milestone Gun Tokens are
-- added once and only once alongside the match reward.
update public.player_season_progress
set season_level = 4, xp_into_level = 100
where player_id = '10000000-0000-0000-0000-000000000001'
  and season_id = 'beta-season';

create temporary table reward_test_payload (result jsonb not null);
insert into reward_test_payload values (jsonb_build_object(
    'schema', 2,
    'match_id', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'ruleset_id', 'classic_beta_v1',
    'mode', 'one_gun',
    'mode_name', 'CLASSIC ONE GUN',
    'map_id', 'res://maps/neon_circuit/neon_circuit.tscn',
    'expected_humans', 3,
    'official', true,
    'champion_actor_id', 1,
    'trophy_awarded', true,
    'reward_state', 'verifying',
    'entries', jsonb_build_array(
        jsonb_build_object(
            'actor_id', 1, 'peer_id', 1, 'name', 'RewardOne',
            'is_bot', false, 'placement', 1, 'round_wins', 3,
            'kills', 12, 'deaths', 4, 'disarms', 4,
            'rounds_participated', 3, 'active_samples', 12,
            'activity_eligible', true,
            'reward_claim_hash', encode(extensions.digest('111111111111111111111111111111111111111111111111', 'sha256'), 'hex')
        ),
        jsonb_build_object(
            'actor_id', 2, 'peer_id', 2, 'name', 'RewardTwo',
            'is_bot', false, 'placement', 2, 'round_wins', 0,
            'kills', 9, 'deaths', 5, 'disarms', 5,
            'rounds_participated', 3, 'active_samples', 9,
            'activity_eligible', true,
            'reward_claim_hash', encode(extensions.digest('222222222222222222222222222222222222222222222222', 'sha256'), 'hex')
        ),
        jsonb_build_object(
            'actor_id', 3, 'peer_id', 3, 'name', 'RewardThree',
            'is_bot', false, 'placement', 3, 'round_wins', 0,
            'kills', 2, 'deaths', 6, 'disarms', 1,
            'rounds_participated', 3, 'active_samples', 8,
            'activity_eligible', true,
            'reward_claim_hash', encode(extensions.digest('333333333333333333333333333333333333333333333333', 'sha256'), 'hex')
        )
    )
));

-- Each caller deliberately supplies a different presentation-only viewer ID.
-- The public RPC must remove it before hashing the shared match result.
select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000001', false);
select public.confirm_official_beta_match(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1, '111111111111111111111111111111111111111111111111',
    (select result || jsonb_build_object('local_peer_id', 1) from reward_test_payload));

select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000002', false);
select public.confirm_official_beta_match(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 2, '222222222222222222222222222222222222222222222222',
    (select result || jsonb_build_object('local_peer_id', 2) from reward_test_payload));

select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000003', false);
select public.confirm_official_beta_match(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 3, '333333333333333333333333333333333333333333333333',
    (select result || jsonb_build_object('local_peer_id', 3) from reward_test_payload));

do $$
declare
    v_count integer;
    v_tokens bigint;
    v_xp integer;
    v_trophies integer;
    v_level integer;
    v_level_xp integer;
    v_career_xp integer;
    v_daily boolean;
begin
    select count(*) into v_count from public.match_rewards
    where match_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    if v_count <> 3 then
        raise exception 'Expected 3 match rewards, got %', v_count;
    end if;

    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_tokens <> 400 then
        raise exception 'Winner expected 400 tokens (250 placement + 100 daily + 50 road), got %', v_tokens;
    end if;
    select xp_delta, trophy_delta,
           coalesce((breakdown->>'daily_victory_bonus_awarded')::boolean, false)
    into v_xp, v_trophies, v_daily
    from public.match_rewards
    where match_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      and player_id = '10000000-0000-0000-0000-000000000001';
    if v_xp <> 122 or v_trophies <> 1 or not v_daily then
        raise exception 'Winner expected 97 match XP + 25 daily XP and 1 Trophy; got % / % / daily %',
            v_xp, v_trophies, v_daily;
    end if;
    select season_level, xp_into_level, trophies into v_level, v_level_xp, v_trophies
    from public.player_season_progress
    where player_id = '10000000-0000-0000-0000-000000000001'
      and season_id = 'beta-season';
    if v_level <> 5 or v_level_xp <> 66 or v_trophies <> 1 then
        raise exception 'Winner expected Season Level 5 at 66 XP / 1 Trophy, got % / % / %',
            v_level, v_level_xp, v_trophies;
    end if;
    select career_xp_into_level into v_career_xp
    from public.player_progression
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_career_xp <> 97 then
        raise exception 'Daily Season XP leaked into Career XP: expected 97, got %', v_career_xp;
    end if;
    select count(*) into v_count from public.player_daily_victory_bonuses
    where player_id = '10000000-0000-0000-0000-000000000001'
      and bonus_date = (timezone('UTC', now()))::date;
    if v_count <> 1 then
        raise exception 'Expected one server-authoritative daily victory grant, got %', v_count;
    end if;
    if not exists (
        select 1 from public.player_inventory
        where player_id = '10000000-0000-0000-0000-000000000001'
          and item_id = 'beta_s1_trophy_1_crest'
    ) then
        raise exception 'First Trophy permanent cosmetic was not granted';
    end if;

    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000002';
    if v_tokens <> 200 then
        raise exception 'Second place expected 200 Gun Tokens, got %', v_tokens;
    end if;
    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000003';
    if v_tokens <> 150 then
        raise exception 'Third place in a 3-player match expected 150 Gun Tokens, got %', v_tokens;
    end if;
end;
$$;

-- An identical confirmation must return the existing receipt without paying
-- twice or duplicating any match ledger entry.
select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000001', false);
select public.confirm_official_beta_match(
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 1, '111111111111111111111111111111111111111111111111',
    (select result || jsonb_build_object('local_peer_id', 1) from reward_test_payload));
do $$
declare v_count integer; v_tokens bigint;
begin
    select count(*) into v_count from public.wallet_ledger
    where match_id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
      and player_id = '10000000-0000-0000-0000-000000000001';
    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_count <> 1 or v_tokens <> 400 then
        raise exception 'Receipt was not idempotent: ledger %, balance %', v_count, v_tokens;
    end if;
end;
$$;

-- A match that began Official remains reward-eligible when everyone but one
-- finisher leaves. The sole finisher settles with one confirmation, retains
-- only actual XP statistics, receives first-place Tokens, and earns a Trophy.
truncate reward_test_payload;
insert into reward_test_payload values (jsonb_build_object(
    'schema', 3,
    'match_id', 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    'ruleset_id', 'classic_beta_v1',
    'mode', 'one_gun',
    'mode_name', 'CLASSIC ONE GUN',
    'map_id', 'res://maps/neon_circuit/neon_circuit.tscn',
    'expected_humans', 3,
    'started_humans', 3,
    'finisher_humans', 1,
    'official', true,
    'champion_actor_id', 1,
    'forfeit_win', true,
    'trophy_awarded', true,
    'reward_state', 'verifying',
    'entries', jsonb_build_array(
        jsonb_build_object(
            'actor_id', 1, 'peer_id', 1, 'name', 'RewardOne',
            'is_bot', false, 'placement', 1, 'round_wins', 0,
            'kills', 0, 'deaths', 0, 'disarms', 0,
            'rounds_participated', 2, 'active_samples', 0,
            'activity_eligible', true, 'finished_match', true,
            'forfeit_winner', true,
            'reward_claim_hash', encode(extensions.digest('111111111111111111111111111111111111111111111111', 'sha256'), 'hex')
        ),
        jsonb_build_object(
            'actor_id', 2, 'peer_id', 2, 'name', 'RewardTwo',
            'is_bot', false, 'placement', 2, 'round_wins', 0,
            'kills', 0, 'deaths', 0, 'disarms', 0,
            'rounds_participated', 1, 'active_samples', 1,
            'activity_eligible', false, 'finished_match', false,
            'forfeit_winner', false,
            'reward_claim_hash', encode(extensions.digest('222222222222222222222222222222222222222222222222', 'sha256'), 'hex')
        ),
        jsonb_build_object(
            'actor_id', 3, 'peer_id', 3, 'name', 'RewardThree',
            'is_bot', false, 'placement', 3, 'round_wins', 0,
            'kills', 0, 'deaths', 0, 'disarms', 0,
            'rounds_participated', 1, 'active_samples', 1,
            'activity_eligible', false, 'finished_match', false,
            'forfeit_winner', false,
            'reward_claim_hash', encode(extensions.digest('333333333333333333333333333333333333333333333333', 'sha256'), 'hex')
        )
    )
));

select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000001', false);
select public.confirm_official_beta_match(
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 1,
    '111111111111111111111111111111111111111111111111',
    (select result from reward_test_payload));

do $$
declare
    v_count integer;
    v_tokens bigint;
    v_xp integer;
    v_trophy integer;
    v_status text;
    v_daily boolean;
    v_level_xp integer;
    v_career_xp integer;
begin
    select status into v_status from public.official_matches
    where match_id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    if v_status <> 'settled' then
        raise exception 'Sole-finisher forfeit did not settle: %', v_status;
    end if;

    select count(*) into v_count from public.match_rewards
    where match_id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    if v_count <> 1 then
        raise exception 'Forfeit expected exactly one finisher reward, got %', v_count;
    end if;

    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_tokens <> 650 then
        raise exception 'Second same-day win expected only another 250 placement Tokens, got %', v_tokens;
    end if;

    select xp_delta, trophy_delta,
           coalesce((breakdown->>'daily_victory_bonus_awarded')::boolean, false)
    into v_xp, v_trophy, v_daily
    from public.match_rewards
    where match_id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
      and player_id = '10000000-0000-0000-0000-000000000001';
    if v_xp <> 45 or v_trophy <> 1 or v_daily then
        raise exception 'Second win expected 45 XP, 1 Trophy, and no repeat daily bonus; got % / % / %',
            v_xp, v_trophy, v_daily;
    end if;

    select count(*) into v_count from public.player_daily_victory_bonuses
    where player_id = '10000000-0000-0000-0000-000000000001'
      and bonus_date = (timezone('UTC', now()))::date;
    if v_count <> 1 then
        raise exception 'Daily victory bonus repeated in the same UTC day: % rows', v_count;
    end if;
    select xp_into_level into v_level_xp
    from public.player_season_progress
    where player_id = '10000000-0000-0000-0000-000000000001'
      and season_id = 'beta-season';
    select career_xp_into_level into v_career_xp
    from public.player_progression
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_level_xp <> 111 or v_career_xp <> 142 then
        raise exception 'Second win XP totals are incorrect: Season % / Career %',
            v_level_xp, v_career_xp;
    end if;

    if exists (
        select 1 from public.match_rewards
        where match_id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
          and player_id <> '10000000-0000-0000-0000-000000000001'
    ) then
        raise exception 'A departed player received a forfeit reward';
    end if;
end;
$$;


-- Exercise the outfit economy rule: 15% off the unowned component sum,
-- permanent ownership of every component, and one-click full-set equip.
insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope
) values
    ('test_hat', 'Test Hat', 'hat', '', 100, 'common', false, false, true,
        'character', 'hats', false, 'none'),
    ('test_shirt', 'Test Shirt', 'shirt', '', 100, 'common', false, false, true,
        'character', 'shirts', false, 'none'),
    ('test_pants', 'Test Pants', 'pants', '', 100, 'common', false, false, true,
        'character', 'pants', false, 'none'),
    ('test_shoes', 'Test Shoes', 'shoes', '', 100, 'common', false, false, true,
        'character', 'shoes', false, 'none'),
    ('test_outfit', 'Test Outfit', 'outfit_bundle', '', 0, 'rare', true, true, true,
        'character', 'outfits', true, 'seasonal_starter');
insert into public.shop_bundle_items (bundle_id, item_id, display_order) values
    ('test_outfit', 'test_hat', 1), ('test_outfit', 'test_shirt', 2),
    ('test_outfit', 'test_pants', 3), ('test_outfit', 'test_shoes', 4);
select set_config('request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000001', false);
update public.player_currency set gun_tokens = 1000
where player_id = '10000000-0000-0000-0000-000000000001';
select public.purchase_shop_item('test_outfit');
select public.equip_outfit('test_outfit');
select public.set_shop_favorite('test_outfit', true);

do $$
declare v_tokens bigint; v_count integer; v_loadout public.player_loadouts%rowtype;
begin
    select gun_tokens into v_tokens from public.player_currency
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_tokens <> 660 then
        raise exception 'Full outfit expected price 340, remaining %, expected 660', v_tokens;
    end if;
    select count(*) into v_count from public.player_inventory
    where player_id = '10000000-0000-0000-0000-000000000001'
      and item_id in ('test_outfit', 'test_hat', 'test_shirt', 'test_pants', 'test_shoes');
    if v_count <> 5 then
        raise exception 'Outfit purchase expected bundle + 4 permanent items, got %', v_count;
    end if;
    select * into v_loadout from public.player_loadouts
    where player_id = '10000000-0000-0000-0000-000000000001';
    if v_loadout.hat <> 'test_hat' or v_loadout.shirt <> 'test_shirt'
       or v_loadout.pants <> 'test_pants' or v_loadout.shoes <> 'test_shoes' then
        raise exception 'One-click outfit equip did not set all four component slots';
    end if;
    if not exists (
        select 1 from public.player_favorites
        where player_id = '10000000-0000-0000-0000-000000000001'
          and item_id = 'test_outfit'
    ) then
        raise exception 'Favorite RPC did not persist the outfit favorite';
    end if;
end;
$$;

do $$
declare v_payload jsonb;
begin
    v_payload := public.get_player_progression();
    if (v_payload#>>'{progress,next_level_xp}')::integer <> 158
       or (v_payload#>>'{career,next_level_xp}')::integer <> 400
       or (v_payload#>>'{career,career_level}')::integer <> 1
       or not (v_payload#>>'{progress,daily_victory_bonus_claimed}')::boolean then
        raise exception 'Progression payload does not expose the new curves/daily state: %',
            v_payload;
    end if;
    if v_payload#>>'{progress,daily_victory_bonus_reset}' <> '00:00 UTC' then
        raise exception 'Daily victory reset label must be UTC';
    end if;
end;
$$;

rollback;

\echo PROGRESSION_REWARD_FUNCTIONAL_TESTS_OK
