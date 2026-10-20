-- ════════════════════════════════════════════════════════════════
-- 32 — Pack famille : tarif réduit par membre
--   • Sports : tarif « pack famille » mensuel, trimestriel, semestriel, annuel (par membre)
--   • Clients : case « pack famille » → ses paiements proposent le tarif famille
--   Un tarif famille vide (0) = tarif normal ; trimestriel/semestriel/annuel vides = mensuel famille × nb de mois
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.sports  ADD COLUMN IF NOT EXISTS famille_mensuel     NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports  ADD COLUMN IF NOT EXISTS famille_trimestriel NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports  ADD COLUMN IF NOT EXISTS famille_semestriel  NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports  ADD COLUMN IF NOT EXISTS famille_annuel      NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS pack_famille        BOOLEAN NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
