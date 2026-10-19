-- ════════════════════════════════════════════════════════════════
-- 28 — Associés : capital investi + ce qui revient à chaque associé
--   • capital     : capital investi par l'associé (à lui rembourser)
--   • deja_verse  : total déjà versé à l'associé (remboursement + bénéfices payés)
--   Ce qui lui revient = capital + sa part du bénéfice cumulé − déjà versé (calculé dans l'application)
--   • Parts : Najib EL HAIDAOUI = 1 part, Mohamed KHAYOUSSEF = 2 parts (créés s'ils n'existent pas)
-- Prérequis : script 22 (table associes). À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS parts      NUMERIC(8,2)  NOT NULL DEFAULT 1;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS actif      BOOLEAN       NOT NULL DEFAULT true;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS capital    NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS deja_verse NUMERIC(12,2) NOT NULL DEFAULT 0;

INSERT INTO public.associes (prenom, nom, parts)
SELECT 'Najib', 'EL HAIDAOUI', 1
WHERE NOT EXISTS (SELECT 1 FROM public.associes WHERE lower(prenom) = 'najib');
INSERT INTO public.associes (prenom, nom, parts)
SELECT 'Mohamed', 'KHAYOUSSEF', 2
WHERE NOT EXISTS (SELECT 1 FROM public.associes WHERE lower(prenom) = 'mohamed');

UPDATE public.associes SET nom = 'EL HAIDAOUI', parts = 1 WHERE lower(prenom) = 'najib';
UPDATE public.associes SET nom = 'KHAYOUSSEF',  parts = 2 WHERE lower(prenom) = 'mohamed';

NOTIFY pgrst, 'reload schema';
