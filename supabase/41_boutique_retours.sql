-- ════════════════════════════════════════════════════════════════
-- 41 — Boutique : retours de marchandise
--   • Un retour = une ligne de vente avec une quantité NÉGATIVE, reliée à la vente d'origine (retour_de).
--     Montant = quantité × prix remboursé → négatif : la caisse baisse.
--   • Le stock remonte tout seul (mouvement de stock « Retour »).
--   • note : motif du retour.
--   • Une vente qui a des retours ne peut pas être supprimée (supprimer d'abord le retour).
-- Prérequis : scripts 27 et 34 (boutique avec stock, factures). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS retour_de UUID REFERENCES public.ventes(id) ON DELETE RESTRICT;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS note TEXT;
CREATE INDEX IF NOT EXISTS ventes_retour_de_idx ON public.ventes (retour_de);

-- Quantité : positive pour une vente, négative pour un retour (toujours relié à une vente)
ALTER TABLE public.ventes DROP CONSTRAINT IF EXISTS ventes_quantite_positive;
DO $$ BEGIN
  ALTER TABLE public.ventes ADD CONSTRAINT ventes_quantite_non_nulle CHECK (quantite <> 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.ventes ADD CONSTRAINT ventes_retour_lie CHECK (quantite > 0 OR retour_de IS NOT NULL);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Mouvement de stock d'une vente : « Vente » (sortie) ou « Retour » (entrée)
CREATE OR REPLACE FUNCTION public.vente_sortie_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.produit_id IS NOT DISTINCT FROM OLD.produit_id AND NEW.quantite = OLD.quantite
     AND NEW.date_vente = OLD.date_vente AND NEW.prix_vente = OLD.prix_vente THEN
    RETURN NULL;                                    -- rien qui touche au stock
  END IF;
  IF TG_OP IN ('UPDATE','DELETE') THEN
    DELETE FROM public.stock_mouvements WHERE vente_id = OLD.id;
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.produit_id IS NOT NULL THEN
    INSERT INTO public.stock_mouvements (date_mouvement, produit_id, type, quantite, prix_unitaire, vente_id)
    VALUES (NEW.date_vente, NEW.produit_id, CASE WHEN NEW.quantite < 0 THEN 'Retour' ELSE 'Vente' END,
            -NEW.quantite, NEW.prix_vente, NEW.id);
  END IF;
  RETURN NULL;
END;
$$;

-- Entrées de stock : par une facture fournisseur, ou par le retour d'un article vendu
CREATE OR REPLACE FUNCTION public.entree_stock_par_facture()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.quantite > 0 AND NEW.facture_id IS NULL AND NOT (NEW.type = 'Retour' AND NEW.vente_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Les entrées de stock se font uniquement par une facture fournisseur (Boutique → Factures fournisseurs).';
  END IF;
  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
