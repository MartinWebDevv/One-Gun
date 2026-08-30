begin;

insert into auth.users (id)
values ('30000000-0000-0000-0000-000000000001')
on conflict (id) do nothing;

insert into public.profiles (id, username)
values ('30000000-0000-0000-0000-000000000001', 'GoldFishTest')
on conflict (id) do nothing;

insert into public.player_loadouts (player_id)
values ('30000000-0000-0000-0000-000000000001')
on conflict (player_id) do nothing;

insert into public.player_inventory (player_id, item_id, obtained_at, source)
values (
    '30000000-0000-0000-0000-000000000001',
    'character_goldfish_bag_man', now(), 'manual_gift'
)
on conflict (player_id, item_id) do nothing;

select set_config(
    'request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000001',
    true
);

select public.equip_cosmetic(
    'character_model', 'character_goldfish_bag_man');

do $$
begin
    if (select character_model from public.player_loadouts
            where player_id = '30000000-0000-0000-0000-000000000001')
            <> 'character_goldfish_bag_man' then
        raise exception 'Owned Gold Fish model did not equip.';
    end if;
    if exists (
        select 1 from public.shop_items
        where id = 'character_goldfish_bag_man'
          and (purchasable or shop_visible or featured)
    ) then
        raise exception 'Gold Fish model leaked into the public shop.';
    end if;
end;
$$;

select public.unequip_cosmetic('character_model');

do $$
begin
    if (select character_model from public.player_loadouts
            where player_id = '30000000-0000-0000-0000-000000000001')
            is not null then
        raise exception 'Gold Fish model did not unequip.';
    end if;
end;
$$;

rollback;
