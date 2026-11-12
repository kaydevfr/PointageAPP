-- Anti-rejeu des puces NTAG 424 DNA (§5.2) : un compteur ne sert qu'une fois.
begin;
create extension if not exists pgtap with schema extensions;
select no_plan();

-- Isolation : on vide les données (seed compris) ; le rollback final annule tout.
truncate public.profiles, public.sites, public.site_agents, public.volant_secteurs, public.creneaux,
         public.pointages, public.evenements_pointage, public.nfc_tags, public.nfc_reservations,
         public.passkeys, public.challenges, public.audit_admin cascade;

insert into public.sites (id, bubble_id, nom) values
  ('00000000-0000-0000-0000-0000000000b1', 't-site', 'Site');
insert into public.nfc_tags (id, site_id, uid, type, cle_vault_id, actif) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b1', '04A1B2C3D4E5F6', 'ntag424',
   '00000000-0000-0000-0000-0000000000f1', true),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-0000000000b1', null, 'statique', null, true),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000b1', '04FFFFFFFFFFFF', 'ntag424',
   '00000000-0000-0000-0000-0000000000f1', false);

select isnt(private.reserver_compteur('00000000-0000-0000-0000-0000000000e1', 5, '2026-11-16 08:00+01'), null,
  'Premier scan (compteur 5) : réservé');
select is(private.reserver_compteur('00000000-0000-0000-0000-0000000000e1', 5, '2026-11-16 08:01+01'), null,
  'Même lien rejoué (compteur 5) : refusé');
select is(private.reserver_compteur('00000000-0000-0000-0000-0000000000e1', 4, '2026-11-16 08:02+01'), null,
  'Ancien lien (compteur 4) : refusé');
select isnt(private.reserver_compteur('00000000-0000-0000-0000-0000000000e1', 6, '2026-11-16 08:03+01'), null,
  'Scan suivant (compteur 6) : réservé');
select is((select dernier_compteur from public.nfc_tags where id = '00000000-0000-0000-0000-0000000000e1'), 6,
  'Dernier compteur mémorisé');

select is((select expires_at - created_at from public.nfc_reservations where compteur = 5), interval '10 minutes',
  'La réservation vaut 10 minutes');

select is(private.reserver_compteur('00000000-0000-0000-0000-0000000000e2', 1, '2026-11-16 08:00+01'), null,
  'Une puce statique ne passe jamais par la réservation SUN');
select is(private.reserver_compteur('00000000-0000-0000-0000-0000000000e3', 1, '2026-11-16 08:00+01'), null,
  'Puce désactivée : refusée');

select throws_ok(
  $$insert into public.nfc_tags (site_id, type) values ('00000000-0000-0000-0000-0000000000b1', 'ntag424')$$,
  '23514', null, 'Une puce NTAG 424 exige un UID et une clé');

select * from finish();
rollback;
