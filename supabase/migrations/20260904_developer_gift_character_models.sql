begin;

-- These packaged character models are developer gifts. They remain active so
-- trusted inventory grants can equip them, but they must never enter the
-- public Prize Counter or any timed rotation.
insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory,
    featured, rotation_scope, sort_order
) values
    (
        'character_eye_wizard', 'Eye Wizard', 'character_model',
        'A special arena competitor granted directly by the One Gun team.',
        0, 'epic', false, false, true, 'character', 'skins', false, 'none', 9010
    ),
    (
        'character_mr_mushroom', 'Mr. Mushroom', 'character_model',
        'A special arena competitor granted directly by the One Gun team.',
        0, 'epic', false, false, true, 'character', 'skins', false, 'none', 9020
    ),
    (
        'character_mr_poop', 'Mr. Poop', 'character_model',
        'A special arena competitor granted directly by the One Gun team.',
        0, 'epic', false, false, true, 'character', 'skins', false, 'none', 9030
    ),
    (
        'character_mr_salt', 'Mr. Salt', 'character_model',
        'A special arena competitor granted directly by the One Gun team.',
        0, 'epic', false, false, true, 'character', 'skins', false, 'none', 9040
    ),
    (
        'character_spooky_witch', 'Spooky Witch', 'character_model',
        'A special arena competitor granted directly by the One Gun team.',
        0, 'epic', false, false, true, 'character', 'skins', false, 'none', 9050
    )
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = 'character_model',
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
-- values ('PLAYER_UUID', 'character_eye_wizard', now(), 'manual_gift')
-- on conflict (player_id, item_id) do nothing;

do $$
declare
    v_valid_count integer;
begin
    select count(*) into v_valid_count
    from public.shop_items
    where id in (
        'character_eye_wizard',
        'character_mr_mushroom',
        'character_mr_poop',
        'character_mr_salt',
        'character_spooky_witch'
    )
      and item_type = 'character_model'
      and active
      and not purchasable
      and not shop_visible
      and not featured
      and rotation_scope = 'none';

    if v_valid_count <> 5 then
        raise exception 'All five added character models must remain active and developer-gift-only.';
    end if;
end;
$$;

commit;

notify pgrst, 'reload schema';
