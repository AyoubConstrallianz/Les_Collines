-- ════════════════════════════════════════════════════════════════
-- 13 — Mode de rémunération des coachs & salariés
--   • Mensuel      : salaire fixe (colonne salaire)
--   • Groupe       : nb_groupes × montant_groupe
--   • Pourcentage  : pourcentage × CA du mois des disciplines du coach
-- Le détail du calcul est conservé avec chaque paiement (reçu PDF).
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS remuneration   TEXT DEFAULT 'Mensuel';
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS nb_groupes     INT DEFAULT 0;
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS montant_groupe NUMERIC(10,2) DEFAULT 0;
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS pourcentage    NUMERIC(5,2) DEFAULT 0;

ALTER TABLE public.salaires_paie ADD COLUMN IF NOT EXISTS detail JSONB;

NOTIFY pgrst, 'reload schema';
