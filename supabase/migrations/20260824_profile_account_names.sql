-- One Gun: unique Account Names and a server-enforced 14-day rename cooldown.
-- Account Name is intentionally separate from the freely editable in-game
-- Display Name stored by Godot. No service-role credential belongs in clients.

begin;

alter table public.profiles
    add column if not exists username_changed_at timestamptz;

update public.profiles
set username = null
where username is not null
  and (btrim(username) = ''
       or lower(btrim(username)) in ('null', '<null>'));

-- Account Names are case-insensitively unique. Existing non-empty duplicate
-- names must be resolved before this migration can be applied.
create unique index if not exists profiles_username_lower_unique
    on public.profiles (lower(username))
    where username is not null;

create or replace function public.claim_profile_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_username text := btrim(coalesce(p_username, ''));
    v_existing text;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;

    if v_username !~ '^[A-Za-z0-9][A-Za-z0-9_]{2,19}$' then
        raise exception 'Account Name must be 3–20 characters using letters, numbers, or underscores.';
    end if;

    if exists (
        select 1
        from public.profiles
        where lower(username) = lower(v_username)
          and id <> v_user_id
    ) then
        raise exception 'That Account Name is already taken.';
    end if;

    select username
    into v_existing
    from public.profiles
    where id = v_user_id
    for update;

    if coalesce(btrim(v_existing), '') <> '' then
        return jsonb_build_object(
            'ok', true,
            'username', v_existing,
            'claimed', false
        );
    end if;

    insert into public.profiles (
        id, username, created_at, updated_at, username_changed_at
    ) values (
        v_user_id, v_username, now(), now(), now()
    )
    on conflict (id) do update set
        username = excluded.username,
        updated_at = now(),
        username_changed_at = coalesce(public.profiles.username_changed_at, now());

    return jsonb_build_object(
        'ok', true,
        'username', v_username,
        'claimed', true
    );
end;
$$;

create or replace function public.rename_profile_username(p_username text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_username text := btrim(coalesce(p_username, ''));
    v_current_username text;
    v_changed_at timestamptz;
    v_next_change_at timestamptz;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;

    if v_username !~ '^[A-Za-z0-9][A-Za-z0-9_]{2,19}$' then
        raise exception 'Account Name must be 3–20 characters using letters, numbers, or underscores.';
    end if;

    select username, username_changed_at
    into v_current_username, v_changed_at
    from public.profiles
    where id = v_user_id
    for update;

    if not found or coalesce(btrim(v_current_username), '') = '' then
        raise exception 'Choose the initial Account Name before renaming it.';
    end if;

    if lower(v_current_username) = lower(v_username) then
        return jsonb_build_object(
            'ok', true,
            'username', v_current_username,
            'changed', false,
            'next_change_at', v_changed_at + interval '14 days'
        );
    end if;

    v_next_change_at := v_changed_at + interval '14 days';
    if v_changed_at is not null and now() < v_next_change_at then
        raise exception 'Account Name can be changed again on %.',
            to_char(v_next_change_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI UTC');
    end if;

    if exists (
        select 1
        from public.profiles
        where lower(username) = lower(v_username)
          and id <> v_user_id
    ) then
        raise exception 'That Account Name is already taken.';
    end if;

    update public.profiles
    set username = v_username,
        username_changed_at = now(),
        updated_at = now()
    where id = v_user_id;

    return jsonb_build_object(
        'ok', true,
        'username', v_username,
        'changed', true,
        'next_change_at', now() + interval '14 days'
    );
end;
$$;

revoke all on function public.claim_profile_username(text) from public, anon;
revoke all on function public.rename_profile_username(text) from public, anon;
grant execute on function public.claim_profile_username(text) to authenticated;
grant execute on function public.rename_profile_username(text) to authenticated;

commit;
