begin;

-- The Winners Circle adds local_peer_id only so each client can highlight its
-- own row and Ready button. It is not match evidence. Older clients submitted
-- that per-viewer value as part of p_result, causing otherwise identical
-- confirmations to hash differently and preventing settlement.
alter function public.confirm_official_beta_match(text, integer, text, jsonb)
    rename to one_gun_confirm_official_beta_match_uncanonicalized;

revoke all on function public.one_gun_confirm_official_beta_match_uncanonicalized(
    text, integer, text, jsonb
) from public, anon, authenticated;

create or replace function public.confirm_official_beta_match(
    p_match_id text,
    p_actor_id integer,
    p_claim_secret text,
    p_result jsonb
)
returns jsonb
language sql
security definer
set search_path = public, extensions
as $$
    select public.one_gun_confirm_official_beta_match_uncanonicalized(
        p_match_id,
        p_actor_id,
        p_claim_secret,
        coalesce(p_result, '{}'::jsonb) - 'local_peer_id'
    );
$$;

revoke all on function public.confirm_official_beta_match(
    text, integer, text, jsonb
) from public, anon;
grant execute on function public.confirm_official_beta_match(
    text, integer, text, jsonb
) to authenticated;

comment on function public.confirm_official_beta_match(text, integer, text, jsonb)
    is 'Confirms an Official Beta result after removing client-local presentation fields.';

notify pgrst, 'reload schema';
commit;

