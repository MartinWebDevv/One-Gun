\set ON_ERROR_STOP on

begin;

do $$
declare
    v_dance_count integer;
    v_distinct_names integer;
begin
    select count(*) into v_dance_count
    from public.shop_items
    where id like 'podium_%' or id like 'round_%';
    if v_dance_count <> 14 then
        raise exception 'Expected 14 stable shipped dance IDs, got %', v_dance_count;
    end if;
    if (select count(*) from public.shop_items
            where (id like 'podium_%' or id like 'round_%')
              and item_type = 'victory_dance'
              and category = 'victory'
              and subcategory = 'dances'
              and active and shop_visible and purchasable) <> 14 then
        raise exception 'All 14 shipped moves must be purchasable unified dances';
    end if;
    select count(distinct display_name) into v_distinct_names
    from public.shop_items
    where id like 'podium_%' or id like 'round_%';
    if v_distinct_names <> 14 then
        raise exception 'All 14 victory products must keep unique player-facing names';
    end if;
    if (select price from public.shop_items where id = 'round_birdie_boogie') <> 900
       or (select rarity from public.shop_items where id = 'podium_midnight_monster') <> 'legendary' then
        raise exception 'Victory dance pricing/rarity seed drifted';
    end if;
    if (select count(*) from public.shop_items
            where id in ('beta_s1_level_70_pose', 'beta_s1_trophy_10_pose')
              and item_type = 'emote' and subcategory = 'poses') <> 2 then
        raise exception 'Static podium rewards must remain in the separate Poses group';
    end if;
end;
$$;

insert into auth.users (id)
values ('20000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;
insert into public.profiles (id, username)
values ('20000000-0000-0000-0000-000000000001', 'MoveTester')
on conflict (id) do nothing;
insert into public.player_currency (player_id, gun_tokens)
values ('20000000-0000-0000-0000-000000000001', 10000)
on conflict (player_id) do update set gun_tokens = excluded.gun_tokens;
insert into public.player_loadouts (player_id)
values ('20000000-0000-0000-0000-000000000001')
on conflict (player_id) do nothing;

select set_config(
    'request.jwt.claim.sub',
    '20000000-0000-0000-0000-000000000001',
    true
);

do $$
begin
    if (select count(*) from public.player_inventory
            where player_id = '20000000-0000-0000-0000-000000000001'
              and item_id in (
                  'base_one_gun', 'base_arena_melee', 'hip_hop_dance',
                  'swing_dance', 'wc_theme_ceremony_march'
              )) <> 5 then
        raise exception 'New loadouts must receive all five permanent baseline items';
    end if;
end;
$$;

select public.purchase_shop_item('podium_fresh_footwork');
select public.purchase_shop_item('round_birdie_boogie');

-- Either stable dance ID must work in either celebration slot, including both
-- slots at the same time.
select public.equip_cosmetic('emote', 'podium_fresh_footwork');
select public.equip_cosmetic('round_victory_move', 'podium_fresh_footwork');

do $$
declare
    v_loadout public.player_loadouts%rowtype;
begin
    select * into v_loadout from public.player_loadouts
    where player_id = '20000000-0000-0000-0000-000000000001';
    if v_loadout.emote <> 'podium_fresh_footwork'
       or v_loadout.round_victory_move <> 'podium_fresh_footwork' then
        raise exception 'One owned dance did not equip to both independent slots';
    end if;
end;
$$;

select public.unequip_cosmetic('emote');
select public.unequip_cosmetic('round_victory_move');

do $$
declare
    v_loadout public.player_loadouts%rowtype;
begin
    select * into v_loadout from public.player_loadouts
    where player_id = '20000000-0000-0000-0000-000000000001';
    if v_loadout.emote is not null
       or v_loadout.round_victory_move <> 'hip_hop_dance' then
        raise exception 'Unequip did not restore idle podium and Hip Hop round defaults';
    end if;
end;
$$;

-- Outfit removal clears only pieces currently supplied by that outfit.
insert into public.player_inventory (player_id, item_id, source)
select '20000000-0000-0000-0000-000000000001', item_id, 'sql_test'
from (values
    ('beta_s1_ace_outfit'), ('beta_s1_ace_hat'), ('beta_s1_ace_shirt'),
    ('beta_s1_ace_pants'), ('beta_s1_ace_shoes')
) items(item_id)
on conflict (player_id, item_id) do nothing;
select public.equip_outfit('beta_s1_ace_outfit');
select public.unequip_outfit('beta_s1_ace_outfit');

do $$
declare
    v_loadout public.player_loadouts%rowtype;
begin
    select * into v_loadout from public.player_loadouts
    where player_id = '20000000-0000-0000-0000-000000000001';
    if v_loadout.hat is not null or v_loadout.shirt is not null
       or v_loadout.pants is not null or v_loadout.shoes is not null then
        raise exception 'Unequip outfit did not clear all still-matching bundle pieces';
    end if;
end;
$$;

select public.equip_cosmetic('emote', 'round_birdie_boogie');
select public.equip_cosmetic('round_victory_move', 'round_birdie_boogie');
select public.equip_outfit('beta_s1_ace_outfit');
update public.player_loadouts
set character_skin = 'beta_s1_level_10_color',
    accessory = 'beta_s1_trophy_50_relic',
    ceremony_theme = 'wc_theme_deep_orbit'
where player_id = '20000000-0000-0000-0000-000000000001';
select public.reset_cosmetic_loadout();

do $$
declare
    v_loadout public.player_loadouts%rowtype;
    v_tokens bigint;
begin
    select * into v_loadout from public.player_loadouts
    where player_id = '20000000-0000-0000-0000-000000000001';
    if v_loadout.character_skin <> 'beta_s1_level_10_color' then
        raise exception 'Reset changed the preserved character skin/color choice';
    end if;
    if v_loadout.hat is not null or v_loadout.shirt is not null
       or v_loadout.pants is not null or v_loadout.shoes is not null
       or v_loadout.accessory is not null or v_loadout.emote is not null
       or v_loadout.profile_badge is not null then
        raise exception 'Reset did not clear optional cosmetic slots';
    end if;
    if v_loadout.gun_skin <> 'base_one_gun'
       or v_loadout.melee_skin <> 'base_arena_melee'
       or v_loadout.round_victory_move <> 'hip_hop_dance'
       or v_loadout.ceremony_theme <> 'wc_theme_ceremony_march' then
        raise exception 'Reset did not restore the canonical baseline loadout';
    end if;
    select gun_tokens into v_tokens from public.player_currency
    where player_id = '20000000-0000-0000-0000-000000000001';
    if v_tokens <> 7400 then
        raise exception 'Expected 7400 tokens after 1700 + 900 purchases, got %', v_tokens;
    end if;
    if (select count(*) from public.player_inventory
            where player_id = '20000000-0000-0000-0000-000000000001'
              and item_id in ('podium_fresh_footwork', 'round_birdie_boogie')) <> 2 then
        raise exception 'Permanent purchased ownership was lost during loadout operations';
    end if;
end;
$$;

rollback;

\echo VICTORY_MOVE_CATALOG_TESTS_OK