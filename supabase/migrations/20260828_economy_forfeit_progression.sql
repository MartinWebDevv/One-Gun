-- One Gun economy v2: placement-only Gun Tokens, stacked XP growth,
-- start-locked Official matches, finisher-based confirmation, and separate
-- Career/Season Prestige presentation.

alter table public.season_archives
    add column if not exists final_prestige integer not null default 0,
    add column if not exists career_level_snapshot integer not null default 1,
    add column if not exists career_prestige_snapshot integer not null default 0;

create or replace function public.one_gun_xp_required(p_level integer)
returns integer
language sql
immutable
as $$
    select case
        when greatest(p_level, 1) <= 100 then
            round(250.0 + 750.0 * (greatest(p_level, 1) - 1) / 99.0)::integer
        else
            (1000 + 15 * (greatest(p_level, 1) - 100))::integer
    end;
$$;

-- New result snapshots retain everyone who started the match, mark quitters
-- as unfinished, and use the remaining finishers for the confirmation quorum.
create or replace function public.one_gun_validate_finisher_confirmation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result jsonb;
    v_entry jsonb;
    v_expected integer;
    v_started integer;
    v_finishers integer;
    v_counted_finishers integer;
    v_forfeit boolean;
    v_forfeit_winners integer;
begin
    select result into v_result
    from public.official_matches
    where match_id = new.match_id;

    if v_result is null then
        raise exception 'The Official match result is missing.';
    end if;

    v_expected := coalesce(
        (v_result->>'expected_humans')::integer,
        jsonb_array_length(v_result->'entries')
    );
    v_started := coalesce((v_result->>'started_humans')::integer, v_expected);
    v_finishers := coalesce((v_result->>'finisher_humans')::integer, v_expected);
    v_forfeit := coalesce((v_result->>'forfeit_win')::boolean, false);

    select count(*) into v_counted_finishers
    from jsonb_array_elements(v_result->'entries') value
    where not coalesce((value->>'is_bot')::boolean, false)
      and coalesce((value->>'finished_match')::boolean, true);

    if v_started < 3 or v_started > 10 or v_expected <> v_started
       or v_finishers < 1 or v_finishers > v_started
       or v_counted_finishers <> v_finishers then
        raise exception 'The Official starting roster or finisher count is invalid.';
    end if;

    select value into v_entry
    from jsonb_array_elements(v_result->'entries') value
    where (value->>'actor_id')::integer = new.actor_id;

    if v_entry is null or not coalesce((v_entry->>'finished_match')::boolean, true) then
        raise exception 'Players who leave before the result cannot claim rewards.';
    end if;

    if v_finishers = 1 and not v_forfeit then
        raise exception 'A sole-finisher result must be marked as a forfeit victory.';
    end if;

    if v_forfeit then
        select count(*) into v_forfeit_winners
        from jsonb_array_elements(v_result->'entries') value
        where coalesce((value->>'finished_match')::boolean, true)
          and coalesce((value->>'forfeit_winner')::boolean, false)
          and (value->>'placement')::integer = 1;
        if v_finishers <> 1 or v_forfeit_winners <> 1 then
            raise exception 'The forfeit victory result is invalid.';
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists one_gun_validate_finisher_confirmation_trigger
    on public.official_match_confirmations;
create trigger one_gun_validate_finisher_confirmation_trigger
before insert on public.official_match_confirmations
for each row execute function public.one_gun_validate_finisher_confirmation();

create or replace function public.one_gun_settle_finisher_quorum()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_match public.official_matches%rowtype;
    v_finishers integer;
    v_confirmations integer;
    v_required integer;
    v_confirmed record;
begin
    select * into v_match
    from public.official_matches
    where match_id = new.match_id
    for update;

    if not found or v_match.status <> 'pending' then
        return new;
    end if;

    v_finishers := coalesce(
        (v_match.result->>'finisher_humans')::integer,
        v_match.expected_players
    );
    v_required := floor(v_finishers / 2.0)::integer + 1;

    select count(*) into v_confirmations
    from public.official_match_confirmations
    where match_id = new.match_id
      and result_hash = new.result_hash;

    if v_confirmations < v_required then
        return new;
    end if;

    update public.official_matches
    set status = 'settled', settled_at = now()
    where match_id = new.match_id and status = 'pending';

    for v_confirmed in
        select player_id
        from public.official_match_confirmations
        where match_id = new.match_id
          and result_hash = new.result_hash
    loop
        perform public.one_gun_award_confirmed_player(
            new.match_id, v_confirmed.player_id
        );
    end loop;

    return new;
end;
$$;

drop trigger if exists one_gun_settle_finisher_quorum_trigger
    on public.official_match_confirmations;
create trigger one_gun_settle_finisher_quorum_trigger
after insert on public.official_match_confirmations
for each row execute function public.one_gun_settle_finisher_quorum();

-- The original award function still calculates XP, roads, ownership, stats,
-- and idempotency. This insert trigger replaces only its old performance-based
-- match Token portion with the approved fixed placement award.
create or replace function public.one_gun_apply_placement_tokens()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_match_tokens integer;
    v_level_bonus integer;
    v_total_tokens integer;
    v_delta integer;
    v_balance bigint;
    v_breakdown jsonb;
    v_career_levels integer := 0;
    v_season_level integer := 1;
begin
    if not new.eligible then
        return new;
    end if;

    v_match_tokens := case new.placement
        when 1 then 250
        when 2 then 200
        when 3 then 150
        else 100
    end;
    v_level_bonus := coalesce(
        (new.breakdown->>'level_road_tokens')::integer, 0
    );
    v_total_tokens := v_match_tokens + v_level_bonus;
    v_delta := v_total_tokens - new.gun_tokens_delta;

    update public.player_currency
    set gun_tokens = gun_tokens + v_delta,
        updated_at = now()
    where player_id = new.player_id
    returning gun_tokens into v_balance;

    select career_levels_earned into v_career_levels
    from public.player_progression
    where player_id = new.player_id;

    select season_level into v_season_level
    from public.player_season_progress
    where player_id = new.player_id and season_id = new.season_id;

    v_breakdown := new.breakdown;
    v_breakdown := jsonb_set(
        v_breakdown, '{token_breakdown}',
        jsonb_build_object('placement', v_match_tokens), true
    );
    v_breakdown := jsonb_set(
        v_breakdown, '{new_gun_token_balance}',
        to_jsonb(coalesce(v_balance, 0)), true
    );
    v_breakdown := jsonb_set(
        v_breakdown, '{new_season_prestige}',
        to_jsonb((greatest(v_season_level, 1) - 1) / 100), true
    );
    v_breakdown := jsonb_set(
        v_breakdown, '{new_career_level}',
        to_jsonb(coalesce(v_career_levels, 0) + 1), true
    );
    v_breakdown := jsonb_set(
        v_breakdown, '{new_career_prestige}',
        to_jsonb(coalesce(v_career_levels, 0) / 100), true
    );
    -- Compatibility aliases for existing Winners Circle consumers.
    v_breakdown := jsonb_set(
        v_breakdown, '{new_lifetime_level}',
        to_jsonb(coalesce(v_career_levels, 0) + 1), true
    );
    v_breakdown := jsonb_set(
        v_breakdown, '{new_lifetime_prestige}',
        to_jsonb(coalesce(v_career_levels, 0) / 100), true
    );

    update public.wallet_ledger
    set amount = v_total_tokens,
        balance_after = coalesce(v_balance, balance_after)
    where player_id = new.player_id and match_id = new.match_id;

    update public.match_rewards
    set gun_tokens_delta = v_total_tokens,
        breakdown = v_breakdown
    where match_id = new.match_id and player_id = new.player_id;

    return new;
end;
$$;

drop trigger if exists one_gun_apply_placement_tokens_trigger
    on public.match_rewards;
create trigger one_gun_apply_placement_tokens_trigger
after insert on public.match_rewards
for each row execute function public.one_gun_apply_placement_tokens();

create or replace function public.one_gun_capture_archive_ranks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    v_career_levels integer;
begin
    new.final_prestige := (greatest(new.final_level, 1) - 1) / 100;
    select career_levels_earned into v_career_levels
    from public.player_progression
    where player_id = new.player_id;
    if found then
        new.career_level_snapshot := v_career_levels + 1;
        new.career_prestige_snapshot := v_career_levels / 100;
    end if;
    return new;
end;
$$;

drop trigger if exists one_gun_capture_archive_ranks_trigger
    on public.season_archives;
create trigger one_gun_capture_archive_ranks_trigger
before insert on public.season_archives
for each row execute function public.one_gun_capture_archive_ranks();

update public.season_archives archive
set final_prestige = (greatest(archive.final_level, 1) - 1) / 100,
    career_level_snapshot = progression.career_levels_earned + 1,
    career_prestige_snapshot = progression.career_levels_earned / 100
from public.player_progression progression
where progression.player_id = archive.player_id;

create or replace function public.one_gun_reward_receipt_json(
    p_match_id text, p_player_id uuid
)
returns jsonb
language sql
security definer
set search_path = public
as $$
    select jsonb_build_object(
        'state', case when reward.eligible then 'settled' else 'ineligible' end,
        'match_id', reward.match_id,
        'persisted', true,
        'eligible', reward.eligible,
        'xp_delta', reward.xp_delta,
        'gun_tokens_delta', reward.gun_tokens_delta,
        'trophy_delta', reward.trophy_delta,
        'breakdown', reward.breakdown,
        'xp_breakdown', coalesce(reward.breakdown->'xp_breakdown', '{}'::jsonb),
        'token_breakdown', coalesce(reward.breakdown->'token_breakdown', '{}'::jsonb),
        'unlocks', coalesce(reward.breakdown->'unlocks', '[]'::jsonb),
        'level_road_tokens', coalesce((reward.breakdown->>'level_road_tokens')::integer, 0),
        'new_season_level', coalesce((reward.breakdown->>'new_season_level')::integer, 1),
        'new_season_xp', coalesce((reward.breakdown->>'new_season_xp')::integer, 0),
        'next_level_xp', coalesce((reward.breakdown->>'next_level_xp')::integer, 250),
        'new_season_prestige', coalesce((reward.breakdown->>'new_season_prestige')::integer, 0),
        'new_season_trophies', coalesce((reward.breakdown->>'new_season_trophies')::integer, 0),
        'new_gun_token_balance', coalesce((reward.breakdown->>'new_gun_token_balance')::bigint, 0),
        'new_career_level', coalesce((reward.breakdown->>'new_career_level')::integer, 1),
        'new_career_prestige', coalesce((reward.breakdown->>'new_career_prestige')::integer, 0),
        'new_lifetime_level', coalesce((reward.breakdown->>'new_career_level')::integer, 1),
        'new_lifetime_prestige', coalesce((reward.breakdown->>'new_career_prestige')::integer, 0)
    )
    from public.match_rewards reward
    where reward.match_id = p_match_id and reward.player_id = p_player_id;
$$;

revoke all on function public.one_gun_validate_finisher_confirmation() from public, anon, authenticated;
revoke all on function public.one_gun_settle_finisher_quorum() from public, anon, authenticated;
revoke all on function public.one_gun_apply_placement_tokens() from public, anon, authenticated;
revoke all on function public.one_gun_capture_archive_ranks() from public, anon, authenticated;
revoke all on function public.one_gun_reward_receipt_json(text, uuid) from public, anon, authenticated;

