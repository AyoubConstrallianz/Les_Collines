-- ════════════════════════════════════════════════════════════════
-- 38 — Assurance : déclarer un client à l'assureur sans paiement d'assurance
--   Date de la déclaration faite depuis la fiche client (vide = aucune).
--   Valable 1 an : un paiement d'assurance fait pendant cette année est
--   considéré comme déjà déclaré (il n'apparaît pas dans « À déclarer »).
--   Nécessite le script 37.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS assurance_declaree_le DATE;

NOTIFY pgrst, 'reload schema';
