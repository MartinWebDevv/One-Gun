\set ON_ERROR_STOP on

begin;

do $$
declare
    v_count integer;
begin
    if not exists (
        select 1 from public.season_reward_milestones
        where season_id = 'beta-season' and road_type = 'level'
          and threshold = 10 and display_name = 'Rice Hat'
          and item_id = 'beta_s1_level_30_hat'
    ) then
        raise exception 'Rice Hat is not the Beta Level 10 reward';
    end if;
    if not exists (
        select 1 from public.season_reward_milestones
        where season_id = 'beta-season' and road_type = 'trophy'
          and threshold = 5 and display_name = 'Pimp Hat'
          and item_id = 'beta_s1_ace_hat'
    ) then
        raise exception 'Pimp Hat is not the Beta Trophy 5 reward';
    end if;
    if exists (
        select 1 from public.season_reward_milestones
        where season_id = 'beta-season'
          and ((road_type = 'level' and threshold = 30)
            or (road_type = 'trophy' and threshold = 20))
    ) then
        raise exception 'Retired Level 30 or Trophy 20 milestone still exists';
    end if;

    select count(*) into v_count
    from public.shop_items
    where id in (
        'hat_chef', 'hat_cowboy_classic', 'hat_cowboy_wide', 'hat_crown',
        'hat_fedora_black', 'hat_fedora_white', 'hat_straw_adventurer',
        'hat_top', 'hat_witch', 'hat_yellow_point'
    ) and item_type = 'hat' and category = 'character'
      and subcategory = 'hats' and active and purchasable and shop_visible
      and rotation_scope in ('daily', 'monthly');
    if v_count <> 10 then
        raise exception 'Expected ten live Prize Counter hats, found %', v_count;
    end if;

    select count(*) into v_count
    from public.shop_items
    where (id in ('hat_chef', 'hat_yellow_point') and price = 850)
       or (id in ('hat_cowboy_classic', 'hat_fedora_black',
                  'hat_straw_adventurer') and price = 1250)
       or (id in ('hat_cowboy_wide', 'hat_fedora_white', 'hat_top',
                  'hat_witch') and price = 1650)
       or (id = 'hat_crown' and price = 2200);
    if v_count <> 10 then
        raise exception 'Expected the rarity-stepped hat prices, found % matches',
            v_count;
    end if;

    if (select display_name from public.shop_items
        where id = 'beta_s1_level_30_hat') <> 'Rice Hat'
       or (select display_name from public.shop_items
        where id = 'beta_s1_ace_hat') <> 'Pimp Hat' then
        raise exception 'Stable reward IDs were not renamed to the requested hats';
    end if;

    if exists (
        select 1 from public.profiles
        where id = '10000000-0000-0000-0000-000000000001'
    ) then
        select count(*) into v_count
        from public.player_inventory
        where player_id = '10000000-0000-0000-0000-000000000001'
          and item_id in ('beta_s1_level_30_hat', 'beta_s1_ace_hat');
        if v_count <> 2 then
            raise exception 'Eligible fixture player did not receive both moved hats';
        end if;
        select count(*) into v_count
        from public.player_inventory
        where player_id = '10000000-0000-0000-0000-000000000001'
          and item_id in ('beta_s1_level_10_color', 'beta_s1_trophy_5_gun',
              'beta_s1_ace_outfit');
        if v_count <> 3 then
            raise exception 'Rebalance revoked a previously owned reward';
        end if;
        if not exists (
            select 1 from public.player_reward_unlocks
            where player_id = '10000000-0000-0000-0000-000000000001'
              and season_id = 'beta-season' and road_type = 'level'
              and threshold = 10 and item_id = 'beta_s1_level_30_hat'
        ) or not exists (
            select 1 from public.player_reward_unlocks
            where player_id = '10000000-0000-0000-0000-000000000001'
              and season_id = 'beta-season' and road_type = 'trophy'
              and threshold = 5 and item_id = 'beta_s1_ace_hat'
        ) then
            raise exception 'Moved milestone unlock ledger was not backfilled';
        end if;
    end if;
end;
$$;

rollback;

\echo HAT_CATALOG_REWARD_TESTS_OK
