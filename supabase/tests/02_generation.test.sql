-- Génération des pointages prévus (§9.1) : filtres, minuit, trajet, idempotence.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

insert into public.profiles (id, bubble_id, nom, role, archive, date_demarrage_planning) values
  ('00000000-0000-0000-0000-0000000000a1', 't-actif',   'Actif',   'agent', false, '2026-01-01'),
  ('00000000-0000-0000-0000-0000000000a2', 't-archive', 'Archivé', 'agent', true,  '2026-01-01'),
  ('00000000-0000-0000-0000-0000000000a3', 't-futur',   'Futur',   'agent', false, '2027-01-01');

insert into public.sites (id, bubble_id, nom, geo, contrat_termine) values
  ('00000000-0000-0000-0000-0000000000b1', 't-site',   'Site',          'SRID=4326;POINT(2.3522 48.8566)', false),
  ('00000000-0000-0000-0000-0000000000b2', 't-ferme',  'Site terminé',  'SRID=4326;POINT(2.3522 48.8566)', true);

-- Lundi = 1, dimanche = 7 (ISO)
insert into public.creneaux (bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin,
                             duree_min, ordre, deplacement, temps_deplacement_min, simulation) values
  ('c-trajet',  '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '06:45', '07:00', 15,   1, true,  15,   false),
  ('c-normal',  '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '07:00', '09:00', null, 2, false, null, false),
  ('c-simul',   '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '10:00', '11:00', 60,   3, false, null, true),
  ('c-nuit',    '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '22:00', '02:00', null, 4, false, null, false),
  ('c-ferme',   '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b2', 1, '12:00', '13:00', 60,   5, false, null, false),
  ('c-mardi',   '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 2, '07:00', '09:00', 120,  1, false, null, false),
  ('c-dimanche','00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 7, '07:00', '09:00', 120,  1, false, null, false),
  ('c-archive', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000b1', 1, '07:00', '09:00', 120,  1, false, null, false),
  ('c-futur',   '00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000b1', 1, '07:00', '09:00', 120,  1, false, null, false);
insert into public.creneaux (bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min, actif) values
  ('c-inactif', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', 1, '15:00', '16:00', 60, false);

-- Lundi 16 novembre 2026
select is(private.generer_pointages('2026-11-16'), 2,
  'Lundi : seuls le créneau normal et le créneau de nuit sont générés');
select is(private.generer_pointages('2026-11-16'), 0, 'Relance : aucun doublon');
select is((select count(*)::int from public.pointages where date_jour = '2026-11-16'), 2,
  'Toujours 2 pointages après la relance');

select results_eq(
  $$select p.prevu_debut, p.prevu_fin, p.prevu_min, p.temps_deplacement_min, p.hors_planning
      from public.pointages p join public.creneaux c on c.id = p.creneau_id
     where c.bubble_id = 'c-normal'$$,
  $$values ('2026-11-16 07:00+01'::timestamptz, '2026-11-16 09:00+01'::timestamptz, 120, 15, false)$$,
  'Créneau normal : heures de Paris, durée calculée, trajet précédent repris');

select results_eq(
  $$select p.prevu_debut, p.prevu_fin, p.prevu_min
      from public.pointages p join public.creneaux c on c.id = p.creneau_id
     where c.bubble_id = 'c-nuit'$$,
  $$values ('2026-11-16 22:00+01'::timestamptz, '2026-11-17 02:00+01'::timestamptz, 240)$$,
  'Créneau qui passe minuit : la fin est le lendemain');

select is_empty(
  $$select 1 from public.pointages where profile_id in
      ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a3')$$,
  'Profil archivé ou date de démarrage future : rien de généré');

-- Dimanche 25 octobre 2026 : passage à l'heure d'hiver
select is(private.generer_pointages('2026-10-25'), 1, 'Dimanche du changement d''heure : 1 pointage');
select results_eq(
  $$select prevu_debut, prevu_fin, prevu_min from public.pointages where date_jour = '2026-10-25'$$,
  $$values ('2026-10-25 07:00+01'::timestamptz, '2026-10-25 09:00+01'::timestamptz, 120)$$,
  'Après le changement d''heure : 7 h reste 7 h à Paris');

select * from finish();
rollback;
