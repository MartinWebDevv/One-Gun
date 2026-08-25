-- One Gun: fourteen locally shipped victory-move products.
-- Seven long-form moves belong to Winners Circle podiums; seven short-form
-- moves belong to round-win celebrations. All resource paths stay in Godot.

begin;

insert into public.shop_items (
    id, display_name, item_type, description, price, rarity,
    purchasable, shop_visible, active, category, subcategory, featured,
    rotation_scope, rotation_starts_at, rotation_ends_at, sort_order
) values
    (
        'podium_backbeat_bounce', 'Backbeat Bounce', 'emote',
        'A bass-driven full-body celebration built for the Winners Circle spotlight.',
        2600, 'epic', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 300
    ),
    (
        'podium_champion_canter', 'Champion Canter', 'emote',
        'A fearless champion step with enough swagger to command the whole podium.',
        3800, 'legendary', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 301
    ),
    (
        'podium_fresh_footwork', 'Fresh Footwork', 'emote',
        'Quick rhythmic footwork for a clean, confident Winners Circle entrance.',
        1700, 'rare', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 302
    ),
    (
        'podium_house_party_heat', 'House Party Heat', 'emote',
        'A long-form arena dance that turns the champion podium into a party.',
        2900, 'epic', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 303
    ),
    (
        'podium_serpent_flow', 'Serpent Flow', 'emote',
        'Smooth winding movement and sharp accents for a stylish podium performance.',
        2700, 'epic', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 304
    ),
    (
        'podium_midnight_monster', 'Midnight Monster', 'emote',
        'A theatrical after-dark routine reserved for players who own the stage.',
        4200, 'legendary', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 305
    ),
    (
        'podium_victory_wave', 'Victory Wave', 'emote',
        'Rolling upper-body waves and precise hits for an electric final reveal.',
        3100, 'epic', true, true, true, 'victory', 'podium_dances', false,
        'monthly', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 306
    ),
    (
        'round_breakspin_finale', 'Breakspin Finale', 'round_victory_move',
        'A compact breakdance finish that punctuates a hard-earned round win.',
        1500, 'rare', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 320
    ),
    (
        'round_floorwork_finish', 'Floorwork Finish', 'round_victory_move',
        'A technical floor sequence with a decisive closing pose.',
        2200, 'epic', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 321
    ),
    (
        'round_birdie_boogie', 'Birdie Boogie', 'round_victory_move',
        'A playful flapping celebration for lighthearted round winners.',
        900, 'uncommon', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 322
    ),
    (
        'round_arena_clapline', 'Arena Clapline', 'round_victory_move',
        'A crowd-ready sequence of claps, steps, and victory confidence.',
        1200, 'rare', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 323
    ),
    (
        'round_soul_cyclone', 'Soul Cyclone', 'round_victory_move',
        'Fast spins and soulful footwork for an explosive round-ending flourish.',
        2100, 'epic', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 324
    ),
    (
        'round_quickstep_shuffle', 'Quickstep Shuffle', 'round_victory_move',
        'Rapid heel-toe movement that celebrates without slowing the next round.',
        1400, 'rare', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 325
    ),
    (
        'round_victory_swing', 'Victory Swing', 'round_victory_move',
        'A cheerful swinging-arm finish with classic One Gun charm.',
        1000, 'uncommon', true, true, true, 'victory', 'round_moves', false,
        'daily', '2026-08-24 00:00:00+00', '2026-11-24 00:00:00+00', 326
    )
on conflict (id) do update set
    display_name = excluded.display_name,
    item_type = excluded.item_type,
    description = excluded.description,
    price = excluded.price,
    rarity = excluded.rarity,
    purchasable = excluded.purchasable,
    shop_visible = excluded.shop_visible,
    active = excluded.active,
    category = excluded.category,
    subcategory = excluded.subcategory,
    featured = excluded.featured,
    rotation_scope = excluded.rotation_scope,
    rotation_starts_at = excluded.rotation_starts_at,
    rotation_ends_at = excluded.rotation_ends_at,
    sort_order = excluded.sort_order;

do $$
begin
    if (select count(*) from public.shop_items
            where id like 'podium_%' and item_type = 'emote') <> 7 then
        raise exception 'Expected exactly seven new Winners Circle podium dances.';
    end if;
    if (select count(*) from public.shop_items
            where id like 'round_%' and item_type = 'round_victory_move') <> 7 then
        raise exception 'Expected exactly seven new round-win moves.';
    end if;
end;
$$;

commit;
