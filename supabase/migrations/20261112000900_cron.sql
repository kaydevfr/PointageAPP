-- =====================================================================
-- 09 — Tâches planifiées (pg_cron tourne en UTC)
-- Toutes les tâches sont idempotentes : on peut les lancer souvent,
-- y compris pendant les changements d'heure.
-- =====================================================================

-- Génère les pointages prévus du jour (date de Paris).
select cron.schedule('generer-pointages', '5 * * * *',
  $$select public.generer_pointages()$$);

-- Clôture les pointages restés ouverts (NO_DEPARTURE).
select cron.schedule('corriger-veille', '15 * * * *',
  $$select public.corriger_veille()$$);

-- RGPD : efface les coordonnées précises au-delà de la durée de conservation.
select cron.schedule('purger-positions', '30 3 * * *',
  $$select public.purger_positions()$$);

-- Défis passkey expirés.
select cron.schedule('nettoyer-challenges', '*/30 * * * *',
  $$delete from public.challenges where expires_at < now() - interval '1 hour'$$);

-- La synchronisation Bubble (sync-bubble) sera planifiée en phase 1.
