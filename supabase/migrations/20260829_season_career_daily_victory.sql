-- One Gun progression v3: research-informed Season/Career curves and a
-- server-authoritative first Official Classic victory bonus each UTC day.

begin;

create table if not exists public.player_daily_victory_bonuses (
    player_id uuid not null references public.profiles(id) on delete cascade,
    bonus_date date not null,
    match_id text not null references public.official_matches(match_id) on delete restrict,
    season_id text not null references public.game_seasons(id) on delete restrict,
    season_xp integer not null default 25,
    gun_tokens integer not null default 100,
    awarded_at timestamptz not null default now(),
    primary key (player_id, bonus_date),
    unique (match_id, player_id),
    constraint player_daily_victory_bonus_xp_check check (season_xp >= 0),
    constraint player_daily_victory_bonus_tokens_check check (gun_tokens >= 0)
);

create index if not exists player_daily_victory_bonuses_history
    on public.player_daily_victory_bonuses (player_id, awarded_at desc);

alter table public.player_daily_victory_bonuses enable row level security;
drop policy if exists "Players can read own daily victory bonuses"
    on public.player_daily_victory_bonuses;
create policy "Players can read own daily victory bonuses"
    on public.player_daily_victory_bonuses for select to authenticated
    using (auth.uid() = player_id);
grant select on public.player_daily_victory_bonuses to authenticated;

create or replace function public.one_gun_season_xp_required(p_level integer)
returns integer
language sql
immutable
as $$
    select (150 + 2 * (greatest(p_level, 1) - 1))::integer;
$$;

create or replace function public.one_gun_career_xp_required(p_level integer)
returns integer
language sql
immutable
as $$
    select 400::integer;
$$;

-- Compatibility helper retained for older client/display paths. Season level
-- progression is the default interpretation; Career uses its dedicated helper.
create or replace function public.one_gun_xp_required(p_level integer)
returns integer
language sql
immutable
as $$
    select public.one_gun_season_xp_required(p_level);
$$;

-- Preserve each existing player's percentage through their current level when
-- changing from the previous curve. Historical total XP remains untouched.
update public.player_season_progress progress
set xp_into_level = least(
        public.one_gun_season_xp_required(progress.season_level) - 1,
        floor(
            progress.xp_into_level::numeric
            * public.one_gun_season_xp_required(progress.season_level)
            / case
                when progress.season_level <= 100 then
                    round(250.0 + 750.0 * (progress.season_level - 1) / 99.0)::integer
                else 1000 + 15 * (progress.season_level - 100)
              end
        )::integer
    ),
    updated_at = now();

update public.player_progression progress
set career_xp_into_level = least(
        public.one_gun_career_xp_required(progress.career_levels_earned + 1) - 1,
        floor(
            progress.career_xp_into_level::numeric
            * public.one_gun_career_xp_required(progress.career_levels_earned + 1)
            / case
                when progress.career_levels_earned + 1 <= 100 then
                    round(250.0 + 750.0 * progress.career_levels_earned / 99.0)::integer
                else 1000 + 15 * (progress.career_levels_earned + 1 - 100)
              end
        )::integer
    ),
    updated_at = now();

-- Placement Tokens are now calculated directly by the authoritative award
-- function, along with the daily bonus, so the older correction trigger must
-- not run after the receipt has been written.
drop trigger if exists one_gun_apply_placement_tokens_trigger
    on public.match_rewards;

create or replace function public.one_gun_award_confirmed_player(
    p_match_id text, p_player_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
    v_match public.official_matches%rowtype;
    v_confirmation public.official_match_confirmations%rowtype;
    v_entry jsonb;
    v_season_id text;
    v_finished boolean;
    v_forfeit_winner boolean;
    v_eligible boolean;
    v_placement integer;
    v_round_wins integer;
    v_kills integer;
    v_deaths integer;
    v_disarms integer;
    v_xp_participation integer := 0;
    v_xp_rounds integer := 0;
    v_xp_placement integer := 0;
    v_xp_kills integer := 0;
    v_xp_disarms integer := 0;
    v_match_xp integer := 0;
    v_daily_date date := (timezone('UTC', now()))::date;
    v_daily_inserted integer := 0;
    v_daily_awarded boolean := false;
    v_daily_xp integer := 0;
    v_daily_tokens integer := 0;
    v_season_xp_award integer := 0;
    v_match_tokens integer := 0;
    v_trophy integer := 0;
    v_old_level integer;
    v_new_level integer;
    v_season_xp integer;
    v_old_trophies integer;
    v_new_trophies integer;
    v_career_levels integer;
    v_career_xp integer;
    v_level_rewards jsonb;
    v_trophy_rewards jsonb;
    v_level_bonus integer := 0;
    v_unlocks jsonb := '[]'::jsonb;
    v_total_tokens integer := 0;
    v_balance bigint := 0;
    v_breakdown jsonb;
begin
    if exists (
        select 1 from public.match_rewards
        where match_id = p_match_id and player_id = p_player_id
    ) then
        return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
    end if;

    select * into v_match
    from public.official_matches
    where match_id = p_match_id and status = 'settled';
    if not found then
        return jsonb_build_object('state', 'pending', 'persisted', false);
    end if;

    select * into v_confirmation
    from public.official_match_confirmations
    where match_id = p_match_id and player_id = p_player_id;
    if not found then
        raise exception 'This account did not confirm the match result.';
    end if;

    select value into v_entry
    from jsonb_array_elements(v_match.result->'entries') value
    where (value->>'actor_id')::integer = v_confirmation.actor_id;
    if v_entry is null then
        raise exception 'The confirmed actor is missing from the result.';
    end if;

    select id into v_season_id
    from public.game_seasons
    where active = true and now() >= starts_at and now() < ends_at
    limit 1;
    if v_season_id is null then
        raise exception 'No active One Gun season is configured.';
    end if;

    v_placement := greatest((v_entry->>'placement')::integer, 1);
    v_round_wins := greatest(coalesce((v_entry->>'round_wins')::integer, 0), 0);
    v_kills := greatest(coalesce((v_entry->>'kills')::integer, 0), 0);
    v_deaths := greatest(coalesce((v_entry->>'deaths')::integer, 0), 0);
    v_disarms := greatest(coalesce((v_entry->>'disarms')::integer, 0), 0);
    v_finished := coalesce((v_entry->>'finished_match')::boolean, true);
    v_forfeit_winner := coalesce((v_entry->>'forfeit_winner')::boolean, false);
    v_eligible := v_finished and (
        v_forfeit_winner or (
            coalesce((v_entry->>'activity_eligible')::boolean, false)
            and coalesce((v_entry->>'rounds_participated')::integer, 0) >= 2
        )
    );

    insert into public.player_progression (player_id)
    values (p_player_id) on conflict (player_id) do nothing;
    insert into public.player_season_progress (player_id, season_id)
    values (p_player_id, v_season_id) on conflict (player_id, season_id) do nothing;
    insert into public.player_currency (player_id, gun_tokens)
    values (p_player_id, 0) on conflict (player_id) do nothing;

    if not v_eligible then
        v_breakdown := jsonb_build_object(
            'state', 'ineligible',
            'reason', 'Active full-match participation requirement was not met.',
            'xp_breakdown', '{}'::jsonb,
            'token_breakdown', '{}'::jsonb,
            'match_xp_delta', 0,
            'season_xp_delta', 0,
            'career_xp_delta', 0,
            'daily_victory_bonus_awarded', false,
            'daily_victory_bonus_date', v_daily_date,
            'daily_victory_bonus_xp', 0,
            'daily_victory_bonus_tokens', 0,
            'level_road_tokens', 0,
            'unlocks', '[]'::jsonb
        );
        insert into public.match_rewards (
            match_id, player_id, season_id, actor_id, mode, map_id,
            placement, round_wins, kills, deaths, disarms,
            xp_delta, gun_tokens_delta, trophy_delta, eligible, breakdown
        ) values (
            p_match_id, p_player_id, v_season_id, v_confirmation.actor_id,
            v_match.mode, v_match.map_id, v_placement, v_round_wins,
            v_kills, v_deaths, v_disarms, 0, 0, 0, false, v_breakdown
        );
        return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
    end if;

    v_xp_participation := 20;
    v_xp_rounds := least(v_round_wins, 3) * 10;
    v_xp_placement := case v_placement
        when 1 then 25 when 2 then 15 when 3 then 10 else 0 end;
    v_xp_kills := least(v_kills, 10);
    v_xp_disarms := least(v_disarms, 5) * 3;
    v_match_xp := least(
        v_xp_participation + v_xp_rounds + v_xp_placement
        + v_xp_kills + v_xp_disarms,
        100
    );

    v_match_tokens := case v_placement
        when 1 then 250
        when 2 then 200
        when 3 then 150
        else 100
    end;
    v_trophy := case when v_placement = 1 then 1 else 0 end;

    select season_level, xp_into_level, trophies
    into v_old_level, v_season_xp, v_old_trophies
    from public.player_season_progress
    where player_id = p_player_id and season_id = v_season_id
    for update;

    select career_levels_earned, career_xp_into_level
    into v_career_levels, v_career_xp
    from public.player_progression
    where player_id = p_player_id
    for update;

    if v_placement = 1 then
        insert into public.player_daily_victory_bonuses (
            player_id, bonus_date, match_id, season_id, season_xp, gun_tokens
        ) values (
            p_player_id, v_daily_date, p_match_id, v_season_id, 25, 100
        ) on conflict (player_id, bonus_date) do nothing;
        get diagnostics v_daily_inserted = row_count;
        if v_daily_inserted > 0 then
            v_daily_awarded := true;
            v_daily_xp := 25;
            v_daily_tokens := 100;
        end if;
    end if;

    v_season_xp_award := v_match_xp + v_daily_xp;
    v_new_level := v_old_level;
    v_season_xp := v_season_xp + v_season_xp_award;
    while v_season_xp >= public.one_gun_season_xp_required(v_new_level) loop
        v_season_xp := v_season_xp - public.one_gun_season_xp_required(v_new_level);
        v_new_level := v_new_level + 1;
    end loop;
    v_new_trophies := v_old_trophies + v_trophy;

    update public.player_season_progress
    set season_level = v_new_level,
        xp_into_level = v_season_xp,
        total_xp = total_xp + v_season_xp_award,
        trophies = v_new_trophies,
        official_matches = official_matches + 1,
        classic_wins = classic_wins + case when v_placement = 1 then 1 else 0 end,
        round_wins = round_wins + v_round_wins,
        kills = kills + v_kills,
        deaths = deaths + v_deaths,
        disarms = disarms + v_disarms,
        updated_at = now()
    where player_id = p_player_id and season_id = v_season_id;

    v_career_xp := v_career_xp + v_match_xp;
    while v_career_xp >= public.one_gun_career_xp_required(v_career_levels + 1) loop
        v_career_xp := v_career_xp - public.one_gun_career_xp_required(v_career_levels + 1);
        v_career_levels := v_career_levels + 1;
    end loop;
    update public.player_progression
    set career_levels_earned = v_career_levels,
        career_xp_into_level = v_career_xp,
        updated_at = now()
    where player_id = p_player_id;

    insert into public.player_mode_stats (
        player_id, mode, matches, wins, best_finish,
        round_wins, kills, deaths, disarms
    ) values (
        p_player_id, 'one_gun', 1,
        case when v_placement = 1 then 1 else 0 end,
        v_placement, v_round_wins, v_kills, v_deaths, v_disarms
    ) on conflict (player_id, mode) do update set
        matches = public.player_mode_stats.matches + 1,
        wins = public.player_mode_stats.wins + case when v_placement = 1 then 1 else 0 end,
        best_finish = least(coalesce(public.player_mode_stats.best_finish, v_placement), v_placement),
        round_wins = public.player_mode_stats.round_wins + v_round_wins,
        kills = public.player_mode_stats.kills + v_kills,
        deaths = public.player_mode_stats.deaths + v_deaths,
        disarms = public.player_mode_stats.disarms + v_disarms,
        updated_at = now();

    v_level_rewards := public.one_gun_grant_due_rewards(
        p_player_id, v_season_id, 'level', v_old_level, v_new_level
    );
    v_trophy_rewards := public.one_gun_grant_due_rewards(
        p_player_id, v_season_id, 'trophy', v_old_trophies, v_new_trophies
    );
    v_level_bonus := coalesce((v_level_rewards->>'gun_tokens')::integer, 0)
        + coalesce((v_trophy_rewards->>'gun_tokens')::integer, 0);
    v_unlocks := coalesce(v_level_rewards->'unlocks', '[]'::jsonb)
        || coalesce(v_trophy_rewards->'unlocks', '[]'::jsonb);
    v_total_tokens := v_match_tokens + v_daily_tokens + v_level_bonus;

    update public.player_currency
    set gun_tokens = gun_tokens + v_total_tokens,
        updated_at = now()
    where player_id = p_player_id
    returning gun_tokens into v_balance;

    insert into public.wallet_ledger (
        player_id, match_id, amount, reason, balance_after
    ) values (
        p_player_id, p_match_id, v_total_tokens,
        'official_classic_match', v_balance
    );

    v_breakdown := jsonb_build_object(
        'xp_breakdown', jsonb_build_object(
            'participation', v_xp_participation,
            'round_wins', v_xp_rounds,
            'placement', v_xp_placement,
            'eliminations', v_xp_kills,
            'disarms', v_xp_disarms,
            'first_official_win', v_daily_xp
        ),
        'token_breakdown', jsonb_build_object(
            'placement', v_match_tokens,
            'first_official_win', v_daily_tokens
        ),
        'match_xp_delta', v_match_xp,
        'season_xp_delta', v_season_xp_award,
        'career_xp_delta', v_match_xp,
        'daily_victory_bonus_awarded', v_daily_awarded,
        'daily_victory_bonus_date', v_daily_date,
        'daily_victory_bonus_xp', v_daily_xp,
        'daily_victory_bonus_tokens', v_daily_tokens,
        'level_road_tokens', v_level_bonus,
        'unlocks', v_unlocks,
        'new_season_level', v_new_level,
        'new_season_xp', v_season_xp,
        'next_level_xp', public.one_gun_season_xp_required(v_new_level),
        'new_season_prestige', (greatest(v_new_level, 1) - 1) / 100,
        'new_season_trophies', v_new_trophies,
        'new_gun_token_balance', v_balance,
        'new_career_level', v_career_levels + 1,
        'new_career_xp', v_career_xp,
        'next_career_level_xp', public.one_gun_career_xp_required(v_career_levels + 1),
        'new_career_prestige', v_career_levels / 100,
        'new_lifetime_level', v_career_levels + 1,
        'new_lifetime_prestige', v_career_levels / 100
    );

    insert into public.match_rewards (
        match_id, player_id, season_id, actor_id, mode, map_id,
        placement, round_wins, kills, deaths, disarms,
        xp_delta, gun_tokens_delta, trophy_delta, eligible, breakdown
    ) values (
        p_match_id, p_player_id, v_season_id, v_confirmation.actor_id,
        v_match.mode, v_match.map_id, v_placement, v_round_wins,
        v_kills, v_deaths, v_disarms, v_season_xp_award, v_total_tokens,
        v_trophy, true, v_breakdown
    );

    return public.one_gun_reward_receipt_json(p_match_id, p_player_id);
end;
$$;

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
        'match_xp_delta', coalesce((reward.breakdown->>'match_xp_delta')::integer, reward.xp_delta),
        'season_xp_delta', coalesce((reward.breakdown->>'season_xp_delta')::integer, reward.xp_delta),
        'career_xp_delta', coalesce((reward.breakdown->>'career_xp_delta')::integer, reward.xp_delta),
        'gun_tokens_delta', reward.gun_tokens_delta,
        'trophy_delta', reward.trophy_delta,
        'breakdown', reward.breakdown,
        'xp_breakdown', coalesce(reward.breakdown->'xp_breakdown', '{}'::jsonb),
        'token_breakdown', coalesce(reward.breakdown->'token_breakdown', '{}'::jsonb),
        'daily_victory_bonus_awarded', coalesce((reward.breakdown->>'daily_victory_bonus_awarded')::boolean, false),
        'daily_victory_bonus_date', reward.breakdown->>'daily_victory_bonus_date',
        'daily_victory_bonus_xp', coalesce((reward.breakdown->>'daily_victory_bonus_xp')::integer, 0),
        'daily_victory_bonus_tokens', coalesce((reward.breakdown->>'daily_victory_bonus_tokens')::integer, 0),
        'unlocks', coalesce(reward.breakdown->'unlocks', '[]'::jsonb),
        'level_road_tokens', coalesce((reward.breakdown->>'level_road_tokens')::integer, 0),
        'new_season_level', coalesce((reward.breakdown->>'new_season_level')::integer, 1),
        'new_season_xp', coalesce((reward.breakdown->>'new_season_xp')::integer, 0),
        'next_level_xp', coalesce((reward.breakdown->>'next_level_xp')::integer, 150),
        'new_season_prestige', coalesce((reward.breakdown->>'new_season_prestige')::integer, 0),
        'new_season_trophies', coalesce((reward.breakdown->>'new_season_trophies')::integer, 0),
        'new_gun_token_balance', coalesce((reward.breakdown->>'new_gun_token_balance')::bigint, 0),
        'new_career_level', coalesce((reward.breakdown->>'new_career_level')::integer, 1),
        'new_career_xp', coalesce((reward.breakdown->>'new_career_xp')::integer, 0),
        'next_career_level_xp', coalesce((reward.breakdown->>'next_career_level_xp')::integer, 400),
        'new_career_prestige', coalesce((reward.breakdown->>'new_career_prestige')::integer, 0),
        'new_lifetime_level', coalesce((reward.breakdown->>'new_career_level')::integer, 1),
        'new_lifetime_prestige', coalesce((reward.breakdown->>'new_career_prestige')::integer, 0)
    )
    from public.match_rewards reward
    where reward.match_id = p_match_id and reward.player_id = p_player_id;
$$;

alter function public.get_player_progression()
    rename to one_gun_get_player_progression_before_daily_bonus;

create or replace function public.get_player_progression()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_payload jsonb;
    v_player_id uuid := auth.uid();
    v_season_level integer;
    v_career_levels integer;
    v_daily_claimed boolean;
begin
    if v_player_id is null then
        raise exception 'Authentication is required.';
    end if;

    v_payload := public.one_gun_get_player_progression_before_daily_bonus();
    v_season_level := greatest(coalesce((v_payload#>>'{progress,season_level}')::integer, 1), 1);
    v_career_levels := greatest(coalesce((v_payload#>>'{career,levels_earned}')::integer, 0), 0);
    select exists (
        select 1 from public.player_daily_victory_bonuses bonus
        where bonus.player_id = v_player_id
          and bonus.bonus_date = (timezone('UTC', now()))::date
    ) into v_daily_claimed;

    v_payload := jsonb_set(
        v_payload, '{progress,next_level_xp}',
        to_jsonb(public.one_gun_season_xp_required(v_season_level)), true
    );
    v_payload := jsonb_set(
        v_payload, '{progress,season_prestige}',
        to_jsonb((v_season_level - 1) / 100), true
    );
    v_payload := jsonb_set(
        v_payload, '{progress,daily_victory_bonus_claimed}',
        to_jsonb(v_daily_claimed), true
    );
    v_payload := jsonb_set(
        v_payload, '{progress,daily_victory_bonus_reset}',
        to_jsonb('00:00 UTC'::text), true
    );
    v_payload := jsonb_set(
        v_payload, '{career,next_level_xp}',
        to_jsonb(public.one_gun_career_xp_required(v_career_levels + 1)), true
    );
    v_payload := jsonb_set(
        v_payload, '{career,career_level}',
        to_jsonb(v_career_levels + 1), true
    );
    v_payload := jsonb_set(
        v_payload, '{career,career_prestige}',
        to_jsonb(v_career_levels / 100), true
    );
    v_payload := jsonb_set(
        v_payload, '{career,lifetime_level}',
        to_jsonb(v_career_levels + 1), true
    );

    return v_payload;
end;
$$;

revoke all on function public.one_gun_season_xp_required(integer) from public, anon, authenticated;
revoke all on function public.one_gun_career_xp_required(integer) from public, anon, authenticated;
revoke all on function public.one_gun_xp_required(integer) from public, anon, authenticated;
revoke all on function public.one_gun_award_confirmed_player(text, uuid) from public, anon, authenticated;
revoke all on function public.one_gun_reward_receipt_json(text, uuid) from public, anon, authenticated;
revoke all on function public.one_gun_get_player_progression_before_daily_bonus() from public, anon, authenticated;
revoke all on function public.get_player_progression() from public, anon;
grant execute on function public.get_player_progression() to authenticated;

commit;

notify pgrst, 'reload schema';
