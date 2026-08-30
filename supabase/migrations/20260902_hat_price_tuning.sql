-- One Gun: rarity-stepped pricing pass for the ten Prize Counter hats.
-- Reward-road hats remain non-purchasable and keep their zero-token price.

begin;

update public.shop_items
set price = case id
    when 'hat_chef' then 850
    when 'hat_yellow_point' then 850
    when 'hat_cowboy_classic' then 1250
    when 'hat_fedora_black' then 1250
    when 'hat_straw_adventurer' then 1250
    when 'hat_cowboy_wide' then 1650
    when 'hat_fedora_white' then 1650
    when 'hat_top' then 1650
    when 'hat_witch' then 1650
    when 'hat_crown' then 2200
    else price
end
where id in (
    'hat_chef', 'hat_yellow_point',
    'hat_cowboy_classic', 'hat_fedora_black', 'hat_straw_adventurer',
    'hat_cowboy_wide', 'hat_fedora_white', 'hat_top', 'hat_witch',
    'hat_crown'
);

do $$
begin
    if (select count(*) from public.shop_items
        where (id in ('hat_chef', 'hat_yellow_point') and price = 850)
           or (id in ('hat_cowboy_classic', 'hat_fedora_black',
                      'hat_straw_adventurer') and price = 1250)
           or (id in ('hat_cowboy_wide', 'hat_fedora_white', 'hat_top',
                      'hat_witch') and price = 1650)
           or (id = 'hat_crown' and price = 2200)) <> 10 then
        raise exception 'Hat price tuning did not update all ten Prize Counter hats';
    end if;
end;
$$;

commit;
