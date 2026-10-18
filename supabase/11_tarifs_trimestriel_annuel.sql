-- ════════════════════════════════════════════════════════════════
-- 11 — Colonnes de tarifs manquantes sur les sports
--      (trimestriel 3 mois et annuel — utilisées par le formulaire Sports & Tarifs)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS tarif_trimestriel NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS tarif_annuel      NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS tarif_semestriel  NUMERIC(10,2) DEFAULT 0;

-- Recharger le cache de l'API pour que les colonnes soient visibles immédiatement
NOTIFY pgrst, 'reload schema';
