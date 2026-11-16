-- Choix du pointage et action (§9.2), alertes appareil / horloge / puce.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

-- Fixtures ──────────────────────────────────────────────────────────────
-- a1 : agent NFC, deux créneaux le lundi sur le même site (08-10 et 14-16)
-- a2 : agent sans NFC (bouton)          a3 : agent archivé
-- a4 : agent pour la limite de débit    a5 : agent qui partage le téléphone de a1
insert into public.profiles (id, bubble_id, nom, role, pointage_nfc, archive) values
  ('00000000-0000-0000-0000-0000000000a1', 't-a1', 'NFC',     'agent', false, false),
  ('00000000-0000-0000-0000-0000000000a2', 't-a2', 'Bouton',  'agent', true,  false),
  ('00000000-0000-0000-0000-0000000000a3', 't-a3', 'Archivé', 'agent', false, true),
  ('00000000-0000-0000-0000-0000000000a4', 't-a4', 'Rapide',  'agent', false, false),
  ('00000000-0000-0000-0000-0000000000a5', 't-a5', 'Copain',  'agent', false, false);

insert into public.sites (id, bubble_id, nom, geo) values
  ('00000000-0000-0000-0000-0000000000b1', 't-s1', 'Site planifié',     'SRID=4326;POINT(2.3522 48.8566)'),
  ('00000000-0000-0000-0000-0000000000b2', 't-s2', 'Site non planifié', 'SRID=4326;POINT(2.3000 48.8500)');

insert into public.creneaux (id, bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min) values
  ('00000000-0000-0000-0000-0000000000c1', 't-c1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00', 120),
  ('00000000-0000-0000-0000-0000000000c2', 't-c2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '14:00', '16:00', 120),
  ('00000000-0000-0000-0000-0000000000c3', 't-c3', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00', 120);

insert into public.nfc_tags (id, site_id, uid, type, cle_vault_id) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1', '04A1B2C3D4E5F6', 'ntag424',
   '00000000-0000-0000-0000-0000000000f1');

insert into public.passkeys (id, profile_id, credential_id, public_key, appareil_id, created_at) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 'cred-1', '\x00', 'tel-1', '2026-01-01'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000a2', 'cred-2', '\x00', 'tel-2', '2026-01-01'),
  -- a2 a changé de téléphone il y a une heure
  ('00000000-0000-0000-0000-0000000000d3', '00000000-0000-0000-0000-0000000000a2', 'cred-3', '\x00', 'tel-3', '2026-11-16 07:00+01'),
  ('00000000-0000-0000-0000-0000000000d5', '00000000-0000-0000-0000-0000000000a5', 'cred-5', '\x00', 'tel-5', '2026-01-01');

select is(private.generer_pointages('2026-11-16'), 3, 'Génération du lundi');

-- Preuves d'un scan NFC sécurisé valide fait avec la passkey de a1
create function pg_temp.nfc(p_profile uuid, p_site uuid, p_at timestamptz, p_extra jsonb default '{}')
returns jsonb language sql as $$
  select private.traiter_pointage(p_profile, p_site, 'nfc', null, null,
    jsonb_build_object('nfc_tag_id', '00000000-0000-0000-0000-0000000000e1',
                       'passkey_id', '00000000-0000-0000-0000-0000000000d1',
                       'appareil_id', 'tel-1') || p_extra,
    p_at)
$$;

-- ── Arrivée / anti-rebond / départ ──────────────────────────────────────
select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                      '2026-11-16 07:58+01') ->> 'message',
  'Arrivée pointée à 07:58 ✓', 'Premier scan : arrivée');

select is((select arrivee_at from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c1'),
  '2026-11-16 07:58+01'::timestamptz, 'L''arrivée est sur le créneau de 8 h (le plus proche)');

select is((select statut_confiance::text from public.pointages
            where creneau_id = '00000000-0000-0000-0000-0000000000c1'),
  'verifie', 'NFC sécurisé + passkey : vérifié');

select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                      '2026-11-16 08:01+01') ->> 'message',
  'Déjà pointé à 07:58', 'Second scan à moins de 5 min : ignoré');

select is((select count(*)::int from public.evenements_pointage
            where profile_id = '00000000-0000-0000-0000-0000000000a1' and type = 'ignore'), 1,
  'Le scan ignoré est quand même journalisé');

select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                      '2026-11-16 10:02+01') ->> 'action',
  'depart', 'Scan à 10:02 : départ');

select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min, ecart_min
      from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c1'$$,
  $$values (124, 0, 124, 4)$$,
  'Temps calculés au départ');

-- ── Deux créneaux sur le même site ──────────────────────────────────────
select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1',
                      '2026-11-16 13:55+01') ->> 'action',
  'arrivee', 'Scan à 13:55 : nouvelle arrivée');
select is((select arrivee_at from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c2'),
  '2026-11-16 13:55+01'::timestamptz, 'Elle va sur le créneau de 14 h, pas sur celui du matin');
select is((select depart_at from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c1'),
  '2026-11-16 10:02+01'::timestamptz, 'Le pointage du matin est intact');

-- ── Hors planning ───────────────────────────────────────────────────────
select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
                      '2026-11-16 11:00+01') ->> 'action',
  'arrivee', 'Site non planifié : arrivée enregistrée');
select results_eq(
  $$select hors_planning, 'SITE_NOT_PLANNED' = any (alertes), prevu_min is null
      from public.pointages
     where profile_id = '00000000-0000-0000-0000-0000000000a1' and site_id = '00000000-0000-0000-0000-0000000000b2'$$,
  $$values (true, true, true)$$,
  'Pointage hors planning créé, avec SITE_NOT_PLANNED');

-- ── Double clic : deux appels au même instant ───────────────────────────
select is(pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
                      '2026-11-16 11:00+01') ->> 'action',
  'deja_pointe', 'Double clic : la seconde action est ignorée');
select is((select count(*)::int from public.pointages
            where profile_id = '00000000-0000-0000-0000-0000000000a1' and site_id = '00000000-0000-0000-0000-0000000000b2'),
  1, 'Un seul pointage hors planning');

-- ── La réponse ne révèle jamais les alertes ─────────────────────────────
select ok(not (pg_temp.nfc('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
                           '2026-11-16 11:01+01')::text ~* 'alerte|statut|SITE_NOT_PLANNED'),
  'La réponse à l''agent ne contient ni alerte ni statut');

-- ── Ancienne puce / sans passkey / horloge ──────────────────────────────
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000b1',
  'nfc', null, null, '{"device_at":"2026-11-16T08:10:00+01:00"}', '2026-11-16 08:00+01') ->> 'action',
  'arrivee', 'Ancienne puce, sans passkey : pointage enregistré');
select results_eq(
  $$select statut_confiance::text, alertes, arrivee_at
      from public.pointages where profile_id = '00000000-0000-0000-0000-0000000000a4'$$,
  $$values ('a_verifier', array['DEVICE_CLOCK_SKEW', 'NO_DEVICE_PROOF', 'SITE_NOT_PLANNED', 'STATIC_TAG'],
            '2026-11-16 08:00+01'::timestamptz)$$,
  'Ancienne puce + sans passkey + horloge décalée de 10 min : alertes, et l''heure reste celle du serveur');

-- ── Bouton ──────────────────────────────────────────────────────────────
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', null, 'bouton',
  (select id from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c2'), null,
  '{"lat":48.8566,"lng":2.3522,"precision_m":10,"passkey_id":"00000000-0000-0000-0000-0000000000d1"}',
  '2026-11-16 16:00+01') ->> 'action', 'depart', 'Bouton utilisé par un agent NFC : accepté…');
select ok((select 'BUTTON_NOT_ALLOWED' = any (alertes) and statut_confiance = 'a_verifier'
             from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c2'),
  '… mais signalé BUTTON_NOT_ALLOWED');

select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a2', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c3',
  '{"lat":48.8566,"lng":2.3522,"precision_m":10,"passkey_id":"00000000-0000-0000-0000-0000000000d3","appareil_id":"tel-3"}',
  '2026-11-16 08:00+01') ->> 'action', 'arrivee', 'Bouton sur la carte du créneau');
select ok((select 'NEW_DEVICE' = any (alertes) and statut_confiance = 'non_verifie'
             from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c3'),
  'Passkey créée il y a une heure alors qu''une autre existait : NEW_DEVICE');

select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a2', null, 'bouton',
  (select id from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c1'), null,
  '{}', '2026-11-16 08:05+01') ->> 'code', 'POINTAGE_INVALIDE',
  'Bouton sur le pointage d''un autre agent : refusé');

-- ── Passkey d'un autre compte / téléphone partagé ───────────────────────
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1',
  'nfc', null, null,
  '{"nfc_tag_id":"00000000-0000-0000-0000-0000000000e1","passkey_id":"00000000-0000-0000-0000-0000000000d1","appareil_id":"tel-1"}',
  '2026-11-16 09:00+01') ->> 'action', 'arrivee', 'Pointage avec le téléphone d''un collègue : enregistré');
select results_eq(
  $$select 'NO_DEVICE_PROOF' = any (alertes), 'SHARED_DEVICE' = any (alertes), statut_confiance::text
      from public.pointages where profile_id = '00000000-0000-0000-0000-0000000000a5'$$,
  $$values (true, true, 'a_verifier')$$,
  'Passkey d''un autre compte ignorée (NO_DEVICE_PROOF) et téléphone partagé (SHARED_DEVICE)');

-- ── Agent archivé ───────────────────────────────────────────────────────
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b1',
  'nfc', null, null, '{}', '2026-11-16 09:00+01') ->> 'code', 'PROFIL_INACTIF',
  'Agent archivé : ne peut plus pointer');
select is_empty($$select 1 from public.pointages where profile_id = '00000000-0000-0000-0000-0000000000a3'$$,
  'Aucun pointage créé pour l''agent archivé');

-- ── Limite de débit : 10 actions par minute ─────────────────────────────
select is((select count(*)::int from (
    select private.traiter_pointage('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000b2',
           'nfc', null, null, '{}', '2026-11-16 12:00+01') ->> 'code' as code
      from generate_series(1, 10)) x where x.code is null),
  10, 'Dix actions dans la minute : acceptées');
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000b2',
  'nfc', null, null, '{}', '2026-11-16 12:00+01') ->> 'code', 'RATE_LIMIT',
  'Onzième action dans la minute : limitée');
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000b2',
  'nfc', null, null, '{}', '2026-11-16 12:02+01') ->> 'code', null,
  'Deux minutes plus tard : de nouveau accepté');

-- ── Preuve malformée : ne bloque pas ────────────────────────────────────
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b2',
  'nfc', null, null, '{"lat":"abc","device_at":"pas une date","ip":"x"}', '2026-11-16 15:00+01') ->> 'action',
  'arrivee', 'Valeurs malformées ignorées, pointage enregistré');

select * from finish();
rollback;
