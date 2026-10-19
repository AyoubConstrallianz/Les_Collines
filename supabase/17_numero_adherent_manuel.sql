-- ════════════════════════════════════════════════════════════════
-- 17 — Numéro d'adhérent : saisie MANUELLE
--   • Efface les numéros attribués automatiquement par le script 16
--   • Supprime l'attribution automatique (les nouveaux clients n'ont plus de numéro par défaut)
--   • Le numéro reste unique : deux clients ne peuvent pas avoir le même
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS numero_adherent INT;
ALTER TABLE public.clients ALTER COLUMN numero_adherent DROP DEFAULT;
DROP SEQUENCE IF EXISTS public.clients_numero_adherent_seq;
UPDATE public.clients SET numero_adherent = NULL;
CREATE UNIQUE INDEX IF NOT EXISTS clients_numero_adherent_uniq ON public.clients (numero_adherent);

NOTIFY pgrst, 'reload schema';
