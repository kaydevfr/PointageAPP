-- Comptes (§7.3) : emails inconnus ou archivés refusés, compte relié à la fiche.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

insert into public.profiles (id, bubble_id, email, nom, prenom, role, pointage_nfc, archive) values
  ('00000000-0000-0000-0000-0000000000a1', 't-a1', 'agent@test.local',   'Martin', 'Alice', 'agent', true,  false),
  ('00000000-0000-0000-0000-0000000000a2', 't-a2', 'archive@test.local', 'Petit',  'Paul',  'agent', false, true);

-- ── Hook avant création de compte ───────────────────────────────────────
select is(public.hook_avant_creation_compte('{"user":{"email":"agent@test.local"}}'), '{}'::jsonb,
  'Email d''un salarié actif : compte autorisé');
select is(public.hook_avant_creation_compte('{"user":{"email":"  Agent@Test.Local "}}'), '{}'::jsonb,
  'Majuscules et espaces ignorés');
select is((public.hook_avant_creation_compte('{"user":{"email":"inconnu@test.local"}}') -> 'error' ->> 'http_code'), '403',
  'Email inconnu : refusé');
select is((public.hook_avant_creation_compte('{"user":{"email":"archive@test.local"}}') -> 'error' ->> 'http_code'), '403',
  'Salarié archivé : refusé');
select is((public.hook_avant_creation_compte('{"user":{}}') -> 'error' ->> 'http_code'), '403',
  'Sans email : refusé');

-- ── Liaison à la création du compte ─────────────────────────────────────
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-000000000f01', 'Agent@test.local', 'authenticated', 'authenticated');
select is((select user_id from public.profiles where id = '00000000-0000-0000-0000-0000000000a1'),
  '00000000-0000-0000-0000-000000000f01'::uuid, 'Le compte est relié à la fiche dès sa création');

-- Fiche créée APRÈS le compte (synchro Bubble plus tardive)
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-000000000f02', 'tard@test.local', 'authenticated', 'authenticated');
insert into public.profiles (id, bubble_id, email, nom, role) values
  ('00000000-0000-0000-0000-0000000000a3', 't-a3', 'tard@test.local', 'Tard', 'agent');
select is((select user_id from public.profiles where id = '00000000-0000-0000-0000-0000000000a3'), null,
  'Pas encore reliée');

set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f02';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f02","email":"tard@test.local","role":"authenticated"}';
set local role authenticated;
select is(public.mon_profil() ->> 'autorise', 'true', 'mon_profil relie le compte à la connexion suivante');
select throws_ok($$select public.hook_avant_creation_compte('{}')$$, '42501', null,
  'Un utilisateur ne peut pas appeler le hook');
reset role;
select is((select user_id from public.profiles where id = '00000000-0000-0000-0000-0000000000a3'),
  '00000000-0000-0000-0000-000000000f02'::uuid, 'La fiche est maintenant reliée');

-- ── Ce que voit l'interface ─────────────────────────────────────────────
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f01';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f01","email":"agent@test.local","role":"authenticated"}';
set local role authenticated;
select is(public.mon_profil(),
  '{"autorise": true, "id": "00000000-0000-0000-0000-0000000000a1", "prenom": "Alice", "nom": "Martin",
    "role": "agent", "langue": "fr", "pointage_bouton": true}'::jsonb,
  'mon_profil : identité et affichage des boutons, rien de plus');
reset role;

-- Compte d'un salarié archivé depuis
update public.profiles set archive = true where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;
select is(public.mon_profil() ->> 'autorise', 'false', 'Salarié archivé depuis : accès refusé');
reset role;

-- Utilisateur inconnu (compte créé avant le hook, par exemple)
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f09';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f09","email":"pirate@test.local","role":"authenticated"}';
set local role authenticated;
select is(public.mon_profil() ->> 'autorise', 'false', 'Compte sans fiche salarié : accès refusé');
select is_empty('select 1 from public.profiles', 'Compte sans fiche salarié : ne voit rien');
reset role;

-- Un compte ne peut pas « voler » une fiche déjà reliée
select is(private.lier_compte('00000000-0000-0000-0000-000000000f09', 'tard@test.local'), null,
  'Fiche déjà reliée à un autre compte : pas de nouvelle liaison');

select * from finish();
rollback;
