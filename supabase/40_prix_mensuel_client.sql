-- ════════════════════════════════════════════════════════════════
-- 40 — Prix mensuel personnalisé par client
--   tarif_mensuel_perso : prix mensuel que paie ce client (ex. 200 DH au lieu de 250 DH).
--   Vide = tarif normal de ses sports. Trimestriel / semestriel / annuel = ce prix × nombre de mois.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS tarif_mensuel_perso NUMERIC(10,2);

NOTIFY pgrst, 'reload schema';
