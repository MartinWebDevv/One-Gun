-- Run only in the disposable PostgreSQL database created by run_course_database_test.mjs.
insert into auth.users(id) values
('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222') on conflict do nothing;
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.sync_agility_personal_bests('{
 "flow_circuit_v2/dash3/sprint0/jump7.000/standard":11002,
 "flow_circuit_v3/dash3/sprint0/jump7.000/standard":10841,
 "flow_circuit_v2/dash3/sprint0/jump7.000/powerup":9283
}'::jsonb);
do $$
declare r jsonb;
begin
 r:=public.sync_agility_personal_bests('{}');
 assert r->'bests'->>'flow_circuit_v3/dash3/sprint0/jump7.000/standard'='10841','legacy/new minimum lost';
 assert r->'bests'->>'flow_circuit_v3/dash3/sprint0/jump7.000/powerup'='9283','legacy Power-Up lost';
 perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":12000}');
 r:=public.sync_agility_personal_bests('{}');
 assert r->'bests'->>'flow_circuit_v3/dash3/sprint0/jump7.000/standard'='10841','slower overwrite';
 begin
  perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":10000,"user_id":1000}');
  raise exception 'invalid owner key accepted';
 exception when sqlstate '22023' then null;
 end;
 r:=public.sync_agility_personal_bests('{}');
 assert r->'bests'->>'flow_circuit_v3/dash3/sprint0/jump7.000/standard'='10841','invalid batch partially committed';
 begin
  perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":1000.5}');
  raise exception 'fractional milliseconds accepted';
 exception when sqlstate '22023' then null;
 end;
 begin
  perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":-1}');
  raise exception 'negative time accepted';
 exception when sqlstate '22023' then null;
 end;
 begin
  delete from public.agility_personal_bests;
  raise exception 'client can delete records';
 exception when insufficient_privilege then null;
 end;
 begin
  select count(*) into r from public.agility_personal_bests;
  raise exception 'client can bypass account RPC';
 exception when insufficient_privilege then null;
 end;
 perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":10000}');
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $$
begin
 assert public.sync_agility_personal_bests('{}')->'bests'='{}'::jsonb,'account B sees account A';
 perform public.sync_agility_personal_bests('{"flow_circuit_v3/dash3/sprint0/jump7.000/standard":20000}');
 assert public.sync_agility_personal_bests('{}')->'bests'->>'flow_circuit_v3/dash3/sprint0/jump7.000/standard'='20000','account isolation failed';
end $$;
reset role;
set role anon;
do $$ begin
 begin
  perform public.sync_agility_personal_bests('{}');
  raise exception 'anonymous access permitted';
 exception when insufficient_privilege then null;
 end;
end $$;
reset role;
do $$ begin
 assert (select count(*) from public.agility_personal_bests)=3,'wrong PB row count';
 assert (select count(*) from public.agility_personal_best_history)=4,'history should record only actual improvements';
 assert (select count(*) from public.agility_personal_best_history where user_id='11111111-1111-4111-8111-111111111111' and bucket like '%/standard')=2,'original and improved Standard history missing';
 assert (select bool_and(relrowsecurity) from pg_class where oid in ('public.agility_personal_bests'::regclass,'public.agility_personal_best_history'::regclass)),'RLS disabled';
end $$;
select 'AGILITY_PERSONAL_BESTS_TESTS_OK' as result;
