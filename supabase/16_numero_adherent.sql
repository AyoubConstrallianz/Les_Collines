-- ════════════════════════════════════════════════════════════════
-- 16 — Numéro d'adhérent (unique, attribué automatiquement)
--   • Les clients existants sont numérotés 1, 2, 3… par date d'inscription
--   • Les nouveaux clients (fiche, paiement, import Excel) reçoivent le numéro suivant
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS numero_adherent INT;

-- Numérotation des clients existants (les plus anciens en premier)
WITH ordre AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY date_inscription NULLS LAST, created_at, id) AS n
  FROM public.clients
  WHERE numero_adherent IS NULL
)
UPDATE public.clients c
SET numero_adherent = o.n + COALESCE((SELECT MAX(numero_adherent) FROM public.clients), 0)
FROM ordre o
WHERE c.id = o.id;

-- Séquence pour les nouveaux clients, calée sur le dernier numéro
CREATE SEQUENCE IF NOT EXISTS public.clients_numero_adherent_seq;
SELECT setval('public.clients_numero_adherent_seq', COALESCE((SELECT MAX(numero_adherent) FROM public.clients), 0) + 1, false);

ALTER TABLE public.clients ALTER COLUMN numero_adherent SET DEFAULT nextval('public.clients_numero_adherent_seq');
ALTER SEQUENCE public.clients_numero_adherent_seq OWNED BY public.clients.numero_adherent;

CREATE UNIQUE INDEX IF NOT EXISTS clients_numero_adherent_uniq ON public.clients (numero_adherent);

NOTIFY pgrst, 'reload schema';
