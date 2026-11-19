-- ════════════════════════════════════════════════════════════════
-- 54 — Historique des coachs de chaque sport
--   Une ligne = un coach encadre un sport du date_debut au date_fin
--   (date_fin vide = encore en place aujourd'hui).
--   Au changement d'entraîneur (Sports & Tarifs → Modifier), l'application
--   ferme la ligne de l'ancien coach la veille et ouvre celle du nouveau.
--   Coachs payés au pourcentage : le CA du sport est partagé selon les jours
--   encadrés par chacun dans le mois.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.sports_coachs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  sport_id    TEXT NOT NULL,
  coach       TEXT NOT NULL,
  date_debut  DATE NOT NULL,
  date_fin    DATE,
  created_by  UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS sports_coachs_sport_idx ON public.sports_coachs (sport_id, date_debut);

-- Coachs actuels : en place depuis toujours (une seule fois)
INSERT INTO public.sports_coachs (sport_id, coach, date_debut)
SELECT s.id::text, s.coach, DATE '2000-01-01'
FROM public.sports s
WHERE s.coach IS NOT NULL AND btrim(s.coach) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.sports_coachs c WHERE c.sport_id = s.id::text);

-- ── Sécurité (RLS) : lecture pour les utilisateurs connectés, écriture = droits « Sports & Tarifs » ──
ALTER TABLE public.sports_coachs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sports_coachs_select" ON public.sports_coachs;
DROP POLICY IF EXISTS "sports_coachs_insert" ON public.sports_coachs;
DROP POLICY IF EXISTS "sports_coachs_update" ON public.sports_coachs;
DROP POLICY IF EXISTS "sports_coachs_delete" ON public.sports_coachs;
CREATE POLICY "sports_coachs_select" ON public.sports_coachs FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "sports_coachs_insert" ON public.sports_coachs FOR INSERT WITH CHECK (public.has_perm('sports','ecrire'));
CREATE POLICY "sports_coachs_update" ON public.sports_coachs FOR UPDATE USING (public.has_perm('sports','ecrire'));
CREATE POLICY "sports_coachs_delete" ON public.sports_coachs FOR DELETE USING (public.has_perm('sports','ecrire'));

NOTIFY pgrst, 'reload schema';
