-- ════════════════════════════════════════════════════════════════
-- 14 — Rémunération « Par semaine » (ex. agents d'entretien)
-- Montant hebdomadaire ; au paiement : nombre de semaines × montant
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS montant_semaine NUMERIC(10,2) DEFAULT 0;

NOTIFY pgrst, 'reload schema';
