begin;

insert into auth.users (id)
values ('30000000-0000-0000-0000-000000000002')
on conflict (id) do nothing;

insert into public.profiles (id, username)
values ('30000000-0000-0000-0000-000000000002', 'GiftModelsTest')
on conflict (id) do nothing;

insert into public.player_loadouts (player_id)
values ('30000000-0000-0000-0000-000000000002')
on conflict (player_id) do nothing;

insert into public.player_inventory (player_id, item_id, obtained_at, source)
select
    '30000000-0000-0000-0000-000000000002'::uuid,
    item_id,
    now(),
    'manual_gift'
from unnest(array[
    'character_eye_wizard',
    'character_mr_mushroom',
    'character_mr_poop',
    'character_mr_salt',
    'character_spooky_witch'
]) as gift(item_id)
on conflict (player_id, item_id) do nothing;

select set_config(
    'request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000002',
    true
);

do $$
declare
    v_item_id text;
begin
    if (
        select count(*)
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
          and rotation_scope = 'none'
    ) <> 5 then
        raise exception 'Developer-gift character catalog visibility is invalid.';
    end if;

    foreach v_item_id in array array[
        'character_eye_wizard',
        'character_mr_mushroom',
        'character_mr_poop',
        'character_mr_salt',
        'character_spooky_witch'
    ] loop
        perform public.equip_cosmetic('character_model', v_item_id);
        if (select character_model from public.player_loadouts
                where player_id = '30000000-0000-0000-0000-000000000002')
                <> v_item_id then
            raise exception 'Owned developer-gift model did not equip: %', v_item_id;
        end if;
    end loop;
end;
$$;

select public.unequip_cosmetic('character_model');

do $$
begin
    if (select character_model from public.player_loadouts
            where player_id = '30000000-0000-0000-0000-000000000002')
            is not null then
        raise exception 'Developer-gift character model did not unequip.';
    end if;
end;
$$;

rollback;
