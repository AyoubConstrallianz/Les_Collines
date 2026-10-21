-- ════════════════════════════════════════════════════════════════
-- 35 — Boutique : case « Stock inventaire »
--   • stock_inventaire : quantité comptée lors du dernier inventaire (saisie avec le bouton « Inventaire »)
--   • date_inventaire  : date de ce comptage
--   Le stock calculé (factures − ventes) n'est PAS modifié : l'écart entre les deux est affiché.
-- Prérequis : script 27 (boutique). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS stock_inventaire INT;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS date_inventaire  DATE;
DO $$ BEGIN
  ALTER TABLE public.produits ADD CONSTRAINT produits_stock_inventaire_positif CHECK (stock_inventaire IS NULL OR stock_inventaire >= 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

NOTIFY pgrst, 'reload schema';
