-- One Gun: unified victory dances and safe Locker loadout controls.
-- Stable item IDs and permanent ownership are preserved during this migration.
-- The game client still uses only the publishable key plus the player's JWT.

begin;

-- Every shipped animated move can now be assigned independently to either the
-- Winners Circle podium slot or the round-win slot.
update public.shop_items
set item_type = 'victory_dance',
    category = 'victory',
    subcategory = 'dances'
where id in (
    'podium_backbeat_bounce',
    'podium_champion_canter',
    'podium_fresh_footwork',
    'podium_house_party_heat',
    'podium_serpent_flow',
    'podium_midnight_monster',
    'podium_victory_wave',
    'round_breakspin_finale',
    'round_floorwork_finish',
    'round_birdie_boogie',
    'round_arena_clapline',
    'round_soul_cyclone',
    'round_quickstep_shuffle',
    'round_victory_swing',
    'beta_s1_trophy_35_dance'
);

update public.shop_items
set category = 'victory', subcategory = 'poses'
where id in ('beta_s1_level_70_pose', 'beta_s1_trophy_10_pose');

-- Baseline choices are real owned catalog entries so the owned-only Locker can
-- show them without an INCLUDED or DEFAULT badge. They never enter rotations.
insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope, sort_order
) values
    (
        'base_one_gun', 'Original One Gun', 'gun_skin',
        'The original arena finish for the one and only gun.',
        0, 'standard', false, false, true, 'weapons', 'gun_skins',
        false, 'none', -40
    ),
    (
        'base_arena_melee', 'Original Melee Finish', 'melee_skin',
        'The original finish shared by the arena melee arsenal.',
        0, 'standard', false, false, true, 'weapons', 'melee_skins',
        false, 'none', -39
    ),
    (
        'hip_hop_dance', 'Hip Hop', 'victory_dance',
        'The original One Gun round-win dance.',
        0, 'standard', false, false, true, 'victory', 'dances',
        false, 'none', -38
    ),
    (
        'swing_dance', 'Swing Dance', 'victory_dance',
        'A classic One Gun celebration available from the start.',
        0, 'standard', false, false, true, 'victory', 'dances',
        false, 'none', -37
    )
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = excluded.item_type,
    description = excluded.description,
    price = 0,
    rarity = excluded.rarity,
    purchasable = false,
    shop_visible = false,
    active = true,
    category = excluded.category,
    subcategory = excluded.subcategory,
    featured = false,
    rotation_scope = 'none',
    sort_order = excluded.sort_order;

-- Explicit defaults let the Locker accurately show which baseline item is
-- active. Podium emote remains null, which intentionally means the idle pose.
alter table public.player_loadouts
    alter column gun_skin set default 'base_one_gun',
    alter column melee_skin set default 'base_arena_melee',
    alter column round_victory_move set default 'hip_hop_dance';

update public.player_loadouts
set gun_skin = coalesce(gun_skin, 'base_one_gun'),
    melee_skin = coalesce(melee_skin, 'base_arena_melee'),
    round_victory_move = coalesce(round_victory_move, 'hip_hop_dance'),
    updated_at = now();

insert into public.player_inventory (player_id, item_id, obtained_at, source)
select loadout.player_id, defaults.item_id, now(), 'base_game'
from public.player_loadouts loadout
cross join (
    values
        ('base_one_gun'),
        ('base_arena_melee'),
        ('hip_hop_dance'),
        ('swing_dance'),
        ('wc_theme_ceremony_march')
) as defaults(item_id)
on conflict (player_id, item_id) do nothing;

-- Preserve the existing trigger/function name so old deployments and clients
-- remain compatible while expanding it to every permanent baseline choice.
create or replace function public.grant_default_ceremony_theme()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.player_inventory (player_id, item_id, obtained_at, source)
    select new.player_id, defaults.item_id, now(), 'base_game'
    from (
        values
            ('base_one_gun'),
            ('base_arena_melee'),
            ('hip_hop_dance'),
            ('swing_dance'),
            ('wc_theme_ceremony_march')
    ) as defaults(item_id)
    on conflict (player_id, item_id) do nothing;
    return new;
end;
$$;

revoke all on function public.grant_default_ceremony_theme()
    from public, anon, authenticated;

-- A victory_dance is intentionally valid in both celebration columns. Legacy
-- item types remain accepted in their original slot during mixed-version tests.
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
    from public.shop_items
    where id = p_item_id and active = true;

    if not found or not (
        v_item_type = p_slot
        or (v_item_type = 'victory_dance'
            and p_slot in ('emote', 'round_victory_move'))
        or (v_item_type = 'emote' and p_slot = 'emote')
        or (v_item_type = 'round_victory_move'
            and p_slot = 'round_victory_move')
    ) then
        raise exception 'Item type does not match the loadout slot.';
    end if;

    insert into public.player_loadouts (player_id)
    values (v_player_id) on conflict (player_id) do nothing;

    execute format(
        'update public.player_loadouts set %I = $1, updated_at = now() where player_id = $2',
        p_slot
    ) using p_item_id, v_player_id;

    insert into public.player_item_usage (
        player_id, item_id, equip_count, last_equipped_at
    ) values (v_player_id, p_item_id, 1, now())
    on conflict (player_id, item_id) do update set
        equip_count = public.player_item_usage.equip_count + 1,
        last_equipped_at = now();

    return jsonb_build_object(
        'ok', true, 'slot', p_slot, 'item_id', p_item_id
    );
end;
$$;

revoke all on function public.equip_cosmetic(text, text) from public, anon;
grant execute on function public.equip_cosmetic(text, text) to authenticated;

create or replace function public.unequip_cosmetic(p_slot text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_player_id uuid := auth.uid();
    v_fallback text;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;
    if p_slot not in (
        'character_skin', 'hat', 'shirt', 'pants', 'shoes', 'accessory',
        'gun_skin', 'melee_skin', 'emote', 'round_victory_move',
        'ceremony_theme', 'profile_badge'
    ) then
        raise exception 'Invalid loadout slot.';
    end if;

    v_fallback := case p_slot
        when 'gun_skin' then 'base_one_gun'
        when 'melee_skin' then 'base_arena_melee'
        when 'round_victory_move' then 'hip_hop_dance'
        when 'ceremony_theme' then 'wc_theme_ceremony_march'
        else null
    end;

    insert into public.player_loadouts (player_id)
    values (v_player_id) on conflict (player_id) do nothing;

    execute format(
        'update public.player_loadouts set %I = $1, updated_at = now() where player_id = $2',
        p_slot
    ) using v_fallback, v_player_id;

    return jsonb_build_object(
        'ok', true, 'slot', p_slot, 'item_id', v_fallback
    );
end;
$$;

revoke all on function public.unequip_cosmetic(text) from public, anon;
grant execute on function public.unequip_cosmetic(text) to authenticated;

create or replace function public.unequip_outfit(p_bundle_id text)
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
        select 1
        from public.player_inventory inventory
        join public.shop_items item on item.id = inventory.item_id
        where inventory.player_id = v_player_id
          and inventory.item_id = p_bundle_id
          and item.item_type = 'outfit_bundle'
          and item.active = true
    ) then
        raise exception 'You do not own this outfit.';
    end if;

    select max(bundle.item_id) filter (where item.item_type = 'hat'),
           max(bundle.item_id) filter (where item.item_type = 'shirt'),
           max(bundle.item_id) filter (where item.item_type = 'pants'),
           max(bundle.item_id) filter (where item.item_type = 'shoes')
    into v_hat, v_shirt, v_pants, v_shoes
    from public.shop_bundle_items bundle
    join public.shop_items item on item.id = bundle.item_id
    where bundle.bundle_id = p_bundle_id;

    update public.player_loadouts
    set hat = case when hat = v_hat then null else hat end,
        shirt = case when shirt = v_shirt then null else shirt end,
        pants = case when pants = v_pants then null else pants end,
        shoes = case when shoes = v_shoes then null else shoes end,
        updated_at = now()
    where player_id = v_player_id;

    return jsonb_build_object(
        'ok', true, 'bundle_id', p_bundle_id,
        'hat', null, 'shirt', null, 'pants', null, 'shoes', null
    );
end;
$$;

revoke all on function public.unequip_outfit(text) from public, anon;
grant execute on function public.unequip_outfit(text) to authenticated;

create or replace function public.reset_cosmetic_loadout()
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

    insert into public.player_loadouts (player_id)
    values (v_player_id) on conflict (player_id) do nothing;

    update public.player_loadouts
    set hat = null,
        shirt = null,
        pants = null,
        shoes = null,
        accessory = null,
        gun_skin = 'base_one_gun',
        melee_skin = 'base_arena_melee',
        emote = null,
        round_victory_move = 'hip_hop_dance',
        ceremony_theme = 'wc_theme_ceremony_march',
        profile_badge = null,
        updated_at = now()
    where player_id = v_player_id;

    return jsonb_build_object(
        'ok', true,
        'preserved', jsonb_build_array('character_skin', 'character_model', 'character_color'),
        'gun_skin', 'base_one_gun',
        'melee_skin', 'base_arena_melee',
        'emote', null,
        'round_victory_move', 'hip_hop_dance',
        'ceremony_theme', 'wc_theme_ceremony_march'
    );
end;
$$;

revoke all on function public.reset_cosmetic_loadout() from public, anon;
grant execute on function public.reset_cosmetic_loadout() to authenticated;

do $$
begin
    if (select count(*) from public.shop_items
            where id like 'podium_%' and item_type = 'victory_dance'
              and subcategory = 'dances') <> 7 then
        raise exception 'Expected seven migrated podium-prefix dances.';
    end if;
    if (select count(*) from public.shop_items
            where id like 'round_%' and item_type = 'victory_dance'
              and subcategory = 'dances') <> 7 then
        raise exception 'Expected seven migrated round-prefix dances.';
    end if;
    if (select count(*) from public.shop_items
            where id in (
                'base_one_gun', 'base_arena_melee',
                'hip_hop_dance', 'swing_dance'
            ) and active and not purchasable and not shop_visible) <> 4 then
        raise exception 'Expected all four hidden baseline Locker items.';
    end if;
end;
$$;

commit;

notify pgrst, 'reload schema';
