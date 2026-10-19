-- ════════════════════════════════════════════════════════════════
-- 29 — Boutique : capital et répartition entre associés, SÉPARÉS du club
--   • capital_boutique     : capital investi par l'associé dans la boutique (à lui rembourser)
--   • deja_verse_boutique  : déjà versé à l'associé au titre de la boutique
--   Ce qui lui revient (boutique) = capital boutique + sa part du bénéfice de la boutique − déjà versé
--   Mêmes parts que le club (colonne parts). Le club et la boutique restent deux calculs indépendants.
-- Prérequis : scripts 22 (associés) et 27 (boutique). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS capital_boutique    NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS deja_verse_boutique NUMERIC(12,2) NOT NULL DEFAULT 0;

NOTIFY pgrst, 'reload schema';
