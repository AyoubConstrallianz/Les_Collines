-- ════════════════════════════════════════════════════════════════
-- 08 — Tarif « 6 mois » par sport (remplace le tarif trimestriel dans l'application)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- La colonne tarif_trimestriel est conservée pour l'historique.
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS tarif_semestriel NUMERIC(10,2) DEFAULT 0;
