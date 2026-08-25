-- One Gun: shared catalog taxonomy, outfit bundles, seasonal progression,
-- majority-confirmed Official Beta match receipts, and auditable economy.
-- The shipped Godot client uses only its publishable key plus player JWT.
-- No service-role or database credential belongs in the game or repository.

begin;

create extension if not exists pgcrypto with schema extensions;

-- -------------------------------------------------------------------------
-- Catalog taxonomy, rotations, popularity, favorites, and outfit bundles.
-- -------------------------------------------------------------------------

alter table public.shop_items
    add column if not exists category text,
    add column if not exists subcategory text,
    add column if not exists featured boolean not null default false,
    add column if not exists rotation_scope text not null default 'none',
    add column if not exists rotation_starts_at timestamptz,
    add column if not exists rotation_ends_at timestamptz,
    add column if not exists purchase_count bigint not null default 0,
    add column if not exists sort_order integer not null default 0;

update public.shop_items
set category = case item_type
        when 'character_skin' then 'character'
        when 'hat' then 'character'
        when 'shirt' then 'character'
        when 'pants' then 'character'
        when 'shoes' then 'character'
        when 'accessory' then 'character'
        when 'outfit_bundle' then 'character'
        when 'gun_skin' then 'weapons'
        when 'melee_skin' then 'weapons'
        when 'emote' then 'victory'
        when 'round_victory_move' then 'victory'
        when 'ceremony_theme' then 'audio'
        else 'featured'
    end,
    subcategory = case item_type
        when 'character_skin' then 'colors'
        when 'hat' then 'hats'
        when 'shirt' then 'shirts'
        when 'pants' then 'pants'
        when 'shoes' then 'shoes'
        when 'accessory' then 'cosmetics'
        when 'outfit_bundle' then 'outfits'
        when 'gun_skin' then 'gun_skins'
        when 'melee_skin' then 'melee_skins'
        when 'emote' then 'podium_dances'
        when 'round_victory_move' then 'round_moves'
        when 'ceremony_theme' then 'winners_circle'
        else 'all'
    end
where category is null or subcategory is null;

alter table public.shop_items
    alter column category set default 'featured',
    alter column category set not null,
    alter column subcategory set default 'all',
    alter column subcategory set not null;

alter table public.shop_items
    drop constraint if exists shop_items_rotation_scope_check,
    add constraint shop_items_rotation_scope_check check (
        rotation_scope in ('daily', 'monthly', 'seasonal_starter', 'seasonal', 'reward', 'none')
    ),
    drop constraint if exists shop_items_purchase_count_check,
    add constraint shop_items_purchase_count_check check (purchase_count >= 0);

alter table public.shop_items
    alter column rotation_scope set default 'none';

-- The old store rows were presentation placeholders, not approved products.
-- Keep anything already owned visible through the authenticated ownership RLS
-- policy, but remove those placeholders from every public rotation. New live
-- products must be deliberately assigned to a rotation by content tooling.
update public.shop_items
set featured = false,
    rotation_scope = 'none',
    rotation_starts_at = null,
    rotation_ends_at = null,
    purchasable = false,
    shop_visible = false
where item_type <> 'ceremony_theme';

update public.shop_items
set category = 'audio',
    subcategory = 'winners_circle',
    featured = true,
    rotation_scope = 'seasonal_starter',
    rotation_starts_at = coalesce(rotation_starts_at, '2026-08-24 00:00:00+00'),
    rotation_ends_at = coalesce(rotation_ends_at, '2026-11-24 00:00:00+00')
where item_type = 'ceremony_theme' and shop_visible = true;

create table if not exists public.shop_bundle_items (
    bundle_id text not null references public.shop_items(id) on delete cascade,
    item_id text not null references public.shop_items(id) on delete restrict,
    display_order integer not null default 0,
    primary key (bundle_id, item_id),
    constraint shop_bundle_no_self_reference check (bundle_id <> item_id)
);

create table if not exists public.player_favorites (
    player_id uuid not null references public.profiles(id) on delete cascade,
    item_id text not null references public.shop_items(id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (player_id, item_id)
);

create table if not exists public.player_item_usage (
    player_id uuid not null references public.profiles(id) on delete cascade,
    item_id text not null references public.shop_items(id) on delete cascade,
    equip_count bigint not null default 0,
    last_equipped_at timestamptz,
    primary key (player_id, item_id),
    constraint player_item_usage_count_check check (equip_count >= 0)
);

create table if not exists public.purchase_ledger (
    id bigint generated by default as identity primary key,
    player_id uuid not null references public.profiles(id) on delete cascade,
    item_id text not null references public.shop_items(id) on delete restrict,
    original_price bigint not null,
    price_paid bigint not null,
    discount_amount bigint not null default 0,
    purchased_at timestamptz not null default now(),
    constraint purchase_ledger_prices_check check (
        original_price >= 0 and price_paid >= 0 and discount_amount >= 0
    )
);

alter table public.player_loadouts
    add column if not exists shirt text,
    add column if not exists pants text,
    add column if not exists shoes text,
    add column if not exists round_victory_move text,
    add column if not exists profile_badge text;

-- -------------------------------------------------------------------------
-- Seasons, progression, roads, career records, and match receipts.
-- -------------------------------------------------------------------------

create table if not exists public.game_seasons (
    id text primary key,
    display_name text not null,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    active boolean not null default false,
    ruleset_id text not null default 'classic_beta_v1',
    created_at timestamptz not null default now(),
    constraint game_seasons_dates_check check (ends_at > starts_at)
);

create unique index if not exists game_seasons_one_active
    on public.game_seasons ((active)) where active = true;

insert into public.game_seasons (
    id, display_name, starts_at, ends_at, active, ruleset_id
) values (
    'beta-season', 'BETA SEASON',
    '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00',
    true, 'classic_beta_v1'
)
on conflict (id) do update set
    display_name = excluded.display_name,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    ruleset_id = excluded.ruleset_id;

create table if not exists public.player_progression (
    player_id uuid primary key references public.profiles(id) on delete cascade,
    career_levels_earned integer not null default 0,
    career_xp_into_level integer not null default 0,
    updated_at timestamptz not null default now(),
    constraint player_progression_levels_check check (career_levels_earned >= 0),
    constraint player_progression_xp_check check (career_xp_into_level >= 0)
);

create table if not exists public.player_season_progress (
    player_id uuid not null references public.profiles(id) on delete cascade,
    season_id text not null references public.game_seasons(id) on delete restrict,
    season_level integer not null default 1,
    xp_into_level integer not null default 0,
    total_xp bigint not null default 0,
    trophies integer not null default 0,
    official_matches integer not null default 0,
    classic_wins integer not null default 0,
    round_wins integer not null default 0,
    kills integer not null default 0,
    deaths integer not null default 0,
    disarms integer not null default 0,
    updated_at timestamptz not null default now(),
    primary key (player_id, season_id),
    constraint player_season_progress_nonnegative check (
        season_level >= 1 and xp_into_level >= 0 and total_xp >= 0
        and trophies >= 0 and official_matches >= 0 and classic_wins >= 0
        and round_wins >= 0 and kills >= 0 and deaths >= 0 and disarms >= 0
    )
);

create table if not exists public.player_mode_stats (
    player_id uuid not null references public.profiles(id) on delete cascade,
    mode text not null,
    matches integer not null default 0,
    wins integer not null default 0,
    best_finish integer,
    round_wins integer not null default 0,
    kills integer not null default 0,
    deaths integer not null default 0,
    disarms integer not null default 0,
    updated_at timestamptz not null default now(),
    primary key (player_id, mode),
    constraint player_mode_stats_mode_check check (
        mode in ('one_gun', 'all_gun', 'one_of_us')
    ),
    constraint player_mode_stats_finish_check check (
        best_finish is null or best_finish between 1 and 10
    )
);

create table if not exists public.season_archives (
    player_id uuid not null references public.profiles(id) on delete cascade,
    season_id text not null references public.game_seasons(id) on delete restrict,
    season_name text not null,
    final_level integer not null,
    final_xp bigint not null,
    trophies integer not null,
    classic_wins integer not null,
    official_matches integer not null,
    road_summary jsonb not null default '{}'::jsonb,
    archived_at timestamptz not null default now(),
    primary key (player_id, season_id)
);

create table if not exists public.season_reward_milestones (
    season_id text not null references public.game_seasons(id) on delete cascade,
    road_type text not null,
    threshold integer not null,
    display_name text not null,
    gun_tokens bigint not null default 0,
    item_id text references public.shop_items(id) on delete restrict,
    rarity text not null default 'standard',
    primary key (season_id, road_type, threshold),
    constraint season_reward_road_check check (road_type in ('level', 'trophy')),
    constraint season_reward_threshold_check check (threshold > 0),
    constraint season_reward_tokens_check check (gun_tokens >= 0)
);

create table if not exists public.player_reward_unlocks (
    player_id uuid not null references public.profiles(id) on delete cascade,
    season_id text not null references public.game_seasons(id) on delete restrict,
    road_type text not null,
    threshold integer not null,
    item_id text references public.shop_items(id) on delete restrict,
    unlocked_at timestamptz not null default now(),
    primary key (player_id, season_id, road_type, threshold),
    constraint player_reward_unlock_road_check check (
        road_type in ('level', 'trophy', 'prestige_loop')
    )
);

create table if not exists public.official_matches (
    match_id text primary key,
    ruleset_id text not null,
    mode text not null,
    map_id text not null,
    expected_players integer not null,
    result_hash text not null,
    result jsonb not null,
    status text not null default 'pending',
    created_at timestamptz not null default now(),
    settled_at timestamptz,
    constraint official_matches_player_count_check check (expected_players between 3 and 10),
    constraint official_matches_status_check check (status in ('pending', 'settled', 'expired'))
);

create table if not exists public.official_match_confirmations (
    match_id text not null references public.official_matches(match_id) on delete cascade,
    player_id uuid not null references public.profiles(id) on delete cascade,
    actor_id integer not null,
    result_hash text not null,
    confirmed_at timestamptz not null default now(),
    primary key (match_id, player_id),
    unique (match_id, actor_id)
);

create table if not exists public.match_rewards (
    match_id text not null references public.official_matches(match_id) on delete cascade,
    player_id uuid not null references public.profiles(id) on delete cascade,
    season_id text not null references public.game_seasons(id) on delete restrict,
    actor_id integer not null,
    mode text not null,
    map_id text not null,
    placement integer not null,
    round_wins integer not null default 0,
    kills integer not null default 0,
    deaths integer not null default 0,
    disarms integer not null default 0,
    xp_delta integer not null default 0,
    gun_tokens_delta integer not null default 0,
    trophy_delta integer not null default 0,
    eligible boolean not null default true,
    breakdown jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    primary key (match_id, player_id)
);

create table if not exists public.wallet_ledger (
    id bigint generated by default as identity primary key,
    player_id uuid not null references public.profiles(id) on delete cascade,
    match_id text references public.official_matches(match_id) on delete restrict,
    amount bigint not null,
    reason text not null,
    balance_after bigint not null,
    created_at timestamptz not null default now()
);

create index if not exists match_rewards_player_history
    on public.match_rewards (player_id, created_at desc);
create index if not exists wallet_ledger_player_history
    on public.wallet_ledger (player_id, created_at desc);
create index if not exists purchase_ledger_item_popularity
    on public.purchase_ledger (item_id, purchased_at desc);

-- -------------------------------------------------------------------------
-- Beta Season reward content. These are permanent stable ownership IDs.
-- Their current client presentation is intentionally safe data-only until the
-- production art/animation assets are supplied and mapped locally.
-- -------------------------------------------------------------------------

insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope
) values
    ('beta_s1_level_10_color', 'Beta Circuit Color', 'character_skin',
     'A Beta Season color earned from the Level Road.', 0, 'common', false, false, true,
     'character', 'colors', false, 'reward'),
    ('beta_s1_level_30_hat', 'Range Tester Hat', 'hat',
     'A field-tested hat earned from the Beta Season Level Road.', 0, 'uncommon', false, false, true,
     'character', 'hats', false, 'reward'),
    ('beta_s1_level_50_melee', 'Circuit Breaker Finish', 'melee_skin',
     'A rare Beta Season finish for melee weapons.', 0, 'rare', false, false, true,
     'weapons', 'melee_skins', false, 'reward'),
    ('beta_s1_level_70_pose', 'Locked In', 'emote',
     'A poised podium celebration from the Beta Season Level Road.', 0, 'rare', false, false, true,
     'victory', 'podium_poses', false, 'reward'),
    ('beta_s1_level_90_theme', 'Beta Afterglow', 'ceremony_theme',
     'An epic Winners Circle theme reserved for Beta Season veterans.', 0, 'epic', false, false, true,
     'audio', 'winners_circle', false, 'reward'),
    ('beta_s1_level_100_gun', 'Beta One Gun', 'gun_skin',
     'The legendary centerpiece for reaching Level 100 in the Beta Season.', 0, 'legendary', false, false, true,
     'weapons', 'gun_skins', false, 'reward'),
    ('beta_s1_trophy_1_crest', 'First Victory Crest', 'profile_badge',
     'Permanent proof of a first Official Classic Beta victory.', 0, 'common', false, false, true,
     'profile', 'badges', false, 'reward'),
    ('beta_s1_trophy_3_color', 'Bronze Victor Color', 'character_skin',
     'An exclusive color earned at three Beta Season trophies.', 0, 'uncommon', false, false, true,
     'character', 'colors', false, 'reward'),
    ('beta_s1_trophy_5_gun', 'Five-Win Finish', 'gun_skin',
     'A rare One Gun finish earned at five Beta Season trophies.', 0, 'rare', false, false, true,
     'weapons', 'gun_skins', false, 'reward'),
    ('beta_s1_trophy_10_pose', 'Ten Count', 'emote',
     'A podium pose earned at ten Beta Season trophies.', 0, 'rare', false, false, true,
     'victory', 'podium_poses', false, 'reward'),
    ('beta_s1_ace_outfit', 'Beta Ace Outfit', 'outfit_bundle',
     'A complete four-piece champion set earned at twenty Beta Season trophies.', 0, 'epic', false, false, true,
     'character', 'outfits', false, 'reward'),
    ('beta_s1_ace_hat', 'Beta Ace Hat', 'hat',
     'The hat from the Beta Ace Outfit.', 0, 'epic', false, false, true,
     'character', 'hats', false, 'reward'),
    ('beta_s1_ace_shirt', 'Beta Ace Shirt', 'shirt',
     'The shirt from the Beta Ace Outfit.', 0, 'epic', false, false, true,
     'character', 'shirts', false, 'reward'),
    ('beta_s1_ace_pants', 'Beta Ace Pants', 'pants',
     'The pants from the Beta Ace Outfit.', 0, 'epic', false, false, true,
     'character', 'pants', false, 'reward'),
    ('beta_s1_ace_shoes', 'Beta Ace Shoes', 'shoes',
     'The shoes from the Beta Ace Outfit.', 0, 'epic', false, false, true,
     'character', 'shoes', false, 'reward'),
    ('beta_s1_trophy_35_dance', 'Thirty-Five Alive', 'emote',
     'An animated champion move earned at thirty-five Beta Season trophies.', 0, 'epic', false, false, true,
     'victory', 'podium_dances', false, 'reward'),
    ('beta_s1_trophy_50_relic', 'One Gun Champion Relic', 'accessory',
     'The legendary champion item for fifty Official Classic Beta victories.', 0, 'legendary', false, false, true,
     'character', 'cosmetics', false, 'reward')
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = excluded.item_type,
    description = excluded.description,
    rarity = excluded.rarity,
    purchasable = false,
    shop_visible = false,
    active = true,
    category = excluded.category,
    subcategory = excluded.subcategory,
    rotation_scope = 'reward';

insert into public.shop_bundle_items (bundle_id, item_id, display_order) values
    ('beta_s1_ace_outfit', 'beta_s1_ace_hat', 1),
    ('beta_s1_ace_outfit', 'beta_s1_ace_shirt', 2),
    ('beta_s1_ace_outfit', 'beta_s1_ace_pants', 3),
    ('beta_s1_ace_outfit', 'beta_s1_ace_shoes', 4)
on conflict (bundle_id, item_id) do update set
    display_order = excluded.display_order;

insert into public.season_reward_milestones (
    season_id, road_type, threshold, display_name, gun_tokens, item_id, rarity
) values
    ('beta-season', 'level', 5, '50 Gun Tokens', 50, null, 'standard'),
    ('beta-season', 'level', 10, 'Beta Circuit Color', 0, 'beta_s1_level_10_color', 'common'),
    ('beta-season', 'level', 15, '75 Gun Tokens', 75, null, 'standard'),
    ('beta-season', 'level', 25, '75 Gun Tokens', 75, null, 'standard'),
    ('beta-season', 'level', 30, 'Range Tester Hat', 0, 'beta_s1_level_30_hat', 'uncommon'),
    ('beta-season', 'level', 35, '100 Gun Tokens', 100, null, 'standard'),
    ('beta-season', 'level', 45, '100 Gun Tokens', 100, null, 'standard'),
    ('beta-season', 'level', 50, 'Circuit Breaker Finish', 0, 'beta_s1_level_50_melee', 'rare'),
    ('beta-season', 'level', 55, '125 Gun Tokens', 125, null, 'standard'),
    ('beta-season', 'level', 65, '125 Gun Tokens', 125, null, 'standard'),
    ('beta-season', 'level', 70, 'Locked In', 0, 'beta_s1_level_70_pose', 'rare'),
    ('beta-season', 'level', 75, '150 Gun Tokens', 150, null, 'standard'),
    ('beta-season', 'level', 85, '150 Gun Tokens', 150, null, 'standard'),
    ('beta-season', 'level', 90, 'Beta Afterglow', 0, 'beta_s1_level_90_theme', 'epic'),
    ('beta-season', 'level', 95, '200 Gun Tokens', 200, null, 'standard'),
    ('beta-season', 'level', 100, 'Beta One Gun', 0, 'beta_s1_level_100_gun', 'legendary'),
    ('beta-season', 'trophy', 1, 'First Victory Crest', 0, 'beta_s1_trophy_1_crest', 'common'),
    ('beta-season', 'trophy', 3, 'Bronze Victor Color', 0, 'beta_s1_trophy_3_color', 'uncommon'),
    ('beta-season', 'trophy', 5, 'Five-Win Finish', 0, 'beta_s1_trophy_5_gun', 'rare'),
    ('beta-season', 'trophy', 10, 'Ten Count', 0, 'beta_s1_trophy_10_pose', 'rare'),
    ('beta-season', 'trophy', 20, 'Beta Ace Outfit', 0, 'beta_s1_ace_outfit', 'epic'),
    ('beta-season', 'trophy', 35, 'Thirty-Five Alive', 0, 'beta_s1_trophy_35_dance', 'epic'),
    ('beta-season', 'trophy', 50, 'One Gun Champion Relic', 0, 'beta_s1_trophy_50_relic', 'legendary')
on conflict (season_id, road_type, threshold) do update set
    display_name = excluded.display_name,
    gun_tokens = excluded.gun_tokens,
    item_id = excluded.item_id,
    rarity = excluded.rarity;

-- -------------------------------------------------------------------------
-- Internal helpers. They are security-definer only so authenticated clients
-- cannot call low-level grant or ledger paths directly.
-- -------------------------------------------------------------------------

create or replace function public.one_gun_xp_required(p_level integer)
returns integer
language sql
immutable
as $$
    select least(250 + 5 * (greatest(p_level, 1) - 1), 750)::integer;
$$;

create or replace function public.one_gun_grant_inventory_item(
    p_player_id uuid, p_item_id text, p_source text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_item_id is null or not exists (
        select 1 from public.shop_items where id = p_item_id and active = true
    ) then
        return;
    end if;

    insert into public.player_inventory (player_id, item_id, obtained_at, source)
    values (p_player_id, p_item_id, now(), p_source)
    on conflict (player_id, item_id) do nothing;

    if exists (
        select 1 from public.shop_items
        where id = p_item_id and item_type = 'outfit_bundle'
    ) then
        insert into public.player_inventory (player_id, item_id, obtained_at, source)
        select p_player_id, bundle.item_id, now(), p_source
        from public.shop_bundle_items bundle
        join public.shop_items component on component.id = bundle.item_id
        where bundle.bundle_id = p_item_id and component.active = true
        on conflict (player_id, item_id) do nothing;
    end if;
end;
$$;

create or replace function public.one_gun_grant_due_rewards(
    p_player_id uuid,
    p_season_id text,
    p_road_type text,
    p_old_value integer,
    p_new_value integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_reward record;
    v_inserted integer;
    v_bonus_tokens bigint := 0;
    v_unlocks jsonb := '[]'::jsonb;
    v_threshold integer;
begin
    if p_new_value <= p_old_value then
        return jsonb_build_object('gun_tokens', 0, 'unlocks', v_unlocks);
    end if;

    for v_reward in
        select *
        from public.season_reward_milestones
        where season_id = p_season_id
          and road_type = p_road_type
          and threshold > p_old_value
          and threshold <= p_new_value
        order by threshold
    loop
        insert into public.player_reward_unlocks (
            player_id, season_id, road_type, threshold, item_id
        ) values (
            p_player_id, p_season_id, p_road_type,
            v_reward.threshold, v_reward.item_id
        ) on conflict do nothing;
        get diagnostics v_inserted = row_count;
        if v_inserted = 0 then
            continue;
        end if;

        v_bonus_tokens := v_bonus_tokens + v_reward.gun_tokens;
        if v_reward.item_id is not null then
            perform public.one_gun_grant_inventory_item(
                p_player_id, v_reward.item_id,
                'beta_season_' || p_road_type || '_road'
            );
        end if;
        v_unlocks := v_unlocks || jsonb_build_array(jsonb_build_object(
            'road', p_road_type,
            'threshold', v_reward.threshold,
            'display_name', v_reward.display_name,
            'gun_tokens', v_reward.gun_tokens,
            'item_id', v_reward.item_id,
            'rarity', v_reward.rarity
        ));
    end loop;

    -- The authored cosmetic road ends at 100. Dedicated players continue
    -- indefinitely and receive a restrained 100 Tokens every ten levels.
    if p_road_type = 'level' and p_new_value > 100 then
        v_threshold := ((greatest(p_old_value, 100) / 10) + 1) * 10;
        while v_threshold <= p_new_value loop
            insert into public.player_reward_unlocks (
                player_id, season_id, road_type, threshold, item_id
            ) values (
                p_player_id, p_season_id, 'prestige_loop', v_threshold, null
            ) on conflict do nothing;
            get diagnostics v_inserted = row_count;
            if v_inserted > 0 then
                v_bonus_tokens := v_bonus_tokens + 100;
                v_unlocks := v_unlocks || jsonb_build_array(jsonb_build_object(
                    'road', 'prestige_loop',
                    'threshold', v_threshold,
                    'display_name', 'Prestige Level Tokens',
                    'gun_tokens', 100,
                    'item_id', null,
                    'rarity', 'standard'
                ));
            end if;
            v_threshold := v_threshold + 10;
        end loop;
    end if;

    return jsonb_build_object(
        'gun_tokens', v_bonus_tokens,
        'unlocks', v_unlocks
    );
end;
$$;

create or replace function public.one_gun_reward_receipt_json(
    p_match_id text, p_player_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'state', case when reward.eligible then 'settled' else 'ineligible' end,
        'match_id', reward.match_id,
        'persisted', true,
        'eligible', reward.eligible,
        'xp_delta', reward.xp_delta,
        'gun_tokens_delta', reward.gun_tokens_delta,
        'trophy_delta', reward.trophy_delta,
        'breakdown', reward.breakdown,
        'unlocks', coalesce(reward.breakdown->'unlocks', '[]'::jsonb),
        'level_road_tokens', coalesce((reward.breakdown->>'level_road_tokens')::integer, 0),
        'new_season_level', coalesce((reward.breakdown->>'new_season_level')::integer, 1),
        'new_season_trophies', coalesce((reward.breakdown->>'new_season_trophies')::integer, 0),
        'new_gun_token_balance', coalesce((reward.breakdown->>'new_gun_token_balance')::bigint, 0),
        'new_lifetime_prestige', coalesce((reward.breakdown->>'new_lifetime_prestige')::integer, 0),
        'new_lifetime_level', coalesce((reward.breakdown->>'new_lifetime_level')::integer, 1)
    )
    from public.match_rewards reward
    where reward.match_id = p_match_id and reward.player_id = p_player_id;
$$;

create or replace function public.one_gun_award_confirmed_player(
    p_match_id text, p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_match public.official_matches%rowtype;
    v_confirmation public.official_match_confirmations%rowtype;
    v_entry jsonb;
    v_season_id text;
    v_eligible boolean;
    v_placement integer;
    v_round_wins integer;
    v_kills integer;
    v_deaths integer;
    v_disarms integer;
    v_xp_participation integer := 0;
    v_xp_rounds integer := 0;
    v_xp_placement integer := 0;
    v_xp_kills integer := 0;
    v_xp_disarms integer := 0;
    v_xp_total integer := 0;
    v_token_participation integer := 0;
    v_token_rounds integer := 0;
    v_token_placement integer := 0;
    v_token_kills integer := 0;
    v_token_disarms integer := 0;
    v_match_tokens integer := 0;
    v_trophy integer := 0;
    v_old_level integer;
    v_new_level integer;
    v_season_xp integer;
    v_old_trophies integer;
    v_new_trophies integer;
    v_career_levels integer;
    v_career_xp integer;
    v_level_rewards jsonb;
    v_trophy_rewards jsonb;
    v_level_bonus integer := 0;
    v_unlocks jsonb := '[]'::jsonb;
    v_total_tokens integer := 0;
    v_balance bigint := 0;
    v_breakdown jsonb;
begin
    if exists (
        select 1 from public.match_rewards
        where match_id = p_match_id and player_id = p_player_id
    ) then
        return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
    end if;

    select * into v_match
    from public.official_matches
    where match_id = p_match_id and status = 'settled';
    if not found then
        return jsonb_build_object('state', 'pending', 'persisted', false);
    end if;

    select * into v_confirmation
    from public.official_match_confirmations
    where match_id = p_match_id and player_id = p_player_id;
    if not found then
        raise exception 'This account did not confirm the match result.';
    end if;

    select value into v_entry
    from jsonb_array_elements(v_match.result->'entries') value
    where (value->>'actor_id')::integer = v_confirmation.actor_id;
    if v_entry is null then
        raise exception 'The confirmed actor is missing from the result.';
    end if;

    select id into v_season_id
    from public.game_seasons
    where active = true and now() >= starts_at and now() < ends_at
    limit 1;
    if v_season_id is null then
        raise exception 'No active One Gun season is configured.';
    end if;

    v_placement := greatest((v_entry->>'placement')::integer, 1);
    v_round_wins := greatest(coalesce((v_entry->>'round_wins')::integer, 0), 0);
    v_kills := greatest(coalesce((v_entry->>'kills')::integer, 0), 0);
    v_deaths := greatest(coalesce((v_entry->>'deaths')::integer, 0), 0);
    v_disarms := greatest(coalesce((v_entry->>'disarms')::integer, 0), 0);
    v_eligible := coalesce((v_entry->>'activity_eligible')::boolean, false)
        and coalesce((v_entry->>'rounds_participated')::integer, 0) >= 2;

    insert into public.player_progression (player_id)
    values (p_player_id) on conflict (player_id) do nothing;
    insert into public.player_season_progress (player_id, season_id)
    values (p_player_id, v_season_id) on conflict (player_id, season_id) do nothing;
    insert into public.player_currency (player_id, gun_tokens)
    values (p_player_id, 0) on conflict (player_id) do nothing;

    if not v_eligible then
        v_breakdown := jsonb_build_object(
            'state', 'ineligible',
            'reason', 'Active full-match participation requirement was not met.',
            'xp_breakdown', '{}'::jsonb,
            'token_breakdown', '{}'::jsonb,
            'level_road_tokens', 0,
            'unlocks', '[]'::jsonb
        );
        insert into public.match_rewards (
            match_id, player_id, season_id, actor_id, mode, map_id,
            placement, round_wins, kills, deaths, disarms,
            xp_delta, gun_tokens_delta, trophy_delta, eligible, breakdown
        ) values (
            p_match_id, p_player_id, v_season_id, v_confirmation.actor_id,
            v_match.mode, v_match.map_id, v_placement, v_round_wins,
            v_kills, v_deaths, v_disarms, 0, 0, 0, false, v_breakdown
        );
        return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
    end if;

    v_xp_participation := 50;
    v_xp_rounds := v_round_wins * 25;
    v_xp_placement := case v_placement when 1 then 50 when 2 then 30 when 3 then 15 else 0 end;
    v_xp_kills := least(v_kills, 10) * 3;
    v_xp_disarms := least(v_disarms, 6) * 4;
    v_xp_total := v_xp_participation + v_xp_rounds + v_xp_placement
        + v_xp_kills + v_xp_disarms;

    v_token_participation := 5;
    v_token_rounds := v_round_wins * 6;
    v_token_placement := case
        when v_placement = 1 then 15
        when v_placement = 2 then 8
        when v_placement = 3 and v_match.expected_players >= 4 then 5
        else 0 end;
    v_token_kills := least(v_kills, 5) * 2;
    v_token_disarms := least(v_disarms, 4) * 3;
    v_match_tokens := v_token_participation + v_token_rounds
        + v_token_placement + v_token_kills + v_token_disarms;
    v_trophy := case when v_placement = 1 then 1 else 0 end;

    select season_level, xp_into_level, trophies
    into v_old_level, v_season_xp, v_old_trophies
    from public.player_season_progress
    where player_id = p_player_id and season_id = v_season_id
    for update;

    v_new_level := v_old_level;
    v_season_xp := v_season_xp + v_xp_total;
    while v_season_xp >= public.one_gun_xp_required(v_new_level) loop
        v_season_xp := v_season_xp - public.one_gun_xp_required(v_new_level);
        v_new_level := v_new_level + 1;
    end loop;
    v_new_trophies := v_old_trophies + v_trophy;

    update public.player_season_progress
    set season_level = v_new_level,
        xp_into_level = v_season_xp,
        total_xp = total_xp + v_xp_total,
        trophies = v_new_trophies,
        official_matches = official_matches + 1,
        classic_wins = classic_wins + case when v_placement = 1 then 1 else 0 end,
        round_wins = round_wins + v_round_wins,
        kills = kills + v_kills,
        deaths = deaths + v_deaths,
        disarms = disarms + v_disarms,
        updated_at = now()
    where player_id = p_player_id and season_id = v_season_id;

    select career_levels_earned, career_xp_into_level
    into v_career_levels, v_career_xp
    from public.player_progression
    where player_id = p_player_id
    for update;
    v_career_xp := v_career_xp + v_xp_total;
    while v_career_xp >= public.one_gun_xp_required(v_career_levels + 1) loop
        v_career_xp := v_career_xp - public.one_gun_xp_required(v_career_levels + 1);
        v_career_levels := v_career_levels + 1;
    end loop;
    update public.player_progression
    set career_levels_earned = v_career_levels,
        career_xp_into_level = v_career_xp,
        updated_at = now()
    where player_id = p_player_id;

    insert into public.player_mode_stats (
        player_id, mode, matches, wins, best_finish,
        round_wins, kills, deaths, disarms
    ) values (
        p_player_id, 'one_gun', 1,
        case when v_placement = 1 then 1 else 0 end,
        v_placement, v_round_wins, v_kills, v_deaths, v_disarms
    ) on conflict (player_id, mode) do update set
        matches = public.player_mode_stats.matches + 1,
        wins = public.player_mode_stats.wins + case when v_placement = 1 then 1 else 0 end,
        best_finish = least(coalesce(public.player_mode_stats.best_finish, v_placement), v_placement),
        round_wins = public.player_mode_stats.round_wins + v_round_wins,
        kills = public.player_mode_stats.kills + v_kills,
        deaths = public.player_mode_stats.deaths + v_deaths,
        disarms = public.player_mode_stats.disarms + v_disarms,
        updated_at = now();

    v_level_rewards := public.one_gun_grant_due_rewards(
        p_player_id, v_season_id, 'level', v_old_level, v_new_level
    );
    v_trophy_rewards := public.one_gun_grant_due_rewards(
        p_player_id, v_season_id, 'trophy', v_old_trophies, v_new_trophies
    );
    v_level_bonus := coalesce((v_level_rewards->>'gun_tokens')::integer, 0)
        + coalesce((v_trophy_rewards->>'gun_tokens')::integer, 0);
    v_unlocks := coalesce(v_level_rewards->'unlocks', '[]'::jsonb)
        || coalesce(v_trophy_rewards->'unlocks', '[]'::jsonb);
    v_total_tokens := v_match_tokens + v_level_bonus;

    update public.player_currency
    set gun_tokens = gun_tokens + v_total_tokens,
        updated_at = now()
    where player_id = p_player_id
    returning gun_tokens into v_balance;

    if v_total_tokens <> 0 then
        insert into public.wallet_ledger (
            player_id, match_id, amount, reason, balance_after
        ) values (
            p_player_id, p_match_id, v_total_tokens,
            'official_classic_match', v_balance
        );
    end if;

    v_breakdown := jsonb_build_object(
        'xp_breakdown', jsonb_build_object(
            'participation', v_xp_participation,
            'round_wins', v_xp_rounds,
            'placement', v_xp_placement,
            'eliminations', v_xp_kills,
            'disarms', v_xp_disarms
        ),
        'token_breakdown', jsonb_build_object(
            'participation', v_token_participation,
            'round_wins', v_token_rounds,
            'placement', v_token_placement,
            'eliminations', v_token_kills,
            'disarms', v_token_disarms
        ),
        'level_road_tokens', v_level_bonus,
        'unlocks', v_unlocks,
        'new_season_level', v_new_level,
        'new_season_xp', v_season_xp,
        'next_level_xp', public.one_gun_xp_required(v_new_level),
        'new_season_trophies', v_new_trophies,
        'new_gun_token_balance', v_balance,
        'new_lifetime_prestige', v_career_levels / 100,
        'new_lifetime_level', (v_career_levels % 100) + 1
    );

    insert into public.match_rewards (
        match_id, player_id, season_id, actor_id, mode, map_id,
        placement, round_wins, kills, deaths, disarms,
        xp_delta, gun_tokens_delta, trophy_delta, eligible, breakdown
    ) values (
        p_match_id, p_player_id, v_season_id, v_confirmation.actor_id,
        v_match.mode, v_match.map_id, v_placement, v_round_wins,
        v_kills, v_deaths, v_disarms, v_xp_total, v_total_tokens,
        v_trophy, true, v_breakdown
    );

    return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
end;
$$;

-- -------------------------------------------------------------------------
-- Authenticated client RPCs.
-- -------------------------------------------------------------------------

create or replace function public.confirm_official_beta_match(
    p_match_id text,
    p_actor_id integer,
    p_claim_secret text,
    p_result jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_player_id uuid := auth.uid();
    v_entry jsonb;
    v_expected integer;
    v_hash text;
    v_existing public.official_matches%rowtype;
    v_confirmation public.official_match_confirmations%rowtype;
    v_confirmations integer;
    v_required integer;
    v_status text;
    v_confirmed record;
    v_receipt jsonb;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if p_match_id !~ '^[0-9a-f]{32}$' then
        raise exception 'Invalid match receipt ID.';
    end if;
    if p_claim_secret !~ '^[0-9a-f]{48}$' then
        raise exception 'Invalid private reward claim.';
    end if;
    if coalesce((p_result->>'official')::boolean, false) is not true
       or p_result->>'mode' <> 'one_gun'
       or p_result->>'ruleset_id' <> 'classic_beta_v1'
       or p_result->>'match_id' <> p_match_id then
        raise exception 'This result is not an Official Classic Beta match.';
    end if;
    if jsonb_typeof(p_result->'entries') <> 'array' then
        raise exception 'Match result entries are missing.';
    end if;

    v_expected := coalesce((p_result->>'expected_humans')::integer, 0);
    if v_expected < 3 or v_expected > 10
       or jsonb_array_length(p_result->'entries') <> v_expected then
        raise exception 'Official matches require three to ten human results.';
    end if;
    if exists (
        select 1 from jsonb_array_elements(p_result->'entries') value
        where coalesce((value->>'is_bot')::boolean, false)
           or coalesce((value->>'placement')::integer, 0) not between 1 and v_expected
           or coalesce((value->>'round_wins')::integer, -1) not between 0 and 10
           or coalesce((value->>'kills')::integer, -1) not between 0 and 200
           or coalesce((value->>'deaths')::integer, -1) not between 0 and 200
           or coalesce((value->>'disarms')::integer, -1) not between 0 and 200
           or coalesce(value->>'reward_claim_hash', '') !~ '^[0-9a-f]{64}$'
    ) then
        raise exception 'The Official match result contains invalid player data.';
    end if;
    if (
        select count(distinct (value->>'placement')::integer)
        from jsonb_array_elements(p_result->'entries') value
    ) <> v_expected then
        raise exception 'Official match placements must be unique.';
    end if;

    select value into v_entry
    from jsonb_array_elements(p_result->'entries') value
    where (value->>'actor_id')::integer = p_actor_id;
    if v_entry is null then
        raise exception 'Your actor is not present in this result.';
    end if;
    if lower(v_entry->>'reward_claim_hash') <>
       encode(extensions.digest(p_claim_secret, 'sha256'), 'hex') then
        raise exception 'This account cannot claim that actor result.';
    end if;

    v_hash := encode(extensions.digest(p_result::text, 'sha256'), 'hex');
    insert into public.official_matches (
        match_id, ruleset_id, mode, map_id, expected_players,
        result_hash, result, status
    ) values (
        p_match_id, 'classic_beta_v1', 'one_gun',
        left(coalesce(p_result->>'map_id', 'unknown'), 256),
        v_expected, v_hash, p_result, 'pending'
    ) on conflict (match_id) do nothing;

    select * into v_existing
    from public.official_matches
    where match_id = p_match_id
    for update;
    if v_existing.result_hash <> v_hash then
        raise exception 'A different result was already submitted for this match.';
    end if;
    if v_existing.created_at < now() - interval '30 minutes' then
        update public.official_matches
        set status = 'expired'
        where match_id = p_match_id and status = 'pending';
        raise exception 'The match reward confirmation window has expired.';
    end if;

    insert into public.official_match_confirmations (
        match_id, player_id, actor_id, result_hash
    ) values (
        p_match_id, v_player_id, p_actor_id, v_hash
    ) on conflict (match_id, player_id) do nothing;

    select * into v_confirmation
    from public.official_match_confirmations
    where match_id = p_match_id and player_id = v_player_id;
    if v_confirmation.actor_id <> p_actor_id
       or v_confirmation.result_hash <> v_hash then
        raise exception 'This account already confirmed a different actor or result.';
    end if;

    select count(*) into v_confirmations
    from public.official_match_confirmations
    where match_id = p_match_id and result_hash = v_hash;
    v_required := floor(v_expected / 2.0)::integer + 1;

    if v_existing.status = 'pending' and v_confirmations >= v_required then
        update public.official_matches
        set status = 'settled', settled_at = now()
        where match_id = p_match_id and status = 'pending';
        for v_confirmed in
            select player_id
            from public.official_match_confirmations
            where match_id = p_match_id and result_hash = v_hash
        loop
            perform public.one_gun_award_confirmed_player(
                p_match_id, v_confirmed.player_id
            );
        end loop;
    end if;

    select status into v_status
    from public.official_matches where match_id = p_match_id;
    if v_status = 'settled' then
        v_receipt := public.one_gun_award_confirmed_player(
            p_match_id, v_player_id
        );
        return v_receipt;
    end if;
    return jsonb_build_object(
        'state', 'pending',
        'persisted', false,
        'match_id', p_match_id,
        'confirmations', v_confirmations,
        'required_confirmations', v_required
    );
end;
$$;

create or replace function public.get_official_match_reward(p_match_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_status text;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if not exists (
        select 1 from public.official_match_confirmations
        where match_id = p_match_id and player_id = v_player_id
    ) then
        raise exception 'This account did not confirm that match.';
    end if;
    if exists (
        select 1 from public.match_rewards
        where match_id = p_match_id and player_id = v_player_id
    ) then
        return public.one_gun_reward_receipt_json(p_match_id, v_player_id);
    end if;
    select status into v_status
    from public.official_matches where match_id = p_match_id;
    return jsonb_build_object(
        'state', coalesce(v_status, 'pending'),
        'persisted', false,
        'match_id', p_match_id
    );
end;
$$;

create or replace function public.set_shop_favorite(
    p_item_id text, p_favorite boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if not exists (select 1 from public.shop_items where id = p_item_id and active = true) then
        raise exception 'That item does not exist.';
    end if;
    if p_favorite then
        insert into public.player_favorites (player_id, item_id)
        values (v_player_id, p_item_id) on conflict do nothing;
    else
        delete from public.player_favorites
        where player_id = v_player_id and item_id = p_item_id;
    end if;
    return jsonb_build_object('ok', true, 'item_id', p_item_id, 'favorite', p_favorite);
end;
$$;

create or replace function public.equip_cosmetic(p_slot text, p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_item_type text;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if p_slot not in (
        'character_skin', 'hat', 'shirt', 'pants', 'shoes', 'accessory',
        'gun_skin', 'melee_skin', 'emote', 'round_victory_move', 'profile_badge'
    ) then
        raise exception 'Invalid loadout slot.';
    end if;
    if not exists (
        select 1 from public.player_inventory
        where player_id = v_player_id and item_id = p_item_id
    ) then
        raise exception 'Item is not owned.';
    end if;
    select item_type into v_item_type
    from public.shop_items where id = p_item_id and active = true;
    if not found or v_item_type <> p_slot then
        raise exception 'Item type does not match the loadout slot.';
    end if;

    insert into public.player_loadouts (player_id)
    values (v_player_id) on conflict (player_id) do nothing;
    execute format(
        'update public.player_loadouts set %I = $1, updated_at = now() where player_id = $2',
        p_slot
    ) using p_item_id, v_player_id;
    insert into public.player_item_usage (player_id, item_id, equip_count, last_equipped_at)
    values (v_player_id, p_item_id, 1, now())
    on conflict (player_id, item_id) do update set
        equip_count = public.player_item_usage.equip_count + 1,
        last_equipped_at = now();
    return jsonb_build_object('ok', true, 'slot', p_slot, 'item_id', p_item_id);
end;
$$;

create or replace function public.equip_ceremony_theme(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if not exists (
        select 1 from public.shop_items item
        join public.player_inventory inventory
          on inventory.item_id = item.id and inventory.player_id = v_player_id
        where item.id = p_item_id and item.active = true
          and item.item_type = 'ceremony_theme'
    ) then
        raise exception 'You do not own this Winners Circle theme.';
    end if;
    insert into public.player_loadouts (player_id, ceremony_theme)
    values (v_player_id, p_item_id)
    on conflict (player_id) do update set
        ceremony_theme = excluded.ceremony_theme, updated_at = now();
    insert into public.player_item_usage (player_id, item_id, equip_count, last_equipped_at)
    values (v_player_id, p_item_id, 1, now())
    on conflict (player_id, item_id) do update set
        equip_count = public.player_item_usage.equip_count + 1,
        last_equipped_at = now();
    return jsonb_build_object('ok', true, 'slot', 'ceremony_theme', 'item_id', p_item_id);
end;
$$;

create or replace function public.equip_outfit(p_bundle_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_hat text;
    v_shirt text;
    v_pants text;
    v_shoes text;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if not exists (
        select 1 from public.player_inventory inventory
        join public.shop_items item on item.id = inventory.item_id
        where inventory.player_id = v_player_id
          and inventory.item_id = p_bundle_id
          and item.item_type = 'outfit_bundle' and item.active = true
    ) then
        raise exception 'You do not own this outfit.';
    end if;
    if exists (
        select 1 from public.shop_bundle_items bundle
        where bundle.bundle_id = p_bundle_id
          and not exists (
              select 1 from public.player_inventory inventory
              where inventory.player_id = v_player_id
                and inventory.item_id = bundle.item_id
          )
    ) then
        raise exception 'One or more outfit pieces are missing.';
    end if;

    select max(bundle.item_id) filter (where item.item_type = 'hat'),
           max(bundle.item_id) filter (where item.item_type = 'shirt'),
           max(bundle.item_id) filter (where item.item_type = 'pants'),
           max(bundle.item_id) filter (where item.item_type = 'shoes')
    into v_hat, v_shirt, v_pants, v_shoes
    from public.shop_bundle_items bundle
    join public.shop_items item on item.id = bundle.item_id
    where bundle.bundle_id = p_bundle_id;

    insert into public.player_loadouts (player_id)
    values (v_player_id) on conflict (player_id) do nothing;
    update public.player_loadouts
    set hat = coalesce(v_hat, hat),
        shirt = coalesce(v_shirt, shirt),
        pants = coalesce(v_pants, pants),
        shoes = coalesce(v_shoes, shoes),
        updated_at = now()
    where player_id = v_player_id;
    insert into public.player_item_usage (player_id, item_id, equip_count, last_equipped_at)
    values (v_player_id, p_bundle_id, 1, now())
    on conflict (player_id, item_id) do update set
        equip_count = public.player_item_usage.equip_count + 1,
        last_equipped_at = now();
    return jsonb_build_object(
        'ok', true, 'bundle_id', p_bundle_id,
        'hat', v_hat, 'shirt', v_shirt, 'pants', v_pants, 'shoes', v_shoes
    );
end;
$$;

create or replace function public.purchase_shop_item(p_item_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_item public.shop_items%rowtype;
    v_balance bigint;
    v_original_price bigint;
    v_price bigint;
    v_discount bigint;
    v_is_bundle boolean;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    select * into v_item from public.shop_items where id = p_item_id;
    if not found or not v_item.active or not v_item.purchasable or not v_item.shop_visible then
        raise exception 'This item is not currently purchasable.';
    end if;
    if v_item.rotation_starts_at is not null and now() < v_item.rotation_starts_at
       or v_item.rotation_ends_at is not null and now() >= v_item.rotation_ends_at then
        raise exception 'This item is not in the current Prize Counter rotation.';
    end if;
    if exists (
        select 1 from public.player_inventory
        where player_id = v_player_id and item_id = p_item_id
    ) then
        raise exception 'Item is already owned.';
    end if;

    v_is_bundle := v_item.item_type = 'outfit_bundle';
    if v_is_bundle then
        select coalesce(sum(component.price), 0)
        into v_original_price
        from public.shop_bundle_items bundle
        join public.shop_items component on component.id = bundle.item_id
        where bundle.bundle_id = p_item_id
          and component.active = true
          and not exists (
              select 1 from public.player_inventory inventory
              where inventory.player_id = v_player_id
                and inventory.item_id = bundle.item_id
          );
        if v_original_price <= 0 then
            raise exception 'Every piece in this outfit is already owned.';
        end if;
        v_price := ceil(v_original_price * 0.85)::bigint;
    else
        v_original_price := v_item.price;
        v_price := v_item.price;
    end if;
    v_discount := v_original_price - v_price;

    select gun_tokens into v_balance
    from public.player_currency
    where player_id = v_player_id
    for update;
    if v_balance is null then
        raise exception 'Player currency record is missing.';
    end if;
    if v_balance < v_price then
        raise exception 'Not enough Gun Tokens.';
    end if;

    update public.player_currency
    set gun_tokens = gun_tokens - v_price, updated_at = now()
    where player_id = v_player_id
    returning gun_tokens into v_balance;
    perform public.one_gun_grant_inventory_item(v_player_id, p_item_id, 'shop');
    update public.shop_items
    set purchase_count = purchase_count + 1
    where id = p_item_id;
    insert into public.purchase_ledger (
        player_id, item_id, original_price, price_paid, discount_amount
    ) values (
        v_player_id, p_item_id, v_original_price, v_price, v_discount
    );
    insert into public.wallet_ledger (
        player_id, amount, reason, balance_after
    ) values (
        v_player_id, -v_price, 'shop_purchase:' || p_item_id, v_balance
    );
    return jsonb_build_object(
        'ok', true,
        'item_id', p_item_id,
        'price_paid', v_price,
        'original_price', v_original_price,
        'discount_amount', v_discount,
        'remaining_balance', v_balance
    );
end;
$$;

create or replace function public.get_player_progression()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_season public.game_seasons%rowtype;
    v_progress public.player_season_progress%rowtype;
    v_career public.player_progression%rowtype;
    v_stats jsonb := '[]'::jsonb;
    v_history jsonb := '[]'::jsonb;
    v_legacy jsonb := '[]'::jsonb;
    v_level_road jsonb := '[]'::jsonb;
    v_trophy_road jsonb := '[]'::jsonb;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    select * into v_season
    from public.game_seasons
    where active = true and now() >= starts_at and now() < ends_at
    limit 1;
    if v_season.id is null then
        raise exception 'No active One Gun season is configured.';
    end if;

    insert into public.season_archives (
        player_id, season_id, season_name, final_level, final_xp,
        trophies, classic_wins, official_matches, road_summary
    )
    select progress.player_id, progress.season_id, season.display_name,
           progress.season_level, progress.total_xp, progress.trophies,
           progress.classic_wins, progress.official_matches,
           jsonb_build_object(
               'claimed', (
                   select count(*) from public.player_reward_unlocks unlock
                   where unlock.player_id = progress.player_id
                     and unlock.season_id = progress.season_id
               )
           )
    from public.player_season_progress progress
    join public.game_seasons season on season.id = progress.season_id
    where progress.player_id = v_player_id
      and progress.season_id <> v_season.id
    on conflict (player_id, season_id) do nothing;

    insert into public.player_progression (player_id)
    values (v_player_id) on conflict (player_id) do nothing;
    insert into public.player_season_progress (player_id, season_id)
    values (v_player_id, v_season.id) on conflict (player_id, season_id) do nothing;

    select * into v_progress from public.player_season_progress
    where player_id = v_player_id and season_id = v_season.id;
    select * into v_career from public.player_progression
    where player_id = v_player_id;

    select coalesce(jsonb_agg(to_jsonb(stats) - 'player_id' order by stats.mode), '[]'::jsonb)
    into v_stats
    from public.player_mode_stats stats
    where stats.player_id = v_player_id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'match_id', reward.match_id,
        'mode', reward.mode,
        'map_id', reward.map_id,
        'placement', reward.placement,
        'round_wins', reward.round_wins,
        'kills', reward.kills,
        'deaths', reward.deaths,
        'disarms', reward.disarms,
        'xp_delta', reward.xp_delta,
        'gun_tokens_delta', reward.gun_tokens_delta,
        'trophy_delta', reward.trophy_delta,
        'eligible', reward.eligible,
        'created_at', reward.created_at
    ) order by reward.created_at desc), '[]'::jsonb)
    into v_history
    from (
        select * from public.match_rewards
        where player_id = v_player_id
        order by created_at desc limit 20
    ) reward;

    select coalesce(jsonb_agg(to_jsonb(archive) - 'player_id' order by archive.archived_at desc), '[]'::jsonb)
    into v_legacy
    from public.season_archives archive
    where archive.player_id = v_player_id;

    select coalesce(jsonb_agg(jsonb_build_object(
        'threshold', milestone.threshold,
        'display_name', milestone.display_name,
        'gun_tokens', milestone.gun_tokens,
        'item_id', milestone.item_id,
        'rarity', milestone.rarity,
        'claimed', unlock.threshold is not null
    ) order by milestone.threshold), '[]'::jsonb)
    into v_level_road
    from public.season_reward_milestones milestone
    left join public.player_reward_unlocks unlock
      on unlock.player_id = v_player_id
     and unlock.season_id = milestone.season_id
     and unlock.road_type = milestone.road_type
     and unlock.threshold = milestone.threshold
    where milestone.season_id = v_season.id and milestone.road_type = 'level';

    select coalesce(jsonb_agg(jsonb_build_object(
        'threshold', milestone.threshold,
        'display_name', milestone.display_name,
        'gun_tokens', milestone.gun_tokens,
        'item_id', milestone.item_id,
        'rarity', milestone.rarity,
        'claimed', unlock.threshold is not null
    ) order by milestone.threshold), '[]'::jsonb)
    into v_trophy_road
    from public.season_reward_milestones milestone
    left join public.player_reward_unlocks unlock
      on unlock.player_id = v_player_id
     and unlock.season_id = milestone.season_id
     and unlock.road_type = milestone.road_type
     and unlock.threshold = milestone.threshold
    where milestone.season_id = v_season.id and milestone.road_type = 'trophy';

    return jsonb_build_object(
        'season', jsonb_build_object(
            'id', v_season.id,
            'display_name', v_season.display_name,
            'starts_at', v_season.starts_at,
            'ends_at', v_season.ends_at,
            'ruleset_id', v_season.ruleset_id
        ),
        'progress', jsonb_build_object(
            'season_level', v_progress.season_level,
            'xp_into_level', v_progress.xp_into_level,
            'next_level_xp', public.one_gun_xp_required(v_progress.season_level),
            'total_xp', v_progress.total_xp,
            'trophies', v_progress.trophies,
            'official_matches', v_progress.official_matches,
            'classic_wins', v_progress.classic_wins,
            'round_wins', v_progress.round_wins,
            'kills', v_progress.kills,
            'deaths', v_progress.deaths,
            'disarms', v_progress.disarms
        ),
        'career', jsonb_build_object(
            'levels_earned', v_career.career_levels_earned,
            'xp_into_level', v_career.career_xp_into_level,
            'next_level_xp', public.one_gun_xp_required(v_career.career_levels_earned + 1),
            'lifetime_prestige', v_career.career_levels_earned / 100,
            'lifetime_level', (v_career.career_levels_earned % 100) + 1
        ),
        'mode_stats', v_stats,
        'match_history', v_history,
        'legacy', v_legacy,
        'level_road', v_level_road,
        'trophy_road', v_trophy_road
    );
end;
$$;

-- Extend account creation so new profiles immediately have progression rows.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_season_id text;
begin
    insert into public.profiles (id, username)
    values (new.id, null) on conflict (id) do nothing;
    insert into public.player_currency (player_id, gun_tokens)
    values (new.id, 0) on conflict (player_id) do nothing;
    insert into public.player_loadouts (player_id)
    values (new.id) on conflict (player_id) do nothing;
    insert into public.player_progression (player_id)
    values (new.id) on conflict (player_id) do nothing;
    select id into v_season_id from public.game_seasons where active = true limit 1;
    if v_season_id is not null then
        insert into public.player_season_progress (player_id, season_id)
        values (new.id, v_season_id) on conflict (player_id, season_id) do nothing;
    end if;
    return new;
end;
$$;

-- Backfill progression roots for existing accounts without changing balances.
insert into public.player_progression (player_id)
select id from public.profiles on conflict (player_id) do nothing;
insert into public.player_season_progress (player_id, season_id)
select profile.id, 'beta-season' from public.profiles profile
on conflict (player_id, season_id) do nothing;

-- -------------------------------------------------------------------------
-- RLS and grants.
-- -------------------------------------------------------------------------

alter table public.shop_bundle_items enable row level security;
alter table public.player_favorites enable row level security;
alter table public.player_item_usage enable row level security;
alter table public.purchase_ledger enable row level security;
alter table public.game_seasons enable row level security;
alter table public.player_progression enable row level security;
alter table public.player_season_progress enable row level security;
alter table public.player_mode_stats enable row level security;
alter table public.season_archives enable row level security;
alter table public.season_reward_milestones enable row level security;
alter table public.player_reward_unlocks enable row level security;
alter table public.official_matches enable row level security;
alter table public.official_match_confirmations enable row level security;
alter table public.match_rewards enable row level security;
alter table public.wallet_ledger enable row level security;

drop policy if exists "Public can read bundle definitions" on public.shop_bundle_items;
create policy "Public can read bundle definitions"
    on public.shop_bundle_items for select to anon, authenticated using (true);
drop policy if exists "Players can read own favorites" on public.player_favorites;
create policy "Players can read own favorites"
    on public.player_favorites for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own item usage" on public.player_item_usage;
create policy "Players can read own item usage"
    on public.player_item_usage for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own purchases" on public.purchase_ledger;
create policy "Players can read own purchases"
    on public.purchase_ledger for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Public can read seasons" on public.game_seasons;
create policy "Public can read seasons"
    on public.game_seasons for select to anon, authenticated using (true);
drop policy if exists "Players can read own career progression" on public.player_progression;
create policy "Players can read own career progression"
    on public.player_progression for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own season progression" on public.player_season_progress;
create policy "Players can read own season progression"
    on public.player_season_progress for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own mode stats" on public.player_mode_stats;
create policy "Players can read own mode stats"
    on public.player_mode_stats for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own season archives" on public.season_archives;
create policy "Players can read own season archives"
    on public.season_archives for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Public can read season roads" on public.season_reward_milestones;
create policy "Public can read season roads"
    on public.season_reward_milestones for select to anon, authenticated using (true);
drop policy if exists "Players can read own reward unlocks" on public.player_reward_unlocks;
create policy "Players can read own reward unlocks"
    on public.player_reward_unlocks for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own match confirmations" on public.official_match_confirmations;
create policy "Players can read own match confirmations"
    on public.official_match_confirmations for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own match rewards" on public.match_rewards;
create policy "Players can read own match rewards"
    on public.match_rewards for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can read own wallet ledger" on public.wallet_ledger;
create policy "Players can read own wallet ledger"
    on public.wallet_ledger for select to authenticated
    using (auth.uid() = player_id);
drop policy if exists "Players can view owned hidden shop items" on public.shop_items;
create policy "Players can view owned hidden shop items"
    on public.shop_items for select to authenticated
    using (exists (
        select 1 from public.player_inventory inventory
        where inventory.player_id = auth.uid()
          and inventory.item_id = shop_items.id
    ));

grant select on public.shop_bundle_items to anon, authenticated;
grant select on public.game_seasons to anon, authenticated;
grant select on public.season_reward_milestones to anon, authenticated;
grant select on public.player_favorites, public.player_item_usage,
    public.purchase_ledger, public.player_progression,
    public.player_season_progress, public.player_mode_stats,
    public.season_archives, public.player_reward_unlocks,
    public.official_match_confirmations, public.match_rewards,
    public.wallet_ledger to authenticated;

revoke all on function public.one_gun_xp_required(integer) from public, anon, authenticated;
revoke all on function public.one_gun_grant_inventory_item(uuid, text, text) from public, anon, authenticated;
revoke all on function public.one_gun_grant_due_rewards(uuid, text, text, integer, integer) from public, anon, authenticated;
revoke all on function public.one_gun_reward_receipt_json(text, uuid) from public, anon, authenticated;
revoke all on function public.one_gun_award_confirmed_player(text, uuid) from public, anon, authenticated;

revoke all on function public.confirm_official_beta_match(text, integer, text, jsonb) from public, anon;
revoke all on function public.get_official_match_reward(text) from public, anon;
revoke all on function public.set_shop_favorite(text, boolean) from public, anon;
revoke all on function public.equip_outfit(text) from public, anon;
revoke all on function public.equip_cosmetic(text, text) from public, anon;
revoke all on function public.equip_ceremony_theme(text) from public, anon;
revoke all on function public.purchase_shop_item(text) from public, anon;
revoke all on function public.get_player_progression() from public, anon;

grant execute on function public.confirm_official_beta_match(text, integer, text, jsonb) to authenticated;
grant execute on function public.get_official_match_reward(text) to authenticated;
grant execute on function public.set_shop_favorite(text, boolean) to authenticated;
grant execute on function public.equip_outfit(text) to authenticated;
grant execute on function public.equip_cosmetic(text, text) to authenticated;
grant execute on function public.equip_ceremony_theme(text) to authenticated;
grant execute on function public.purchase_shop_item(text) to authenticated;
grant execute on function public.get_player_progression() to authenticated;

commit;

notify pgrst, 'reload schema';
