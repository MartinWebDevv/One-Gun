import { readFile } from 'node:fs/promises';
import { PGlite } from '../artifacts/course_cloud_validation/db/node_modules/@electric-sql/pglite/dist/index.js';
const db = new PGlite();
try {
  await db.exec(`create role anon nologin; create role authenticated nologin;
    create schema auth; create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
    $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
    grant usage on schema auth to anon,authenticated;
    grant execute on function auth.uid() to anon,authenticated;`);
  const migration = await readFile(new URL('../supabase/migrations/20260910_agility_personal_bests.sql',import.meta.url),'utf8');
  await db.exec(migration);
  const result = await db.exec(await readFile(new URL('../supabase/tests/agility_personal_bests_test.sql',import.meta.url),'utf8'));
  console.log(result.at(-1).rows);
  await db.exec(migration);
  const preserved = await db.query('select count(*)::int as count from public.agility_personal_best_history');
  if (preserved.rows[0].count !== 4) throw new Error('Migration rerun changed history');
  console.log('PASS: migration rerun preserves records and history');
} finally { await db.close(); }
