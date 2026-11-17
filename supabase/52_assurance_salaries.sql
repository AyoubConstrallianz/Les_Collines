-- ════════════════════════════════════════════════════════════════
-- 52 — Assurance : déclarer des salariés à l'assureur
--   assurance_a_declarer : case cochée dans « À déclarer à l'assurance »
--                          (seuls les salariés cochés sont déclarés)
--   assurance_declaree_le : date de la déclaration (valable 1 an)
--   date_naissance        : demandée par l'assureur (fiche du salarié)
--   Modification réservée aux utilisateurs qui peuvent modifier « Coaches & Salariés ».
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS assurance_a_declarer BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS assurance_declaree_le DATE;
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS date_naissance DATE;

NOTIFY pgrst, 'reload schema';
