-- ════════════════════════════════════════════════════════════════
-- 23 — Associés : répartition du bénéfice PAR PARTS
--   • Chaque associé a un nombre de parts ; sa part = bénéfice × ses parts ÷ total des parts
--   • Najib : 1 part (1/3) — Mohamed : 2 parts (2/3)
--     (créés s'ils n'existent pas encore ; le nom de famille se complète dans l'application)
-- Prérequis : script 22 (table associes)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.associes ADD COLUMN IF NOT EXISTS parts NUMERIC(8,2) NOT NULL DEFAULT 1 CHECK (parts >= 0);

INSERT INTO public.associes (prenom, nom, parts)
SELECT 'Najib', '', 1
WHERE NOT EXISTS (SELECT 1 FROM public.associes WHERE lower(prenom) = 'najib');

INSERT INTO public.associes (prenom, nom, parts)
SELECT 'Mohamed', '', 2
WHERE NOT EXISTS (SELECT 1 FROM public.associes WHERE lower(prenom) = 'mohamed');

UPDATE public.associes SET parts = 1 WHERE lower(prenom) = 'najib';
UPDATE public.associes SET parts = 2 WHERE lower(prenom) = 'mohamed';

NOTIFY pgrst, 'reload schema';
