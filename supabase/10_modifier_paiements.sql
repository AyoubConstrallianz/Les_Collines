-- ════════════════════════════════════════════════════════════════
-- 10 — Autoriser la modification des paiements (bouton « Modifier »)
-- Réservé aux utilisateurs ayant le droit « écrire » sur les paiements.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "paie_update" ON public.paiements;
CREATE POLICY "paie_update" ON public.paiements FOR UPDATE
  USING (public.has_perm('paiements','ecrire'))
  WITH CHECK (public.has_perm('paiements','ecrire'));
