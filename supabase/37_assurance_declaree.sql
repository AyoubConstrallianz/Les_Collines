-- ════════════════════════════════════════════════════════════════
-- 37 — Assurance : déclaration du client auprès de l'assureur
--   Date à laquelle le paiement d'assurance a été déclaré à l'assurance
--   (vide = pas encore déclaré). Un nouveau paiement d'assurance (renouvellement)
--   repart « non déclaré » : le client est à déclarer de nouveau.
--   Modification réservée aux utilisateurs qui peuvent modifier les paiements (script 10).
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.paiements ADD COLUMN IF NOT EXISTS assurance_declaree_le DATE;

NOTIFY pgrst, 'reload schema';
