-- ════════════════════════════════════════════════════════════════
-- 61 — Boutique : packs par discipline
--   • boutique_packs : un pack = nom, discipline, prix du pack et liste
--     d'articles du stock (articles : [{"produit_id": "...", "quantite": 1}, …])
--   • ventes.pack    : nom du pack vendu (affiché dans la liste et le reçu)
--   • Vendre un pack ajoute ses articles à la vente : le stock de chaque
--     article diminue comme pour une vente normale.
-- Prérequis : script 27 (boutique avec stock). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.boutique_packs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom         TEXT NOT NULL,
  sport       TEXT,
  prix        NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (prix >= 0),
  articles    JSONB NOT NULL DEFAULT '[]'::jsonb,
  actif       BOOLEAN NOT NULL DEFAULT true,
  created_by  UUID DEFAULT auth.uid(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS boutique_packs_sport_idx ON public.boutique_packs (sport);

ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS pack TEXT;

-- ── Sécurité (RLS) : mêmes droits que la boutique ───────────────────────────
ALTER TABLE public.boutique_packs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "boutique_packs_select" ON public.boutique_packs;
DROP POLICY IF EXISTS "boutique_packs_insert" ON public.boutique_packs;
DROP POLICY IF EXISTS "boutique_packs_update" ON public.boutique_packs;
DROP POLICY IF EXISTS "boutique_packs_delete" ON public.boutique_packs;
CREATE POLICY "boutique_packs_select" ON public.boutique_packs FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "boutique_packs_insert" ON public.boutique_packs FOR INSERT WITH CHECK (public.has_perm('boutique','ecrire'));
CREATE POLICY "boutique_packs_update" ON public.boutique_packs FOR UPDATE USING (public.has_perm('boutique','ecrire'));
CREATE POLICY "boutique_packs_delete" ON public.boutique_packs FOR DELETE USING (public.has_perm('boutique','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les packs ─────────────
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.boutique_packs';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.boutique_packs FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
