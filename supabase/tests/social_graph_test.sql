\set ON_ERROR_STOP on

begin;

insert into auth.users (id) values
    ('30000000-0000-0000-0000-000000000001'),
    ('30000000-0000-0000-0000-000000000002'),
    ('30000000-0000-0000-0000-000000000003')
on conflict (id) do nothing;
insert into public.profiles (id, username) values
    ('30000000-0000-0000-0000-000000000001', 'SocialOne'),
    ('30000000-0000-0000-0000-000000000002', 'SocialTwo'),
    ('30000000-0000-0000-0000-000000000003', 'SocialThree')
on conflict (id) do update set username = excluded.username;

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000001', true);
select public.send_friend_request('socialtwo');

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000002', true);
do $$
declare v_snapshot jsonb := public.get_social_snapshot();
begin
    if jsonb_array_length(v_snapshot->'incoming_requests') <> 1
       or v_snapshot->'incoming_requests'->0->>'username' <> 'SocialOne' then
        raise exception 'Incoming friend request was not private and visible to its receiver';
    end if;
end;
$$;
select public.respond_friend_request(
    '30000000-0000-0000-0000-000000000001', false);

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000001', true);
select public.send_friend_request('SocialTwo');
select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000002', true);
select public.respond_friend_request(
    '30000000-0000-0000-0000-000000000001', true);
select public.set_social_presence('lobby', 'Social Lobby', '100.64.1.2', 24545, true);

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000001', true);
do $$
declare v_snapshot jsonb := public.get_social_snapshot();
begin
    if jsonb_array_length(v_snapshot->'friends') <> 1
       or not (v_snapshot->'friends'->0->>'online')::boolean
       or not (v_snapshot->'friends'->0->>'joinable')::boolean
       or v_snapshot->'friends'->0->>'lobby_address' <> '100.64.1.2' then
        raise exception 'Accepted friend presence did not expose the joinable Tailscale lobby';
    end if;
end;
$$;
select public.set_social_presence('lobby', 'Social One Lobby', '127.0.0.1', 24545, true);
select public.send_lobby_invite('30000000-0000-0000-0000-000000000002');

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000002', true);
do $$
declare
    v_snapshot jsonb := public.get_social_snapshot();
    v_invite_id uuid;
    v_receipt jsonb;
begin
    if jsonb_array_length(v_snapshot->'invites') <> 1
       or v_snapshot->'invites'->0->>'lobby_name' <> 'Social One Lobby' then
        raise exception 'Friend lobby invitation was not delivered';
    end if;
    v_invite_id := (v_snapshot->'invites'->0->>'id')::uuid;
    v_receipt := public.respond_lobby_invite(v_invite_id, true);
    if v_receipt->>'status' <> 'accepted'
       or v_receipt->>'lobby_address' <> '127.0.0.1' then
        raise exception 'Accepted invite did not return its ENet endpoint';
    end if;
end;
$$;

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000003', true);
select public.set_social_presence('home', null, null, null, false);
do $$
begin
    begin
        perform public.send_lobby_invite(
            '30000000-0000-0000-0000-000000000002');
        raise exception 'A non-friend was allowed to send a lobby invite';
    exception when others then
        if sqlerrm = 'A non-friend was allowed to send a lobby invite' then
            raise;
        end if;
    end;
end;
$$;

do $$
begin
    if has_table_privilege('authenticated', 'public.player_friendships', 'select')
       or has_table_privilege('authenticated', 'public.player_presence', 'select')
       or has_table_privilege('authenticated', 'public.player_lobby_invites', 'select') then
        raise exception 'Social tables leaked direct authenticated read access';
    end if;
end;
$$;

select set_config('request.jwt.claim.sub',
    '30000000-0000-0000-0000-000000000001', true);
select public.remove_friend('30000000-0000-0000-0000-000000000002');
do $$
begin
    if jsonb_array_length(public.get_social_snapshot()->'friends') <> 0 then
        raise exception 'Removing a friend did not clear the accepted relationship';
    end if;
end;
$$;

rollback;
