-- ════════════════════════════════════════════════════════════════
-- 30 — Versements aux associés (club et boutique, séparés) + caisse
--   • Chaque versement : associé, date, montant, nature (bénéfice / remboursement du capital), mode, note
--   • « Déjà versé » = somme des versements (plus de saisie manuelle)
--   • Les montants « déjà versé » saisis à la main avant ce script sont repris en un versement « Report »
--   • Caisse = capital apporté + encaissements − dépenses − versements (calculée dans l'application)
-- Prérequis : script 28 (et 29 pour la boutique). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.versements_associes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_versement  DATE NOT NULL DEFAULT CURRENT_DATE,
  associe_id      UUID NOT NULL REFERENCES public.associes(id) ON DELETE CASCADE,
  activite        TEXT NOT NULL DEFAULT 'club' CHECK (activite IN ('club','boutique')),
  nature          TEXT NOT NULL DEFAULT 'Bénéfice' CHECK (nature IN ('Bénéfice','Capital')),
  montant         NUMERIC(12,2) NOT NULL CHECK (montant > 0),
  mode            TEXT NOT NULL DEFAULT 'Espèces',
  note            TEXT,
  created_by      UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS versements_associes_idx ON public.versements_associes (activite, date_versement);

-- ── Reprise des montants « déjà versé » saisis à la main (une seule fois) ──
INSERT INTO public.versements_associes (associe_id, activite, nature, montant, note)
SELECT a.id, 'club', 'Bénéfice', a.deja_verse, 'Report : déjà versé avant le suivi des versements'
FROM public.associes a
WHERE a.deja_verse > 0
  AND NOT EXISTS (SELECT 1 FROM public.versements_associes v WHERE v.associe_id = a.id AND v.activite = 'club');
UPDATE public.associes SET deja_verse = 0 WHERE deja_verse <> 0;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'associes' AND column_name = 'deja_verse_boutique') THEN
    EXECUTE $q$
      INSERT INTO public.versements_associes (associe_id, activite, nature, montant, note)
      SELECT a.id, 'boutique', 'Bénéfice', a.deja_verse_boutique, 'Report : déjà versé avant le suivi des versements'
      FROM public.associes a
      WHERE a.deja_verse_boutique > 0
        AND NOT EXISTS (SELECT 1 FROM public.versements_associes v WHERE v.associe_id = a.id AND v.activite = 'boutique')
    $q$;
    EXECUTE 'UPDATE public.associes SET deja_verse_boutique = 0 WHERE deja_verse_boutique <> 0';
  END IF;
END $$;

-- ── Sécurité (RLS) : module « associes » ───────────────────────────────────
ALTER TABLE public.versements_associes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "versements_associes_select" ON public.versements_associes;
DROP POLICY IF EXISTS "versements_associes_insert" ON public.versements_associes;
DROP POLICY IF EXISTS "versements_associes_update" ON public.versements_associes;
DROP POLICY IF EXISTS "versements_associes_delete" ON public.versements_associes;
CREATE POLICY "versements_associes_select" ON public.versements_associes FOR SELECT USING (public.has_perm('associes','lire'));
CREATE POLICY "versements_associes_insert" ON public.versements_associes FOR INSERT WITH CHECK (public.has_perm('associes','ecrire'));
CREATE POLICY "versements_associes_update" ON public.versements_associes FOR UPDATE USING (public.has_perm('associes','ecrire'));
CREATE POLICY "versements_associes_delete" ON public.versements_associes FOR DELETE USING (public.has_perm('associes','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les versements ─────────
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.versements_associes';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.versements_associes FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
