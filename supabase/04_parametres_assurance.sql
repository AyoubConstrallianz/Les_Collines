-- ════════════════════════════════════════════════════════════════
-- 04 — Paramètres généraux (frais d'assurance par saison)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.parametres (
  cle         TEXT PRIMARY KEY,
  valeur      TEXT,
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.parametres ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "parametres_select" ON public.parametres;
DROP POLICY IF EXISTS "parametres_insert" ON public.parametres;
DROP POLICY IF EXISTS "parametres_update" ON public.parametres;

-- Lecture : tout utilisateur connecté (nécessaire au formulaire de paiement)
CREATE POLICY "parametres_select" ON public.parametres FOR SELECT
  USING (auth.role() = 'authenticated');
-- Écriture : mêmes droits que la gestion des Sports & Tarifs
CREATE POLICY "parametres_insert" ON public.parametres FOR INSERT
  WITH CHECK (public.has_perm('sports','ecrire'));
CREATE POLICY "parametres_update" ON public.parametres FOR UPDATE
  USING (public.has_perm('sports','ecrire'));

-- Montant unique de l'assurance (DH), valable une saison sportive (septembre → août)
INSERT INTO public.parametres (cle, valeur) VALUES ('assurance_montant', '0')
  ON CONFLICT (cle) DO NOTHING;
