-- ════════════════════════════════════════════════════════════════
-- 64 — Boutique : noms des articles en MAJUSCULES
--   • Tous les articles du stock et toutes les ventes déjà enregistrées
--     passent en majuscules (ex. « Gants de boxe » → « GANTS DE BOXE »).
--   • À l'avenir, tout nom d'article est mis en majuscules automatiquement,
--     quelle que soit la page qui l'enregistre (article, facture, vente).
--   Le stock, les prix et l'historique ne changent pas.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

-- ── Articles du stock ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.produit_nom_majuscule()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.nom := upper(trim(NEW.nom));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_produit_nom_majuscule ON public.produits;
CREATE TRIGGER trg_produit_nom_majuscule BEFORE INSERT OR UPDATE OF nom ON public.produits
  FOR EACH ROW EXECUTE FUNCTION public.produit_nom_majuscule();

-- ── Ventes (nom de l'article vendu) ────────────────────────────
CREATE OR REPLACE FUNCTION public.vente_article_majuscule()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.article IS NOT NULL THEN
    NEW.article := upper(trim(NEW.article));
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_vente_article_majuscule ON public.ventes;
CREATE TRIGGER trg_vente_article_majuscule BEFORE INSERT OR UPDATE OF article ON public.ventes
  FOR EACH ROW EXECUTE FUNCTION public.vente_article_majuscule();

-- ── Noms déjà enregistrés ──────────────────────────────────────
UPDATE public.produits
SET nom = upper(trim(nom))
WHERE nom IS DISTINCT FROM upper(trim(nom));

UPDATE public.ventes
SET article = upper(trim(article))
WHERE article IS NOT NULL
  AND article IS DISTINCT FROM upper(trim(article));

NOTIFY pgrst, 'reload schema';
