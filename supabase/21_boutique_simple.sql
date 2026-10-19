-- ════════════════════════════════════════════════════════════════
-- 21 — Boutique simplifiée : une vente = client, date, article, prix d'achat, prix de vente
--   • Pas de gestion de stock
--   • Fonctionne que le script 20 ait été exécuté ou non
--   • Les tables de stock du script 20 (produits, tailles, lignes) sont supprimées
--     UNIQUEMENT si elles sont vides (aucune donnée perdue)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.ventes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date_vente  DATE NOT NULL DEFAULT CURRENT_DATE,
  client_id   UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  client_nom  TEXT,
  created_by  UUID DEFAULT auth.uid(),
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS article    TEXT;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS prix_achat NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS prix_vente NUMERIC(10,2) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS ventes_date_idx ON public.ventes (date_vente);

-- ── Sécurité (RLS) : module « boutique » ───────────────────────────────────
ALTER TABLE public.ventes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ventes_select" ON public.ventes;
DROP POLICY IF EXISTS "ventes_insert" ON public.ventes;
DROP POLICY IF EXISTS "ventes_update" ON public.ventes;
DROP POLICY IF EXISTS "ventes_delete" ON public.ventes;
CREATE POLICY "ventes_select" ON public.ventes FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "ventes_insert" ON public.ventes FOR INSERT WITH CHECK (public.has_perm('boutique','ecrire'));
CREATE POLICY "ventes_update" ON public.ventes FOR UPDATE USING (public.has_perm('boutique','ecrire'));
CREATE POLICY "ventes_delete" ON public.ventes FOR DELETE USING (public.has_perm('boutique','supprimer'));

-- ── Nettoyage du système de stock (script 20), seulement s'il n'a pas servi ─
DO $$
BEGIN
  IF to_regclass('public.vente_lignes') IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.vente_lignes)
     AND NOT EXISTS (SELECT 1 FROM public.produit_variantes)
     AND NOT EXISTS (SELECT 1 FROM public.produits) THEN
    DROP TABLE public.vente_lignes;
    DROP TABLE public.produit_variantes;
    DROP TABLE public.produits;
    DROP FUNCTION IF EXISTS public.maj_stock_vente();
    RAISE NOTICE 'Tables de stock vides : supprimées.';
  ELSIF to_regclass('public.vente_lignes') IS NOT NULL THEN
    RAISE NOTICE 'Tables de stock conservées (elles contiennent des données).';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
