-- Droits et RLS (§8) : lecture par périmètre, aucune écriture côté agent,
-- alertes invisibles, volants et secteurs (§2.5).
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

-- Comptes Auth
insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-000000000f00', 'admin@test.local',  'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000f01', 'chef@test.local',   'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000f02', 'agent@test.local',  'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000f03', 'volant1@test.local','authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000f04', 'volant2@test.local','authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-000000000f05', 'archive@test.local','authenticated', 'authenticated');

insert into public.profiles (id, user_id, bubble_id, email, nom, role, archive) values
  ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-000000000f00', 't-admin', 'admin@test.local',   'Admin',  'admin',        false),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000f01', 't-chef',  'chef@test.local',    'Chef',   'chef_secteur', false);
insert into public.profiles (id, user_id, bubble_id, email, nom, role, chef_secteur_id, archive) values
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000f02', 't-agent', 'agent@test.local',   'Agent',  'agent',  '00000000-0000-0000-0000-0000000000a1', false),
  ('00000000-0000-0000-0000-0000000000a3', null,                                   't-autre', null,                 'Autre',  'agent',  null, false),
  ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-000000000f03', 't-vol1',  'volant1@test.local', 'Volant1','volant', null, false),
  ('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-000000000f04', 't-vol2',  'volant2@test.local', 'Volant2','volant', null, false),
  ('00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-000000000f05', 't-arch',  'archive@test.local', 'Archivé','agent',  null, true);

-- S1, S2 : secteur du chef a1 ; S3, S4 : autres
insert into public.sites (id, bubble_id, nom, chef_secteur_id) values
  ('00000000-0000-0000-0000-0000000000b1', 't-s1', 'S1', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b2', 't-s2', 'S2', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b3', 't-s3', 'S3', null),
  ('00000000-0000-0000-0000-0000000000b4', 't-s4', 'S4', null);

insert into public.creneaux (bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin) values
  ('t-c1', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00'),
  ('t-c2', '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b3', 1, '08:00', '10:00'),
  ('t-c3', '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b3', 1, '08:00', '10:00');
insert into public.site_agents (site_id, profile_id) values
  ('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000a4'),
  ('00000000-0000-0000-0000-0000000000b4', '00000000-0000-0000-0000-0000000000a5');
-- Volant 1 travaille sur le secteur du chef a1 ; volant 2 n'a aucun secteur.
insert into public.volant_secteurs (volant_id, chef_secteur_id) values
  ('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000a1');

select is(private.generer_pointages('2026-11-16'), 3, 'Pointages de test générés');

-- ── Agent ───────────────────────────────────────────────────────────────
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f02';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f02","role":"authenticated"}';
set local role authenticated;

select results_eq('select id from public.profiles', $$values ('00000000-0000-0000-0000-0000000000a2'::uuid)$$,
  'Agent : ne voit que son profil');
select results_eq('select count(*)::int from public.pointages', $$values (1)$$, 'Agent : ne voit que ses pointages');
select results_eq('select nom from public.sites', $$values ('S1')$$, 'Agent : ne voit que ses sites');
select lives_ok('select id, arrivee_at, depart_at, realise_min from public.pointages',
  'Agent : lit les heures de ses pointages');
select throws_ok('select alertes from public.pointages', '42501', null,
  'Agent : ne peut pas lire les alertes');
select throws_ok('select statut_confiance from public.pointages', '42501', null,
  'Agent : ne peut pas lire le statut de confiance');
select throws_ok('select * from public.evenements_pointage', '42501', null,
  'Agent : ne peut pas lire le journal');
select throws_ok($$insert into public.pointages (profile_id, site_id, date_jour)
                   values ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', '2026-11-16')$$,
  '42501', null, 'Agent : ne peut pas créer de pointage');
select throws_ok('update public.pointages set arrivee_at = now()', '42501', null,
  'Agent : ne peut pas modifier un pointage');
select throws_ok('delete from public.pointages', '42501', null, 'Agent : ne peut pas supprimer');
select throws_ok('insert into public.evenements_pointage (profile_id, type, methode) values (''00000000-0000-0000-0000-0000000000a2'', ''arrivee'', ''nfc'')',
  '42501', null, 'Agent : ne peut pas écrire dans le journal');
select throws_ok('update public.profiles set pointage_nfc = true', '42501', null,
  'Agent : ne peut pas modifier son profil');
select throws_ok($$select public.traiter_pointage('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 'nfc')$$,
  '42501', null, 'Agent : ne peut pas appeler traiter_pointage directement');
select throws_ok('select public.generer_pointages()', '42501', null, 'Agent : ne peut pas lancer la génération');
select throws_ok('select * from public.reglages', '42501', null, 'Agent : ne lit pas les réglages');
select throws_ok('select * from public.passkeys', '42501', null, 'Agent : ne lit pas les passkeys');
select throws_ok('select * from public.nfc_tags', '42501', null, 'Agent : ne lit pas les puces');
select lives_ok($$select * from public.mon_planning('2026-11-16')$$, 'Agent : peut appeler mon_planning');
select results_eq($$select count(*)::int from public.mon_planning('2026-11-16')$$, $$values (1)$$,
  'Agent : mon_planning renvoie sa carte');

-- ── Volant avec secteur ─────────────────────────────────────────────────
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f03';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f03","role":"authenticated"}';
set local role authenticated;
select results_eq('select nom from public.sites order by nom', $$values ('S1'), ('S2'), ('S4')$$,
  'Volant avec secteur : sites du secteur + ses propres sites');

-- ── Volant sans secteur ─────────────────────────────────────────────────
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f04';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f04","role":"authenticated"}';
set local role authenticated;
select results_eq('select nom from public.sites order by nom', $$values ('S3'), ('S4')$$,
  'Volant sans secteur : SEULEMENT ses propres sites (pas tous, contrairement à Bubble)');

-- ── Chef de secteur ─────────────────────────────────────────────────────
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f01';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f01","role":"authenticated"}';
set local role authenticated;
select results_eq('select nom from public.profiles order by nom', $$values ('Agent'), ('Chef')$$,
  'Chef de secteur : lui-même et son équipe');
select results_eq('select profile_id from public.pointages',
  $$values ('00000000-0000-0000-0000-0000000000a2'::uuid)$$, 'Chef de secteur : pointages de son équipe');
select results_eq('select nom from public.sites order by nom', $$values ('S1'), ('S2')$$,
  'Chef de secteur : sites de son secteur');
select throws_ok('update public.pointages set valide = true', '42501', null,
  'Chef de secteur : pas d''écriture directe');

-- ── Admin ───────────────────────────────────────────────────────────────
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f00';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f00","role":"authenticated"}';
set local role authenticated;
select results_eq('select count(*)::int from public.sites', $$values (4)$$, 'Admin : tous les sites');
select results_eq('select count(*)::int from public.profiles', $$values (7)$$, 'Admin : tous les profils');
select results_eq('select count(*)::int from public.pointages', $$values (3)$$, 'Admin : tous les pointages');
select throws_ok('update public.pointages set valide = true', '42501', null,
  'Admin : corrections uniquement par fonction auditée (phase 1)');

-- ── Compte archivé ──────────────────────────────────────────────────────
reset role;
set local request.jwt.claim.sub = '00000000-0000-0000-0000-000000000f05';
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000f05","role":"authenticated"}';
set local role authenticated;
select is_empty('select 1 from public.profiles', 'Compte archivé : ne voit plus rien');
select is_empty($$select 1 from public.mon_planning('2026-11-16')$$, 'Compte archivé : planning vide');

-- ── Anonyme ─────────────────────────────────────────────────────────────
reset role;
set local role anon;
select throws_ok('select * from public.profiles', '42501', null, 'Anonyme : aucun accès aux tables');
select throws_ok($$select * from public.mon_planning()$$, '42501', null, 'Anonyme : pas de planning');

reset role;
select * from finish();
rollback;
