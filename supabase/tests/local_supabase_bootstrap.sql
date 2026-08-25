\set ON_ERROR_STOP on

-- Minimal Supabase compatibility surface for disposable plain-PostgreSQL
-- migration tests. This file never runs against the linked project.

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'service_role') then
        create role service_role nologin;
    end if;
end;
$$;

create schema if not exists auth;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table if not exists auth.users (
    id uuid primary key
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth, extensions to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
