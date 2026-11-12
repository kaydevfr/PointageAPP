-- Distance et zone (§5.4), puis effet sur un pointage par bouton.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

-- Site au centre de Paris. 0,00135° de latitude ≈ 150 m ; 0,018° ≈ 2 km.
insert into public.sites (id, bubble_id, nom, geo, rayon_m) values
  ('00000000-0000-0000-0000-0000000000b1', 't-site',  'Site',        'SRID=4326;POINT(2.3522 48.8566)', null),
  ('00000000-0000-0000-0000-0000000000b2', 't-petit', 'Petit rayon', 'SRID=4326;POINT(2.3522 48.8566)', 100),
  ('00000000-0000-0000-0000-0000000000b3', 't-nogeo', 'Sans GPS',    null, null);
insert into public.sites (id, bubble_id, nom, geo, geo_corrige) values
  ('00000000-0000-0000-0000-0000000000b4', 't-corr',  'Corrigé',
   'SRID=4326;POINT(2.3522 48.8566)', 'SRID=4326;POINT(2.3522 48.8746)');

-- ── Fonction pure ───────────────────────────────────────────────────────
select ok((select dans_zone and alertes = '{}' and distance_m between 140 and 160
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b1', 48.85795, 2.3522, 10)),
  'À 150 m avec rayon par défaut (200 m) : dans la zone');

select ok((select not dans_zone and alertes = array['OUT_OF_ZONE'] and distance_m between 1900 and 2100
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b1', 48.8746, 2.3522, 10)),
  'À 2 km : OUT_OF_ZONE, distance gardée');

select ok((select alertes = array['OUT_OF_ZONE']
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b2', 48.85795, 2.3522, 10)),
  'Rayon propre du site (100 m) prioritaire sur le défaut');

select ok((select alertes = array['LOW_ACCURACY'] and distance_m is not null and not dans_zone
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b1', 48.8746, 2.3522, 400)),
  'Précision de 400 m : LOW_ACCURACY, on ne conclut rien sur la zone');

select ok((select alertes = array['NO_LOCATION'] and distance_m is null
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b1', null, null, null)),
  'Pas de position : NO_LOCATION');

select ok((select alertes = array['NO_LOCATION']
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b1', 123, 2.35, 10)),
  'Latitude impossible : traitée comme absente');

select ok((select alertes = array['SITE_NO_POSITION']
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b3', 48.8566, 2.3522, 10)),
  'Site sans coordonnées : SITE_NO_POSITION');

select ok((select dans_zone
             from private.evaluer_position('00000000-0000-0000-0000-0000000000b4', 48.8746, 2.3522, 10)),
  'La position corrigée par l''admin remplace la position géocodée');

-- ── Effet sur un pointage par bouton ────────────────────────────────────
-- 4 agents sans NFC, chacun avec un créneau le lundi 08:00-10:00 et une passkey.
insert into public.profiles (id, bubble_id, nom, role, pointage_nfc) values
  ('00000000-0000-0000-0000-0000000000a1', 't-a1', 'A150m',  'agent', true),
  ('00000000-0000-0000-0000-0000000000a2', 't-a2', 'A2km',   'agent', true),
  ('00000000-0000-0000-0000-0000000000a3', 't-a3', 'A400m',  'agent', true),
  ('00000000-0000-0000-0000-0000000000a4', 't-a4', 'Refus',  'agent', true);
insert into public.creneaux (id, bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min)
select ('00000000-0000-0000-0000-0000000000c' || n)::uuid, 't-c' || n,
       ('00000000-0000-0000-0000-0000000000a' || n)::uuid,
       '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00', 120
  from generate_series(1, 4) n;
insert into public.passkeys (id, profile_id, credential_id, public_key, created_at)
select ('00000000-0000-0000-0000-0000000000d' || n)::uuid,
       ('00000000-0000-0000-0000-0000000000a' || n)::uuid,
       'cred-' || n, '\x00', '2026-01-01'
  from generate_series(1, 4) n;

select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c1',
  '{"lat":48.85795,"lng":2.3522,"precision_m":12,"passkey_id":"00000000-0000-0000-0000-0000000000d1"}',
  '2026-11-16 07:58+01') ->> 'action', 'arrivee', 'Arrivée enregistrée');
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a2', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c2',
  '{"lat":48.8746,"lng":2.3522,"precision_m":12,"passkey_id":"00000000-0000-0000-0000-0000000000d2"}',
  '2026-11-16 07:58+01') ->> 'action', 'arrivee', 'Arrivée enregistrée');
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a3', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c3',
  '{"lat":48.8566,"lng":2.3522,"precision_m":400,"passkey_id":"00000000-0000-0000-0000-0000000000d3"}',
  '2026-11-16 07:58+01') ->> 'action', 'arrivee', 'Arrivée enregistrée');
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a4', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c4',
  '{"passkey_id":"00000000-0000-0000-0000-0000000000d4"}',
  '2026-11-16 07:58+01') ->> 'action', 'arrivee', 'Arrivée enregistrée');

select results_eq(
  $$select p.statut_confiance::text, p.arrivee_at is not null
      from public.pointages p
     where p.profile_id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
                            '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a4')
     order by p.profile_id$$,
  $$values ('verifie', true), ('a_verifier', true), ('non_verifie', true), ('non_verifie', true)$$,
  '150 m → vérifié ; 2 km → à vérifier ; 400 m de précision ou refus → non vérifié, MAIS enregistré');

select ok((select 'NO_LOCATION' = any (alertes) from public.pointages
            where profile_id = '00000000-0000-0000-0000-0000000000a4'),
  'Permission refusée : NO_LOCATION');

select ok((select distance_m between 1900 and 2100 from public.evenements_pointage
            where profile_id = '00000000-0000-0000-0000-0000000000a2'),
  'La distance est gardée sur l''événement');

select * from finish();
rollback;
