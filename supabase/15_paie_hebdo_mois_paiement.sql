-- ════════════════════════════════════════════════════════════════
-- 15 — Paie hebdomadaire : rattacher chaque paiement au mois du lundi de paie
--      (semaine 28/09 → 04/10, payée le lundi 05/10 → octobre)
-- Corrige les paiements hebdomadaires déjà enregistrés. Sans effet s'il n'y en a pas.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

UPDATE public.salaires_paie
SET mois = to_char((detail->>'semaine_debut')::date + 7, 'YYYY-MM')
WHERE detail ? 'semaine_debut'
  AND mois IS DISTINCT FROM to_char((detail->>'semaine_debut')::date + 7, 'YYYY-MM');
