-- ════════════════════════════════════════════════════════════════
-- 24 — Associés : complète la table si elle existait déjà avant le script 22
--   (le script 22 ne recrée pas une table existante : des colonnes pouvaient manquer, ex. « actif »)
--   Sans risque : n'ajoute que les colonnes absentes, ne supprime rien.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS prenom      TEXT;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS nom         TEXT DEFAULT '';
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS pourcentage NUMERIC(5,2) DEFAULT 0;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS parts       NUMERIC(8,2) NOT NULL DEFAULT 1;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS actif       BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS created_at  TIMESTAMPTZ DEFAULT now();

-- Les associés déjà saisis sont actifs
UPDATE public.associes SET actif = true WHERE actif IS NULL;

-- Droits (module « associes »)
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
