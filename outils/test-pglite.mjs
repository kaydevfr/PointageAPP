// Exécute migrations + seed + tests dans PGlite (Postgres WASM) avec PostGIS,
// en simulant l'environnement Supabase (rôles, auth.uid, pg_cron) et un mini pgTAP.
// Usage : npm test   (ou node outils/test-pglite.mjs)
// Vérification rapide SANS Docker. Ne remplace pas « supabase test db » (vrai Supabase + vrai pgTAP).
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const supa = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'supabase');

const { PGlite } = await import('@electric-sql/pglite');
const { postgis } = await import('@electric-sql/pglite-postgis');

const db = new PGlite({ extensions: { postgis } });

const env = `
create schema extensions;
grant usage on schema extensions to public;
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
-- défauts Supabase (que la migration 08 doit annuler)
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
create schema auth; grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key, email text, aud text, role text);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $$;
grant execute on function auth.uid() to public;
create schema cron;
create function cron.schedule(text, text, text) returns bigint language sql as $$ select 1::bigint $$;
alter database template1 set search_path = public, extensions;
set search_path = public, extensions;

-- mini pgTAP
create function extensions.no_plan() returns setof boolean language sql as $$ select true where false $$;
create function extensions.finish() returns setof text language sql as $$ select null::text where false $$;
create function extensions.ok(b boolean, d text default '') returns text language sql as
  $$ select case when b then 'ok - ' else 'not ok - ' end || d $$;
create function extensions.is(a anyelement, b anyelement, d text default '') returns text language sql as
  $$ select case when a is not distinct from b then 'ok - ' || d
                 else 'not ok - ' || d || '  [got: ' || coalesce(a::text,'NULL') || ' | want: ' || coalesce(b::text,'NULL') || ']' end $$;
create function extensions.isnt(a anyelement, b anyelement, d text default '') returns text language sql as
  $$ select case when a is distinct from b then 'ok - ' else 'not ok - ' end || d $$;
create function extensions.results_eq(q1 text, q2 text, d text default '') returns text language plpgsql as $$
declare a text[]; b text[];
begin
  execute format('select array_agg(t::text) from (%s) t', q1) into a;
  execute format('select array_agg(t::text) from (%s) t', q2) into b;
  if a is not distinct from b then return 'ok - ' || d; end if;
  return 'not ok - ' || d || '  [got: ' || coalesce(a::text,'NULL') || ' | want: ' || coalesce(b::text,'NULL') || ']';
end $$;
create function extensions.is_empty(q text, d text default '') returns text language plpgsql as $$
declare n int;
begin
  execute format('select count(*) from (%s) t', q) into n;
  return case when n = 0 then 'ok - ' || d else 'not ok - ' || d || '  [' || n || ' rows]' end;
end $$;
create function extensions.throws_ok(q text, code text, msg text, d text default '') returns text language plpgsql as $$
begin
  execute q;
  return 'not ok - ' || d || '  [no error]';
exception when others then
  return case when sqlstate = code then 'ok - ' || d
              else 'not ok - ' || d || '  [' || sqlstate || ': ' || sqlerrm || ']' end;
end $$;
create function extensions.lives_ok(q text, d text default '') returns text language plpgsql as $$
begin
  execute q;
  return 'ok - ' || d;
exception when others then
  return 'not ok - ' || d || '  [' || sqlstate || ': ' || sqlerrm || ']';
end $$;
`;

const run = async (label, sql) => {
  try { return await db.exec(sql); }
  catch (e) { console.log(`ERREUR dans ${label}: ${e.message}`); if (e.position) console.log('  position', e.position, JSON.stringify(sql.slice(Math.max(0, e.position - 120), Number(e.position) + 60))); throw e; }
};

await run('env', env);
await run('postgis', 'create extension postgis with schema extensions;');

const migDir = path.join(supa, 'migrations');
for (const f of fs.readdirSync(migDir).sort()) {
  let sql = fs.readFileSync(path.join(migDir, f), 'utf8')
    .replace(/create extension if not exists pg_cron;/, '')
    .replace(/create extension if not exists postgis with schema extensions;/, '');
  await run(f, sql);
  console.log('migration OK', f);
}
await run('seed', fs.readFileSync(path.join(supa, 'seed.sql'), 'utf8'));
const n = await db.query('select count(*)::int n from public.pointages');
console.log('seed OK, pointages du jour générés :', n.rows[0].n);

let total = 0, failed = 0;
const testDir = path.join(supa, 'tests');
for (const f of fs.readdirSync(testDir).filter((x) => x.endsWith('.sql')).sort()) {
  const sql = fs.readFileSync(path.join(testDir, f), 'utf8')
    .replace(/create extension if not exists pgtap with schema extensions;/, '');
  let res;
  try { res = await run(f, sql); } catch { failed++; try { await db.exec('rollback'); } catch {} continue; }
  const lines = res.flatMap((r) => r.rows.flatMap((row) => Object.values(row)))
    .filter((v) => typeof v === 'string' && /^(not )?ok - /.test(v));
  const ko = lines.filter((l) => l.startsWith('not ok'));
  total += lines.length; failed += ko.length;
  console.log(`${ko.length ? 'FAIL' : 'PASS'} ${f} (${lines.length - ko.length}/${lines.length})`);
  ko.forEach((l) => console.log('   ', l));
}
console.log(`\nTotal : ${total - failed}/${total} assertions OK`);
process.exit(failed ? 1 : 0);
