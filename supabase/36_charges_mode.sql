-- ════════════════════════════════════════════════════════════════
-- 36 — Charges : mode de paiement (Espèces, Virement, Chèque)
--   Sert à la « caisse réelle » du club (Associés) : seules les dépenses payées en espèces
--   sortent de la caisse ; les virements et chèques passent par la banque.
--   Les charges déjà enregistrées sont considérées payées en espèces.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.charges ADD COLUMN IF NOT EXISTS mode TEXT NOT NULL DEFAULT 'Espèces';

NOTIFY pgrst, 'reload schema';
