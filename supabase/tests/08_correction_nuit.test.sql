-- Correction de nuit (§9.4) : NO_DEPARTURE, créneaux qui passent minuit.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

insert into public.profiles (id, bubble_id, nom, role) values
  ('00000000-0000-0000-0000-0000000000a1', 't-a1', 'Agent', 'agent');
insert into public.sites (id, bubble_id, nom) values
  ('00000000-0000-0000-0000-0000000000b1', 't-s1', 'Jour'),
  ('00000000-0000-0000-0000-0000000000b2', 't-s2', 'Nuit'),
  ('00000000-0000-0000-0000-0000000000b3', 't-s3', 'Hors planning');
insert into public.creneaux (id, bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min) values
  ('00000000-0000-0000-0000-0000000000c1', 't-c1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00', 120),
  ('00000000-0000-0000-0000-0000000000c2', 't-c2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2', 1, '22:00', '02:00', 240);

select is(private.generer_pointages('2026-11-16'), 2, 'Génération du lundi');

create function pg_temp.scan(p_site uuid, p_at timestamptz) returns text language sql as $$
  select private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', p_site, 'nfc', null, null, '{}', p_at) ->> 'action'
$$;

select is(pg_temp.scan('00000000-0000-0000-0000-0000000000b1', '2026-11-16 07:58+01'), 'arrivee', 'Arrivée 07:58, jamais de départ');
select is(pg_temp.scan('00000000-0000-0000-0000-0000000000b3', '2026-11-16 12:00+01'), 'arrivee', 'Arrivée hors planning, jamais de départ');
select is(pg_temp.scan('00000000-0000-0000-0000-0000000000b2', '2026-11-16 21:58+01'), 'arrivee', 'Arrivée 21:58 sur le créneau de nuit');

select is(private.corriger_pointages_ouverts('2026-11-16 23:00+01'), 0, 'Le jour même : aucune correction');
select is(private.corriger_pointages_ouverts('2026-11-17 00:30+01'), 2,
  'Le lendemain : 2 corrections (le créneau de nuit en cours est épargné)');

select results_eq(
  $$select realise_min, ecart_min, realise_nuit_min, realise_jour_min, depart_at, 'NO_DEPARTURE' = any (alertes)
      from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c1'$$,
  $$values (120, null::int, 0, 120, null::timestamptz, true)$$,
  'Sans départ : réalisé = prévu, écart vide, jour/nuit recalculés, NO_DEPARTURE');

select results_eq(
  $$select realise_min, 'NO_DEPARTURE' = any (alertes)
      from public.pointages where site_id = '00000000-0000-0000-0000-0000000000b3'$$,
  $$values (null::int, true)$$,
  'Hors planning sans départ : rien à reprendre, mais NO_DEPARTURE');

select is(private.corriger_pointages_ouverts('2026-11-17 01:30+01'), 0, 'Relance : idempotente');

select is(pg_temp.scan('00000000-0000-0000-0000-0000000000b2', '2026-11-17 02:05+01'), 'depart',
  'Créneau de nuit : départ à 02:05 le lendemain, sur le pointage de la veille');
select results_eq(
  $$select realise_min, date_jour from public.pointages where creneau_id = '00000000-0000-0000-0000-0000000000c2'$$,
  $$values (247, '2026-11-16'::date)$$,
  'Créneau de nuit : 247 min réalisées, rattachées au lundi');

select is(private.corriger_pointages_ouverts('2026-11-17 07:00+01'), 0, 'Le créneau de nuit terminé n''est pas corrigé');

select * from finish();
rollback;
