-- Calculs de temps (§9.3) et fuseau Europe/Paris, changements d'heure inclus.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

-- ── Fuseau ──────────────────────────────────────────────────────────────
select is(private.date_paris('2026-11-16 23:30:00+00'), date '2026-11-17',
  '23:30 UTC en hiver = lendemain à Paris');
select is(private.a_paris('2026-11-16', '06:00'), '2026-11-16 05:00:00+00'::timestamptz,
  '6 h Paris en hiver = 5 h UTC');
select is(private.a_paris('2026-07-01', '06:00'), '2026-07-01 04:00:00+00'::timestamptz,
  '6 h Paris en été = 4 h UTC');
select is(private.hhmm('2026-11-16 06:58:00+00'), '07:58', 'Affichage HH:MM à l''heure de Paris');

-- ── Créneau normal ──────────────────────────────────────────────────────
select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min, ecart_min
      from private.calcul_temps('2026-11-16 07:58+01', '2026-11-16 10:02+01', 120)$$,
  $$values (124, 0, 124, 4)$$,
  'Arrivée 07:58, départ 10:02, prévu 120 → 124 min, 0 nuit, écart +4');

-- ── Nuit ────────────────────────────────────────────────────────────────
select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min
      from private.calcul_temps('2026-11-16 05:00+01', '2026-11-16 07:00+01', 120)$$,
  $$values (120, 60, 60)$$,
  '5 h → 7 h : 60 min de nuit et 60 min de jour');

select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min
      from private.calcul_temps('2026-11-16 04:00+01', '2026-11-16 05:30+01', 90)$$,
  $$values (90, 90, 0)$$,
  '4 h → 5 h 30 : 90 min de nuit (Bubble en comptait 120)');

select results_eq(
  $$select realise_nuit_min from private.calcul_temps('2026-11-16 06:00+01', '2026-11-16 08:00+01', 120)$$,
  $$values (0)$$,
  'Arrivée à 6 h pile : pas de nuit');

-- ── Hors planning ───────────────────────────────────────────────────────
select results_eq(
  $$select realise_min, ecart_min from private.calcul_temps('2026-11-16 08:00+01', '2026-11-16 09:00+01', null)$$,
  $$values (60, null::int)$$,
  'Sans prévu : écart vide');

select results_eq(
  $$select realise_min from private.calcul_temps('2026-11-16 08:00+01', null, 60)$$,
  $$values (null::int)$$,
  'Sans départ : rien n''est calculé');

-- ── Changements d'heure ─────────────────────────────────────────────────
-- 25 octobre 2026 : à 3 h on revient à 2 h. 01:30 (UTC+2) → 05:30 (UTC+1) = 5 h réelles.
select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min
      from private.calcul_temps('2026-10-25 01:30+02', '2026-10-25 05:30+01', 240)$$,
  $$values (300, 300, 0)$$,
  'Passage à l''heure d''hiver : 300 min réelles, toutes de nuit');

-- 28 mars 2027 : à 2 h on passe à 3 h. 01:30 (UTC+1) → 05:30 (UTC+2) = 3 h réelles.
select results_eq(
  $$select realise_min, realise_nuit_min, realise_jour_min, ecart_min
      from private.calcul_temps('2027-03-28 01:30+01', '2027-03-28 05:30+02', 240)$$,
  $$values (180, 180, 0, -60)$$,
  'Passage à l''heure d''été : 180 min réelles, toutes de nuit');

-- 6 h le jour du changement d'heure d'été = 4 h UTC
select results_eq(
  $$select realise_nuit_min, realise_jour_min
      from private.calcul_temps('2027-03-28 05:00+02', '2027-03-28 07:00+02', 120)$$,
  $$values (60, 60)$$,
  'Jour du passage à l''heure d''été : 6 h calculé en heure locale');

select * from finish();
rollback;
