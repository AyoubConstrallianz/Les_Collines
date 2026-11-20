-- ════════════════════════════════════════════════════════════════
-- 58 — Planning : autoriser la modification d'une séance
--   La table planning n'avait pas de règle de sécurité (RLS) pour la
--   modification : Supabase ignorait la modification sans erreur.
--   Modification autorisée aux utilisateurs qui ont « Écrire » sur Planning
--   (et au super admin).
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "planning_update" ON public.planning;
CREATE POLICY "planning_update" ON public.planning FOR UPDATE
  USING (public.has_perm('planning','ecrire'))
  WITH CHECK (public.has_perm('planning','ecrire'));

NOTIFY pgrst, 'reload schema';
