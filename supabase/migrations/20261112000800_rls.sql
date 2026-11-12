-- =====================================================================
-- 08 — Droits et règles RLS
--
-- Principe : les rôles `anon` et `authenticated` ne peuvent RIEN écrire.
-- Toute écriture passe par des fonctions réservées à `service_role`
-- (Edge Functions) ou, plus tard, par des RPC admin qui écrivent dans
-- audit_admin. Les alertes et le statut de confiance ne sont jamais
-- lisibles directement : l'admin y accède par RPC (phase 1).
-- =====================================================================

-- ── Tables : on repart de zéro ─────────────────────────────────────────
revoke all on all tables    in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated;

grant select on public.profiles, public.sites, public.site_agents,
                public.volant_secteurs, public.creneaux
  to authenticated;

-- Pointages : toutes les colonnes SAUF alertes, statut et file Bubble.
grant select (id, profile_id, site_id, creneau_id, date_jour,
              prevu_debut, prevu_fin, prevu_min, temps_deplacement_min,
              arrivee_at, depart_at,
              realise_min, realise_nuit_min, realise_jour_min, ecart_min,
              hors_planning, absence, valide, created_at, updated_at)
  on public.pointages to authenticated;

-- Aucun droit pour authenticated sur : evenements_pointage, nfc_tags,
-- nfc_reservations, passkeys, challenges, audit_admin, reglages.

-- ── Fonctions ──────────────────────────────────────────────────────────
revoke all on all functions in schema public  from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;

-- Les politiques RLS appellent ces fonctions avec les droits de l'appelant.
grant usage on schema private to authenticated;
grant execute on function private.mon_profil_id()    to authenticated;
grant execute on function private.mon_role()         to authenticated;
grant execute on function private.est_admin()        to authenticated;
grant execute on function private.profils_visibles() to authenticated;
grant execute on function private.sites_visibles()   to authenticated;

grant execute on function public.mon_planning(date) to authenticated;

grant execute on function public.traiter_pointage(uuid, uuid, public.methode_pointage, uuid, uuid, jsonb)
  to service_role;
grant execute on function public.nfc_reserver_compteur(uuid, int) to service_role;
grant execute on function public.generer_pointages(date)          to service_role;
grant execute on function public.corriger_veille()                to service_role;
grant execute on function public.purger_positions()               to service_role;

-- ── Politiques de lecture ──────────────────────────────────────────────
create policy profiles_lecture on public.profiles
  for select to authenticated
  using (id in (select private.profils_visibles()));

create policy sites_lecture on public.sites
  for select to authenticated
  using (id in (select private.sites_visibles()));

create policy site_agents_lecture on public.site_agents
  for select to authenticated
  using (profile_id in (select private.profils_visibles()));

create policy volant_secteurs_lecture on public.volant_secteurs
  for select to authenticated
  using (volant_id in (select private.profils_visibles()));

create policy creneaux_lecture on public.creneaux
  for select to authenticated
  using (profile_id in (select private.profils_visibles()));

create policy pointages_lecture on public.pointages
  for select to authenticated
  using (profile_id in (select private.profils_visibles()));

-- Aucune politique insert / update / delete : RLS active + aucune
-- politique = refus, même si un droit était accordé par erreur.
