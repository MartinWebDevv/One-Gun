-- Account-owned backups of personal course receipts, not a verified world ranking.
begin;

create table if not exists public.agility_personal_bests (
    user_id uuid not null references auth.users(id) on delete cascade,
    bucket text not null check (bucket ~ '^flow_circuit_v3/dash[0-9]{1,2}/sprint[01]/jump[0-9]{1,3}[.][0-9]{3}/(standard|powerup|assisted)$'),
    time_ms integer not null check (time_ms between 1000 and 3600000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (user_id,bucket)
);
create table if not exists public.agility_personal_best_history (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    bucket text not null,
    time_ms integer not null check (time_ms between 1000 and 3600000),
    recorded_at timestamptz not null default now()
);
create index if not exists agility_history_user_bucket on public.agility_personal_best_history(user_id,bucket,recorded_at);
alter table public.agility_personal_bests enable row level security;
alter table public.agility_personal_best_history enable row level security;
revoke all on public.agility_personal_bests, public.agility_personal_best_history from public,anon,authenticated;
revoke all on sequence public.agility_personal_best_history_id_seq from public,anon,authenticated;

create or replace function public.record_agility_best_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    insert into public.agility_personal_best_history(user_id,bucket,time_ms)
    values (new.user_id,new.bucket,new.time_ms);
    return new;
end;
$$;
revoke all on function public.record_agility_best_history() from public,anon,authenticated;
drop trigger if exists agility_best_insert_history on public.agility_personal_bests;
create trigger agility_best_insert_history after insert on public.agility_personal_bests
    for each row execute function public.record_agility_best_history();
drop trigger if exists agility_best_update_history on public.agility_personal_bests;
create trigger agility_best_update_history after update on public.agility_personal_bests
    for each row when (new.time_ms < old.time_ms) execute function public.record_agility_best_history();

create or replace function public.sync_agility_personal_bests(p_bests jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    player uuid := auth.uid();
    entry record;
    result jsonb;
begin
    if player is null then raise exception 'Sign in to sync course records' using errcode='42501'; end if;
    if p_bests is null or jsonb_typeof(p_bests) <> 'object' then
        raise exception 'Expected a personal best object' using errcode='22023';
    end if;
    if (select count(*) from jsonb_object_keys(p_bests)) > 128 then
        raise exception 'Too many course records' using errcode='22023';
    end if;
    for entry in select key,value from jsonb_each(p_bests) loop
        if entry.key !~ '^flow_circuit_v[23]/dash[0-9]{1,2}/sprint[01]/jump[0-9]{1,3}[.][0-9]{3}/(standard|powerup|assisted)$'
            or jsonb_typeof(entry.value) <> 'number' then
            raise exception 'Invalid course record' using errcode='22023';
        end if;
        if (entry.value::text)::numeric < 1000 or (entry.value::text)::numeric > 3600000
            or (entry.value::text)::numeric <> trunc((entry.value::text)::numeric) then
            raise exception 'Invalid course time' using errcode='22023';
        end if;
    end loop;
    -- Serialize this account's imports, including two devices reconnecting together.
    perform pg_advisory_xact_lock(hashtextextended(player::text, 413));
    if (select count(*) from public.agility_personal_bests where user_id=player) +
       (select count(*) from jsonb_object_keys(p_bests)) > 1024 then
        raise exception 'Course record limit reached' using errcode='22023';
    end if;
    insert into public.agility_personal_bests(user_id,bucket,time_ms)
    select player,regexp_replace(key,'^flow_circuit_v2/','flow_circuit_v3/'),min((value::text)::numeric)::integer
    from jsonb_each(p_bests) group by regexp_replace(key,'^flow_circuit_v2/','flow_circuit_v3/')
    on conflict(user_id,bucket) do update set time_ms=excluded.time_ms,updated_at=now()
    where excluded.time_ms < public.agility_personal_bests.time_ms;
    select coalesce(jsonb_object_agg(bucket,time_ms),'{}'::jsonb) into result
    from public.agility_personal_bests where user_id=player;
    return jsonb_build_object('version',1,'bests',result);
end;
$$;
revoke all on function public.sync_agility_personal_bests(jsonb) from public,anon;
grant execute on function public.sync_agility_personal_bests(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
