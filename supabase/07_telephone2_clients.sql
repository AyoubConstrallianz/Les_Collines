-- ════════════════════════════════════════════════════════════════
-- 07 — Deuxième numéro de téléphone pour les clients
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS telephone2 TEXT;
