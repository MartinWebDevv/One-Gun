-- One Gun: Winners Circle ceremony-theme ownership and loadout support.
-- Run once in the Supabase SQL Editor as the project/database owner.
-- This file contains no service-role key and must never be executed by the game client.

begin;

-- The default is a hidden starter unlock. The other six approved themes are
-- visible Prize Counter items. Prices are Beta starting values and can be
-- tuned here without changing or rebuilding the Godot client.
insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active
) values
    (
        'wc_theme_ceremony_march', 'Ceremony March', 'ceremony_theme',
        'The official One Gun Winners Circle march. Included for every player.',
        0, 'standard', false, false, true
    ),
    (
        'wc_theme_neon_victory', 'Neon Victory', 'ceremony_theme',
        'A bright electronic victory charge timed to every podium reveal.',
        1200, 'rare', true, true, true
    ),
    (
        'wc_theme_western_toybox', 'Western Toybox', 'ceremony_theme',
        'A playful frontier celebration with a One Gun toy-box spirit.',
        750, 'uncommon', true, true, true
    ),
    (
        'wc_theme_grand_arena', 'Grand Arena', 'ceremony_theme',
        'A large ceremonial anthem built for a champion entrance.',
        1800, 'epic', true, true, true
    ),
    (
        'wc_theme_pixel_champion', 'Pixel Champion', 'ceremony_theme',
        'A colorful digital victory theme with a smooth final flourish.',
        1400, 'rare', true, true, true
    ),
    (
        'wc_theme_champion_groove', 'Champion Groove', 'ceremony_theme',
        'A confident champion groove with a playful arena-sized finish.',
        1600, 'epic', true, true, true
    ),
    (
        'wc_theme_deep_orbit', 'Deep Orbit', 'ceremony_theme',
        'A deep electronic champion theme with warm bass and cinematic space.',
        2200, 'legendary', true, true, true
)
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = excluded.item_type,
    description = excluded.description,
    price = excluded.price,
    rarity = excluded.rarity,
    purchasable = excluded.purchasable,
    shop_visible = excluded.shop_visible,
    active = excluded.active;

alter table public.player_loadouts
    add column if not exists ceremony_theme text;

update public.player_loadouts
set ceremony_theme = 'wc_theme_ceremony_march'
where ceremony_theme is null or btrim(ceremony_theme) = '';

alter table public.player_loadouts
    alter column ceremony_theme set default 'wc_theme_ceremony_march',
    alter column ceremony_theme set not null;

-- Existing accounts receive the default permanently. This insert is safe to
-- rerun because player_inventory is unique on (player_id, item_id).
insert into public.player_inventory (player_id, item_id, obtained_at, source)
select player_id, 'wc_theme_ceremony_march', now(), 'starter_unlock'
from public.player_loadouts
on conflict (player_id, item_id) do nothing;

-- Every future loadout/account receives the same permanent starter unlock.
create or replace function public.grant_default_ceremony_theme()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.player_inventory (player_id, item_id, obtained_at, source)
    values (new.player_id, 'wc_theme_ceremony_march', now(), 'starter_unlock')
    on conflict (player_id, item_id) do nothing;
    return new;
end;
$$;

revoke all on function public.grant_default_ceremony_theme()
    from public, anon, authenticated;

drop trigger if exists grant_default_ceremony_theme_on_loadout
    on public.player_loadouts;
create trigger grant_default_ceremony_theme_on_loadout
after insert on public.player_loadouts
for each row execute function public.grant_default_ceremony_theme();

-- Isolated RPC: the working six-slot equip_cosmetic function is untouched.
-- This endpoint trusts auth.uid(), validates catalog type + ownership, and is
-- the only client-callable write path for player_loadouts.ceremony_theme.
create or replace function public.equip_ceremony_theme(p_item_id text)
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
        raise exception 'Authentication required.' using errcode = '28000';
    end if;

    select item_type
    into v_item_type
    from public.shop_items
    where id = p_item_id and active = true;

    if not found or v_item_type <> 'ceremony_theme' then
        raise exception 'This is not an active Winners Circle theme.'
            using errcode = '22023';
    end if;

    if not exists (
        select 1
        from public.player_inventory
        where player_id = v_player_id and item_id = p_item_id
    ) then
        raise exception 'You do not own this Winners Circle theme.'
            using errcode = '42501';
    end if;

    insert into public.player_loadouts (
        player_id, ceremony_theme, updated_at
    ) values (
        v_player_id, p_item_id, now()
    )
    on conflict (player_id) do update set
        ceremony_theme = excluded.ceremony_theme,
        updated_at = excluded.updated_at;

    return jsonb_build_object(
        'ok', true,
        'slot', 'ceremony_theme',
        'item_id', p_item_id
    );
end;
$$;

revoke all on function public.equip_ceremony_theme(text) from public, anon;
grant execute on function public.equip_ceremony_theme(text) to authenticated;

-- The Prize Counter is intentionally public-readable; purchases/equips remain
-- authenticated RPCs protected by their own ownership/currency checks.
grant select on table public.shop_items to anon, authenticated;

commit;

-- Ask PostgREST to expose the new column/RPC immediately.
notify pgrst, 'reload schema';
