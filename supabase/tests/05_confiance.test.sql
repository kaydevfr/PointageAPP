-- Statut de confiance (§5.6) : table de vérité de la fonction unique.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

select is(private.statut_confiance(true,  true,  '{}'),                         'verifie',
  'Présence + appareil, aucune alerte → vérifié');
select is(private.statut_confiance(true,  true,  array['SITE_NOT_PLANNED']),    'verifie',
  'Alerte purement informative → reste vérifié');
select is(private.statut_confiance(true,  true,  array['NO_DEPARTURE']),        'verifie',
  'NO_DEPARTURE n''est pas une alerte de présence');

select is(private.statut_confiance(true,  true,  array['OUT_OF_ZONE']),         'a_verifier', 'OUT_OF_ZONE → à vérifier');
select is(private.statut_confiance(true,  true,  array['DEVICE_CLOCK_SKEW']),   'a_verifier', 'DEVICE_CLOCK_SKEW → à vérifier');
select is(private.statut_confiance(true,  true,  array['SHARED_DEVICE']),       'a_verifier', 'SHARED_DEVICE → à vérifier');
select is(private.statut_confiance(true,  true,  array['IDENTICAL_COORDS']),    'a_verifier', 'IDENTICAL_COORDS → à vérifier');
select is(private.statut_confiance(true,  true,  array['IMPOSSIBLE_TRAVEL']),   'a_verifier', 'IMPOSSIBLE_TRAVEL → à vérifier');
select is(private.statut_confiance(true,  true,  array['REPLAYED_TAG']),        'a_verifier', 'REPLAYED_TAG → à vérifier');
select is(private.statut_confiance(true,  true,  array['BUTTON_NOT_ALLOWED']),  'a_verifier', 'BUTTON_NOT_ALLOWED → à vérifier');

select is(private.statut_confiance(false, true,  array['NO_LOCATION']),         'non_verifie', 'NO_LOCATION → non vérifié');
select is(private.statut_confiance(false, true,  array['LOW_ACCURACY']),        'non_verifie', 'LOW_ACCURACY → non vérifié');
select is(private.statut_confiance(false, true,  array['STATIC_TAG']),          'non_verifie', 'STATIC_TAG → non vérifié');
select is(private.statut_confiance(true,  false, array['NO_DEVICE_PROOF']),     'non_verifie', 'NO_DEVICE_PROOF → non vérifié');
select is(private.statut_confiance(true,  true,  array['NEW_DEVICE']),          'non_verifie', 'NEW_DEVICE → non vérifié');
select is(private.statut_confiance(false, false, '{}'),                         'non_verifie', 'Aucune preuve → non vérifié');
select is(private.statut_confiance(null,  null,  null),                         'non_verifie', 'Entrées vides → non vérifié');

select is(private.statut_confiance(false, false, array['NO_LOCATION', 'SHARED_DEVICE']), 'a_verifier',
  'Une alerte grave l''emporte sur l''absence de preuve');

select is(greatest('verifie'::public.statut_confiance, 'a_verifier', 'non_verifie'), 'a_verifier',
  'L''ordre de l''enum donne le statut le plus grave');

-- ── Heure du téléphone ──────────────────────────────────────────────────
select is(private.alerte_horloge('2026-11-16 08:10+01', '2026-11-16 08:00+01'), array['DEVICE_CLOCK_SKEW'],
  'Téléphone en avance de 10 min → DEVICE_CLOCK_SKEW');
select is(private.alerte_horloge('2026-11-16 07:50+01', '2026-11-16 08:00+01'), array['DEVICE_CLOCK_SKEW'],
  'Téléphone en retard de 10 min → DEVICE_CLOCK_SKEW');
select is(private.alerte_horloge('2026-11-16 08:01+01', '2026-11-16 08:00+01'), '{}'::text[],
  'Écart d''une minute : toléré');
select is(private.alerte_horloge(null, '2026-11-16 08:00+01'), '{}'::text[],
  'Heure du téléphone absente : pas d''alerte');

select * from finish();
rollback;
