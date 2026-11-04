-- ════════════════════════════════════════════════════════════════
-- 39 — Paiements partiels (reste à payer)
--   montant_du : montant à payer d'une ligne payée en partie (vide = payée en entier).
--   reste_de   : pour un paiement de type « Complément », la ligne dont il règle le reste.
--   Reste à payer = montant_du − montant − somme des compléments.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.paiements ADD COLUMN IF NOT EXISTS montant_du NUMERIC;
ALTER TABLE public.paiements ADD COLUMN IF NOT EXISTS reste_de UUID REFERENCES public.paiements(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS paiements_reste_de_idx ON public.paiements(reste_de);

NOTIFY pgrst, 'reload schema';
