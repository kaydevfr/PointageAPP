-- =====================================================================
-- Données de test locales (supabase db reset). Aucune donnée réelle.
-- Les tests pgTAP créent leurs propres données et ne dépendent pas de ce fichier.
-- =====================================================================

insert into public.profiles (id, bubble_id, email, nom, prenom, role, type_contact, pointage_nfc, date_demarrage_planning) values
  ('10000000-0000-0000-0000-000000000001', 'seed-admin',  'admin@nettoyeurs.test',  'Admin',   'Alex',    'admin',        'Admin',           false, null),
  ('10000000-0000-0000-0000-000000000002', 'seed-chef-a', 'sophie@nettoyeurs.test', 'Secteur', 'Sophie',  'chef_secteur', 'Chef de secteur', false, null),
  ('10000000-0000-0000-0000-000000000003', 'seed-chef-b', 'marc@nettoyeurs.test',   'Secteur', 'Marc',    'chef_secteur', 'Chef de secteur', false, null);

insert into public.profiles (id, bubble_id, email, nom, prenom, role, type_contact, chef_secteur_id, pointage_nfc, archive, date_demarrage_planning) values
  -- Agent avec NFC
  ('10000000-0000-0000-0000-000000000010', 'seed-alice',   'alice@nettoyeurs.test',   'Martin',  'Alice',   'agent',  'Agent',  '10000000-0000-0000-0000-000000000002', false, false, '2026-01-01'),
  -- Agent SANS NFC : boutons
  ('10000000-0000-0000-0000-000000000011', 'seed-bruno',   'bruno@nettoyeurs.test',   'Durand',  'Bruno',   'agent',  'Agent',  '10000000-0000-0000-0000-000000000002', true,  false, '2026-01-01'),
  -- Agent archivé
  ('10000000-0000-0000-0000-000000000012', 'seed-claire',  'claire@nettoyeurs.test',  'Petit',   'Claire',  'agent',  'Agent',  '10000000-0000-0000-0000-000000000003', false, true,  '2026-01-01'),
  -- Volant avec le secteur de Sophie
  ('10000000-0000-0000-0000-000000000020', 'seed-victor',  'victor@nettoyeurs.test',  'Leroy',   'Victor',  'volant', 'Volant', null,                                   false, false, '2026-01-01'),
  -- Volant sans secteur
  ('10000000-0000-0000-0000-000000000021', 'seed-valerie', 'valerie@nettoyeurs.test', 'Moreau',  'Valérie', 'volant', 'Volant', null,                                   true,  false, '2026-01-01');

insert into public.sites (id, bubble_id, nom, adresse, geo, chef_secteur_id) values
  ('20000000-0000-0000-0000-000000000001', 'seed-tilleuls', 'Résidence Les Tilleuls', '12 rue Oberkampf, 75011 Paris',
   'SRID=4326;POINT(2.3698 48.8649)', '10000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000002', 'seed-voltaire', 'Immeuble Voltaire',      '80 boulevard Voltaire, 75011 Paris',
   'SRID=4326;POINT(2.3781 48.8603)', '10000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003', 'seed-vaugirard','Copropriété Vaugirard',  '200 rue de Vaugirard, 75015 Paris',
   'SRID=4326;POINT(2.3053 48.8413)', '10000000-0000-0000-0000-000000000003'),
  ('20000000-0000-0000-0000-000000000004', 'seed-lecourbe', 'Résidence Lecourbe',     '150 rue Lecourbe, 75015 Paris',
   'SRID=4326;POINT(2.2977 48.8398)', '10000000-0000-0000-0000-000000000003');

insert into public.site_agents (site_id, profile_id) values
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000021');

insert into public.volant_secteurs (volant_id, chef_secteur_id) values
  ('10000000-0000-0000-0000-000000000020', '10000000-0000-0000-0000-000000000002');

-- Planning du lundi au vendredi
insert into public.creneaux (bubble_id, profile_id, site_id, jour_semaine, heure_debut, heure_fin, duree_min, ordre, deplacement, temps_deplacement_min)
select 'seed-' || x.code || '-' || j, x.profile_id, x.site_id, j, x.debut, x.fin, x.duree, x.ordre, x.deplacement, x.trajet
  from generate_series(1, 5) j
 cross join (values
   -- Alice : Tilleuls, trajet, Voltaire
   ('alice-1',  '10000000-0000-0000-0000-000000000010'::uuid, '20000000-0000-0000-0000-000000000001'::uuid, time '07:00', time '09:00', 120, 1, false, null::int),
   ('alice-t',  '10000000-0000-0000-0000-000000000010'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, time '09:00', time '09:15',  15, 2, true,  15),
   ('alice-2',  '10000000-0000-0000-0000-000000000010'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, time '09:15', time '11:00', 105, 3, false, null),
   -- Bruno : deux créneaux le même jour sur le même site (cas Bubble à corriger)
   ('bruno-1',  '10000000-0000-0000-0000-000000000011'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, time '05:00', time '07:00', 120, 1, false, null),
   ('bruno-2',  '10000000-0000-0000-0000-000000000011'::uuid, '20000000-0000-0000-0000-000000000002'::uuid, time '18:00', time '19:00',  60, 2, false, null),
   -- Valérie : Vaugirard
   ('valerie',  '10000000-0000-0000-0000-000000000021'::uuid, '20000000-0000-0000-0000-000000000003'::uuid, time '08:00', time '10:00', 120, 1, false, null),
   -- Claire (archivée) : ne doit rien générer
   ('claire',   '10000000-0000-0000-0000-000000000012'::uuid, '20000000-0000-0000-0000-000000000003'::uuid, time '08:00', time '10:00', 120, 1, false, null)
 ) as x(code, profile_id, site_id, debut, fin, duree, ordre, deplacement, trajet);

-- Puces : Tilleuls garde son ancienne puce, Voltaire a une NTAG 424 (clé fictive).
insert into public.nfc_tags (site_id, uid, type, cle_vault_id) values
  ('20000000-0000-0000-0000-000000000001', null,             'statique', null),
  ('20000000-0000-0000-0000-000000000002', '04DEADBEEF0001', 'ntag424',  '30000000-0000-0000-0000-000000000001');

-- Pointages prévus du jour
select public.generer_pointages();
