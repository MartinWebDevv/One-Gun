-- One Gun social graph, friend-only presence, and short-lived lobby invites.
-- Persistent relationships live in Supabase; lobby transport remains ENet over
-- Tailscale. Direct table access is intentionally revoked so a client can only
-- see identities and endpoints exposed by the participant-checked RPCs below.

begin;

create table if not exists public.player_friendships (
    user_low uuid not null references auth.users(id) on delete cascade,
    user_high uuid not null references auth.users(id) on delete cascade,
    requested_by uuid not null references auth.users(id) on delete cascade,
    state text not null default 'pending'
        check (state in ('pending', 'accepted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    responded_at timestamptz,
    primary key (user_low, user_high),
    check (user_low < user_high),
    check (requested_by = user_low or requested_by = user_high)
);

create table if not exists public.player_presence (
    user_id uuid primary key references auth.users(id) on delete cascade,
    activity text not null default 'home'
        check (activity in ('home', 'lobby', 'playpen', 'match')),
    lobby_name text,
    lobby_address text,
    lobby_port integer check (lobby_port is null or lobby_port between 1 and 65535),
    joinable boolean not null default false,
    updated_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '90 seconds'),
    check (length(coalesce(lobby_name, '')) <= 32),
    check (length(coalesce(lobby_address, '')) <= 64)
);

create table if not exists public.player_lobby_invites (
    id uuid primary key default extensions.gen_random_uuid(),
    sender_id uuid not null references auth.users(id) on delete cascade,
    receiver_id uuid not null references auth.users(id) on delete cascade,
    lobby_name text not null,
    lobby_address text not null,
    lobby_port integer not null check (lobby_port between 1 and 65535),
    status text not null default 'pending'
        check (status in ('pending', 'accepted', 'declined', 'expired')),
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '5 minutes'),
    responded_at timestamptz,
    check (sender_id <> receiver_id),
    check (length(lobby_name) between 1 and 32),
    check (length(lobby_address) between 3 and 64)
);

create index if not exists player_friendships_high_state_idx
    on public.player_friendships (user_high, state);
create index if not exists player_friendships_low_state_idx
    on public.player_friendships (user_low, state);
create index if not exists player_lobby_invites_receiver_idx
    on public.player_lobby_invites (receiver_id, status, expires_at desc);
create index if not exists player_presence_expiry_idx
    on public.player_presence (expires_at);

alter table public.player_friendships enable row level security;
alter table public.player_presence enable row level security;
alter table public.player_lobby_invites enable row level security;

revoke all on table public.player_friendships from public, anon, authenticated;
revoke all on table public.player_presence from public, anon, authenticated;
revoke all on table public.player_lobby_invites from public, anon, authenticated;


create or replace function public.send_friend_request(p_account_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_target_id uuid;
    v_low uuid;
    v_high uuid;
    v_existing public.player_friendships%rowtype;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    select id into v_target_id
    from public.profiles
    where lower(username) = lower(btrim(coalesce(p_account_name, '')))
      and username is not null
    limit 1;
    if v_target_id is null then
        raise exception 'No player has that exact Account Name.';
    end if;
    if v_target_id = v_user_id then
        raise exception 'You cannot add yourself as a friend.';
    end if;
    v_low := least(v_user_id, v_target_id);
    v_high := greatest(v_user_id, v_target_id);
    select * into v_existing from public.player_friendships
    where user_low = v_low and user_high = v_high;
    if found then
        if v_existing.state = 'accepted' then
            return jsonb_build_object('ok', true, 'state', 'accepted',
                'user_id', v_target_id, 'message', 'You are already friends.');
        end if;
        return jsonb_build_object(
            'ok', true,
            'state', case when v_existing.requested_by = v_user_id
                then 'outgoing' else 'incoming' end,
            'user_id', v_target_id,
            'message', case when v_existing.requested_by = v_user_id
                then 'Friend request already sent.'
                else 'This player already sent you a friend request.' end
        );
    end if;
    insert into public.player_friendships (
        user_low, user_high, requested_by, state
    ) values (v_low, v_high, v_user_id, 'pending');
    return jsonb_build_object('ok', true, 'state', 'outgoing',
        'user_id', v_target_id, 'message', 'Friend request sent.');
end;
$$;


create or replace function public.respond_friend_request(
    p_requester_id uuid, p_accept boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_low uuid;
    v_high uuid;
    v_request public.player_friendships%rowtype;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    if p_requester_id is null or p_requester_id = v_user_id then
        raise exception 'That friend request is invalid.';
    end if;
    v_low := least(v_user_id, p_requester_id);
    v_high := greatest(v_user_id, p_requester_id);
    select * into v_request from public.player_friendships
    where user_low = v_low and user_high = v_high
      and state = 'pending' and requested_by = p_requester_id
    for update;
    if not found then
        raise exception 'That incoming friend request is no longer pending.';
    end if;
    if p_accept then
        update public.player_friendships
        set state = 'accepted', updated_at = now(), responded_at = now()
        where user_low = v_low and user_high = v_high;
    else
        delete from public.player_friendships
        where user_low = v_low and user_high = v_high;
    end if;
    return jsonb_build_object('ok', true,
        'state', case when p_accept then 'accepted' else 'denied' end,
        'user_id', p_requester_id);
end;
$$;


create or replace function public.remove_friend(p_friend_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_deleted integer;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    delete from public.player_friendships
    where user_low = least(v_user_id, p_friend_id)
      and user_high = greatest(v_user_id, p_friend_id)
      and state = 'accepted';
    get diagnostics v_deleted = row_count;
    if v_deleted = 0 then
        raise exception 'That player is not in your friends list.';
    end if;
    return jsonb_build_object('ok', true, 'state', 'removed',
        'user_id', p_friend_id);
end;
$$;


create or replace function public.set_social_presence(
    p_activity text,
    p_lobby_name text default null,
    p_lobby_address text default null,
    p_lobby_port integer default null,
    p_joinable boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_activity text := lower(btrim(coalesce(p_activity, 'home')));
    v_name text := nullif(left(btrim(coalesce(p_lobby_name, '')), 32), '');
    v_address text := nullif(left(btrim(coalesce(p_lobby_address, '')), 64), '');
    v_joinable boolean := coalesce(p_joinable, false);
    v_address_value inet;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    if v_activity not in ('home', 'lobby', 'playpen', 'match') then
        raise exception 'Invalid presence activity.';
    end if;
    if v_joinable then
        if v_name is null or v_address is null
           or p_lobby_port is null or p_lobby_port not between 1 and 65535 then
            raise exception 'Joinable presence requires a complete lobby endpoint.';
        end if;
        begin
            v_address_value := v_address::inet;
        exception when others then
            raise exception 'Lobby address must be a valid Tailscale or localhost IP.';
        end;
        if not (v_address_value <<= inet '100.64.0.0/10'
                or v_address_value <<= inet '127.0.0.0/8') then
            raise exception 'Lobby address must use Tailscale or localhost.';
        end if;
    else
        v_name := null;
        v_address := null;
        p_lobby_port := null;
    end if;
    insert into public.player_presence (
        user_id, activity, lobby_name, lobby_address, lobby_port,
        joinable, updated_at, expires_at
    ) values (
        v_user_id, v_activity, v_name, v_address, p_lobby_port,
        v_joinable, now(), now() + interval '90 seconds'
    ) on conflict (user_id) do update set
        activity = excluded.activity,
        lobby_name = excluded.lobby_name,
        lobby_address = excluded.lobby_address,
        lobby_port = excluded.lobby_port,
        joinable = excluded.joinable,
        updated_at = now(),
        expires_at = now() + interval '90 seconds';
    return jsonb_build_object('ok', true, 'activity', v_activity,
        'joinable', v_joinable, 'expires_at', now() + interval '90 seconds');
end;
$$;


create or replace function public.clear_social_presence()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
begin
    if v_user_id is not null then
        delete from public.player_presence where user_id = v_user_id;
    end if;
    return jsonb_build_object('ok', true);
end;
$$;


create or replace function public.send_lobby_invite(p_receiver_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_presence public.player_presence%rowtype;
    v_invite public.player_lobby_invites%rowtype;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    if not exists (
        select 1 from public.player_friendships friendship
        where friendship.user_low = least(v_user_id, p_receiver_id)
          and friendship.user_high = greatest(v_user_id, p_receiver_id)
          and friendship.state = 'accepted'
    ) then
        raise exception 'Lobby invites can only be sent to accepted friends.';
    end if;
    select * into v_presence from public.player_presence
    where user_id = v_user_id and joinable and expires_at > now();
    if not found then
        raise exception 'Enter a joinable online lobby before inviting friends.';
    end if;
    update public.player_lobby_invites
    set status = 'expired', responded_at = now()
    where sender_id = v_user_id and receiver_id = p_receiver_id
      and status = 'pending';
    insert into public.player_lobby_invites (
        sender_id, receiver_id, lobby_name, lobby_address, lobby_port
    ) values (
        v_user_id, p_receiver_id, v_presence.lobby_name,
        v_presence.lobby_address, v_presence.lobby_port
    ) returning * into v_invite;
    return jsonb_build_object('ok', true, 'id', v_invite.id,
        'status', v_invite.status, 'expires_at', v_invite.expires_at);
end;
$$;


create or replace function public.respond_lobby_invite(
    p_invite_id uuid, p_accept boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_invite public.player_lobby_invites%rowtype;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    select * into v_invite from public.player_lobby_invites
    where id = p_invite_id and receiver_id = v_user_id
      and status = 'pending'
    for update;
    if not found or v_invite.expires_at <= now() then
        if found then
            update public.player_lobby_invites
            set status = 'expired', responded_at = now()
            where id = p_invite_id;
        end if;
        raise exception 'That lobby invitation has expired.';
    end if;
    update public.player_lobby_invites
    set status = case when p_accept then 'accepted' else 'declined' end,
        responded_at = now()
    where id = p_invite_id;
    return jsonb_build_object(
        'ok', true,
        'id', v_invite.id,
        'status', case when p_accept then 'accepted' else 'declined' end,
        'lobby_name', v_invite.lobby_name,
        'lobby_address', v_invite.lobby_address,
        'lobby_port', v_invite.lobby_port
    );
end;
$$;


create or replace function public.get_social_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid := auth.uid();
    v_result jsonb;
begin
    if v_user_id is null then
        raise exception 'Authentication is required.';
    end if;
    update public.player_lobby_invites
    set status = 'expired', responded_at = now()
    where receiver_id = v_user_id and status = 'pending' and expires_at <= now();

    select jsonb_build_object(
        'friends', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', friend.friend_id,
                'username', coalesce(profile.username, 'PLAYER'),
                'online', presence.user_id is not null and presence.expires_at > now(),
                'activity', case when presence.expires_at > now()
                    then presence.activity else 'offline' end,
                'lobby_name', case when presence.expires_at > now()
                    then coalesce(presence.lobby_name, '') else '' end,
                'lobby_address', case when presence.expires_at > now()
                    then coalesce(presence.lobby_address, '') else '' end,
                'lobby_port', case when presence.expires_at > now()
                    then coalesce(presence.lobby_port, 0) else 0 end,
                'joinable', coalesce(presence.joinable, false)
                    and presence.expires_at > now(),
                'last_seen_at', presence.updated_at
            ) order by (presence.user_id is not null and presence.expires_at > now()) desc,
                lower(coalesce(profile.username, 'PLAYER')))
            from (
                select case when friendship.user_low = v_user_id
                        then friendship.user_high else friendship.user_low end as friend_id
                from public.player_friendships friendship
                where friendship.state = 'accepted'
                  and (friendship.user_low = v_user_id or friendship.user_high = v_user_id)
            ) friend
            left join public.profiles profile on profile.id = friend.friend_id
            left join public.player_presence presence on presence.user_id = friend.friend_id
        ), '[]'::jsonb),
        'incoming_requests', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', friendship.requested_by,
                'username', coalesce(profile.username, 'PLAYER'),
                'created_at', friendship.created_at
            ) order by friendship.created_at desc)
            from public.player_friendships friendship
            left join public.profiles profile on profile.id = friendship.requested_by
            where friendship.state = 'pending'
              and friendship.requested_by <> v_user_id
              and (friendship.user_low = v_user_id or friendship.user_high = v_user_id)
        ), '[]'::jsonb),
        'outgoing_requests', coalesce((
            select jsonb_agg(jsonb_build_object(
                'user_id', case when friendship.user_low = v_user_id
                    then friendship.user_high else friendship.user_low end,
                'username', coalesce(profile.username, 'PLAYER'),
                'created_at', friendship.created_at
            ) order by friendship.created_at desc)
            from public.player_friendships friendship
            left join public.profiles profile on profile.id = case
                when friendship.user_low = v_user_id
                    then friendship.user_high else friendship.user_low end
            where friendship.state = 'pending'
              and friendship.requested_by = v_user_id
        ), '[]'::jsonb),
        'invites', coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', invite.id,
                'sender_id', invite.sender_id,
                'username', coalesce(profile.username, 'PLAYER'),
                'lobby_name', invite.lobby_name,
                'lobby_address', invite.lobby_address,
                'lobby_port', invite.lobby_port,
                'created_at', invite.created_at,
                'expires_at', invite.expires_at
            ) order by invite.created_at desc)
            from public.player_lobby_invites invite
            left join public.profiles profile on profile.id = invite.sender_id
            where invite.receiver_id = v_user_id
              and invite.status = 'pending' and invite.expires_at > now()
        ), '[]'::jsonb),
        'server_time', now()
    ) into v_result;
    return v_result;
end;
$$;


revoke all on function public.send_friend_request(text) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.remove_friend(uuid) from public, anon;
revoke all on function public.set_social_presence(text, text, text, integer, boolean) from public, anon;
revoke all on function public.clear_social_presence() from public, anon;
revoke all on function public.send_lobby_invite(uuid) from public, anon;
revoke all on function public.respond_lobby_invite(uuid, boolean) from public, anon;
revoke all on function public.get_social_snapshot() from public, anon;

grant execute on function public.send_friend_request(text) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.remove_friend(uuid) to authenticated;
grant execute on function public.set_social_presence(text, text, text, integer, boolean) to authenticated;
grant execute on function public.clear_social_presence() to authenticated;
grant execute on function public.send_lobby_invite(uuid) to authenticated;
grant execute on function public.respond_lobby_invite(uuid, boolean) to authenticated;
grant execute on function public.get_social_snapshot() to authenticated;

notify pgrst, 'reload schema';
commit;
