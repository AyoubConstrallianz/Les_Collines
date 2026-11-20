-- ════════════════════════════════════════════════════════════════
-- 57 — Boutique : vente payée en partie, reste à payer
--   ventes.montant_paye : montant payé le jour de la vente pour cette ligne
--                         (vide = ligne payée en entier, comme avant)
--   ventes_reglements   : règlements du reste, payés plus tard (date, montant, mode)
--   Reste d'une ligne = quantité × prix de vente − montant payé − règlements.
--   La caisse et le rapport journalier ne comptent que l'argent reçu, le jour où il est reçu.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS montant_paye NUMERIC(10,2);

CREATE TABLE IF NOT EXISTS public.ventes_reglements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_reglement  DATE NOT NULL DEFAULT CURRENT_DATE,
  vente_id        UUID NOT NULL REFERENCES public.ventes(id) ON DELETE CASCADE,
  montant         NUMERIC(10,2) NOT NULL CHECK (montant > 0),
  mode            TEXT NOT NULL DEFAULT 'Espèces',
  note            TEXT,
  created_by      UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS ventes_reglements_vente_idx ON public.ventes_reglements (vente_id);
CREATE INDEX IF NOT EXISTS ventes_reglements_date_idx ON public.ventes_reglements (date_reglement);

-- ── Sécurité (RLS) : mêmes droits que la boutique ───────────────────────────
ALTER TABLE public.ventes_reglements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "ventes_reglements_select" ON public.ventes_reglements;
DROP POLICY IF EXISTS "ventes_reglements_insert" ON public.ventes_reglements;
DROP POLICY IF EXISTS "ventes_reglements_delete" ON public.ventes_reglements;
CREATE POLICY "ventes_reglements_select" ON public.ventes_reglements FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "ventes_reglements_insert" ON public.ventes_reglements FOR INSERT WITH CHECK (public.has_perm('boutique','ecrire'));
CREATE POLICY "ventes_reglements_delete" ON public.ventes_reglements FOR DELETE USING (public.has_perm('boutique','supprimer'));

NOTIFY pgrst, 'reload schema';
