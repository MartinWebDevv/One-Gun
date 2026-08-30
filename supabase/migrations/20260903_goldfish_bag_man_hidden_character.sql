begin;

-- Gift-only character models occupy their own slot so they do not overwrite a
-- player's selected cat color. This column is intentionally preserved by the
-- existing reset_cosmetic_loadout() function.
alter table public.player_loadouts
    add column if not exists character_model text;

insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope, sort_order
) values (
    'character_goldfish_bag_man',
    'Gold Fish Bag Man',
    'character_model',
    'A special arena competitor granted directly by the One Gun team.',
    0,
    'epic',
    false,
    false,
    true,
    'character',
    'skins',
    false,
    'none',
    9000
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
    category = 'character',
    subcategory = 'skins',
    featured = false,
    rotation_scope = 'none',
    rotation_starts_at = null,
    rotation_ends_at = null,
    sort_order = excluded.sort_order;

-- Manual gift example (run with a real profile UUID from the Supabase SQL
-- editor, never from an untrusted client):
-- insert into public.player_inventory (player_id, item_id, obtained_at, source)
-- values ('PLAYER_UUID', 'character_goldfish_bag_man', now(), 'manual_gift')
-- on conflict (player_id, item_id) do nothing;

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
        'character_skin', 'character_model', 'hat', 'shirt', 'pants',
        'shoes', 'accessory', 'gun_skin', 'melee_skin', 'emote',
        'round_victory_move', 'profile_badge'
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
        'character_skin', 'character_model', 'hat', 'shirt', 'pants',
        'shoes', 'accessory', 'gun_skin', 'melee_skin', 'emote',
        'round_victory_move', 'ceremony_theme', 'profile_badge'
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

do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name = 'player_loadouts'
          and column_name = 'character_model'
    ) then
        raise exception 'player_loadouts.character_model was not created.';
    end if;
    if not exists (
        select 1 from public.shop_items
        where id = 'character_goldfish_bag_man'
          and item_type = 'character_model'
          and active
          and not purchasable
          and not shop_visible
          and not featured
    ) then
        raise exception 'Gold Fish Bag Man must remain active and gift-only.';
    end if;
end;
$$;

commit;

notify pgrst, 'reload schema';
