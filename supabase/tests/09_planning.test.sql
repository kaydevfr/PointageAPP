-- Planning du jour et règles d'affichage (§2.4) : boutons, messages,
-- deux créneaux sur le même site, hors planning.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

-- a1 : sans NFC (boutons) ; a2 : avec NFC (pas de bouton)
insert into public.profiles (id, bubble_id, nom, role, pointage_nfc) values
  ('00000000-0000-0000-0000-0000000000a1', 't-a1', 'Bouton', 'agent', true),
  ('00000000-0000-0000-0000-0000000000a2', 't-a2', 'NFC',    'agent', false);
insert into public.sites (id, bubble_id, nom, adresse) values
  ('00000000-0000-0000-0000-0000000000b1', 't-s1', 'Résidence', '1 rue de Paris'),
  ('00000000-0000-0000-0000-0000000000b2', 't-s2', 'Autre',     '2 rue de Lyon');
insert into public.creneaux (id, bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min) values
  ('00000000-0000-0000-0000-0000000000c1', 't-c1', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '06:00', '08:00', 120),
  ('00000000-0000-0000-0000-0000000000c2', 't-c2', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '18:00', '19:00', 60),
  ('00000000-0000-0000-0000-0000000000c3', 't-c3', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 1, '08:00', '10:00', 120);

create function pg_temp.planning(p_profile uuid, p_at timestamptz)
returns table (creneau_id uuid, pointage_id uuid, etat text, affichage text, message text, bouton text, hors_planning boolean)
language sql as $$
  select creneau_id, pointage_id, etat, affichage, message, bouton, hors_planning
    from private.planning_du_jour(p_profile, private.date_paris(p_at), p_at)
$$;

-- Avant toute génération : les cartes viennent des créneaux.
select results_eq(
  $$select creneau_id, pointage_id, etat, affichage, bouton
      from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 05:00+01')$$,
  $$values ('00000000-0000-0000-0000-0000000000c1'::uuid, null::uuid, 'a_faire', 'a_pointer', 'arrivee'),
           ('00000000-0000-0000-0000-0000000000c2'::uuid, null::uuid, 'a_faire', 'a_pointer', 'arrivee')$$,
  'Dès minuit : « Pointer l''arrivée » sur chaque créneau du jour');

-- Bouton sur la carte du premier créneau (pointage pas encore généré).
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', null, 'bouton', null,
  '00000000-0000-0000-0000-0000000000c1', '{}', '2026-11-16 05:58+01') ->> 'message',
  'Arrivée pointée à 05:58 ✓', 'Le pointage prévu est créé au moment de l''arrivée');

select results_eq(
  $$select affichage, message, bouton from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 06:30+01')$$,
  $$values ('arrivee_pointee', 'Arrivée pointée à 05:58', 'depart'),
           ('a_pointer', null, 'arrivee')$$,
  'Deux créneaux sur le même site : chaque carte affiche SON pointage');

select results_eq(
  $$select affichage, message, bouton from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 08:30+01')
     limit 1$$,
  $$values ('penser_depart', 'Créneau terminé : pensez à pointer votre départ', 'depart')$$,
  'Après la fin du créneau sans départ : rappel, le bouton reste');

select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', null, 'bouton',
  (select pointage_id from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 08:40+01') limit 1),
  null, '{}', '2026-11-16 08:40+01') ->> 'message',
  'Départ pointé à 08:40 ✓', 'Départ par le bouton de la carte');

select results_eq(
  $$select etat, affichage, message, bouton from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 19:30+01')$$,
  $$values ('termine', 'termine', 'Arrivée 05:58 · Départ 08:40', null::text),
           ('manque',  'manque',  'Créneau terminé à 19:00 : arrivée non pointée', null::text)$$,
  'Encadré vert une fois terminé ; créneau manqué sans arrivée');

select is(private.generer_pointages('2026-11-16'), 2,
  'La génération ne recrée pas le pointage déjà créé par le bouton (2 = c2 + c3)');
select is((select count(*)::int from public.pointages where profile_id = '00000000-0000-0000-0000-0000000000a1'), 2,
  'Toujours 2 pointages pour l''agent');

-- Pointage hors planning : il apparaît comme une carte en plus.
select is(private.traiter_pointage('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2',
  'nfc', null, null, '{}', '2026-11-16 20:00+01') ->> 'action', 'arrivee', 'Arrivée hors planning');
select results_eq(
  $$select count(*)::int, count(*) filter (where hors_planning)::int
      from pg_temp.planning('00000000-0000-0000-0000-0000000000a1', '2026-11-16 20:05+01')$$,
  $$values (3, 1)$$,
  'La carte hors planning s''ajoute au planning');

-- Agent NFC : jamais de bouton.
select results_eq(
  $$select bouton, etat from pg_temp.planning('00000000-0000-0000-0000-0000000000a2', '2026-11-16 07:00+01')$$,
  $$values (null::text, 'a_faire')$$,
  'pointage_nfc = false : aucun bouton');

-- Jour passé : plus de bouton.
select is_empty(
  $$select 1 from private.planning_du_jour('00000000-0000-0000-0000-0000000000a1', '2026-11-16', '2026-11-17 10:00+01')
     where bouton is not null$$,
  'Planning d''un jour passé : aucun bouton');

select * from finish();
rollback;
