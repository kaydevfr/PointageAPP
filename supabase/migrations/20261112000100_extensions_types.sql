-- =====================================================================
-- 01 — Extensions, schéma privé et types énumérés
-- =====================================================================

create extension if not exists postgis with schema extensions;
create extension if not exists pg_cron;

-- Schéma interne : jamais exposé par l'API (absent de [api].schemas
-- dans config.toml). Toute la logique métier y vit.
create schema if not exists private;

-- Par défaut PostgreSQL rend toute fonction exécutable par PUBLIC.
-- On inverse ce défaut pour le schéma privé : chaque droit est accordé
-- explicitement (voir migration 08).
alter default privileges in schema private revoke execute on functions from public;
alter default privileges in schema public  revoke execute on functions from public;

create type public.role_profil as enum
  ('agent', 'volant', 'chef_equipe', 'chef_secteur', 'admin', 'autre');

-- L'ordre compte : max() / greatest() renvoient le statut le plus grave.
create type public.statut_confiance as enum
  ('verifie', 'non_verifie', 'a_verifier');

-- 'ignore' : action reçue mais sans effet (anti-rebond, pointage terminé).
-- 'rejete' : lien NFC rejoué, aucun pointage modifié.
create type public.type_evenement as enum
  ('arrivee', 'depart', 'ignore', 'rejete');

create type public.methode_pointage as enum ('nfc', 'bouton');

create type public.type_puce as enum ('statique', 'ntag424');
