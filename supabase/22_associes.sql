-- ════════════════════════════════════════════════════════════════
-- 22 — Associés : pourcentage du bénéfice
--   • Une ligne par associé : prénom, nom, pourcentage du bénéfice
--   • La part de chaque associé est calculée dans l'application (bénéfice du mois × pourcentage)
--   • Droits : module « associes » (Utilisateurs → Habilitations) — super admin seulement par défaut
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.associes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  prenom       TEXT NOT NULL,
  nom          TEXT NOT NULL,
  pourcentage  NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (pourcentage >= 0 AND pourcentage <= 100),
  actif        BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.associes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "associes_select" ON public.associes;
DROP POLICY IF EXISTS "associes_insert" ON public.associes;
DROP POLICY IF EXISTS "associes_update" ON public.associes;
DROP POLICY IF EXISTS "associes_delete" ON public.associes;
CREATE POLICY "associes_select" ON public.associes FOR SELECT USING (public.has_perm('associes','lire'));
CREATE POLICY "associes_insert" ON public.associes FOR INSERT WITH CHECK (public.has_perm('associes','ecrire'));
CREATE POLICY "associes_update" ON public.associes FOR UPDATE USING (public.has_perm('associes','ecrire'));
CREATE POLICY "associes_delete" ON public.associes FOR DELETE USING (public.has_perm('associes','supprimer'));

NOTIFY pgrst, 'reload schema';
