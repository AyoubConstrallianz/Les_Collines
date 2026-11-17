-- ════════════════════════════════════════════════════════════════
-- 53 — Avances des associés prises dans la caisse
--   Deux nouvelles natures de mouvement dans versements_associes :
--   • 'Avance'        : l'associé prend de l'argent dans la caisse (sort de la caisse)
--   • 'Retour avance' : l'associé rend l'argent à la caisse (rentre dans la caisse)
--   Une avance en cours est déduite de sa part au partage de la caisse,
--   ou remboursée en espèces (en totalité ou en partie).
-- Prérequis : script 30. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.versements_associes'::regclass AND contype = 'c'
             AND pg_get_constraintdef(oid) ILIKE '%nature%'
  LOOP
    EXECUTE format('ALTER TABLE public.versements_associes DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;

ALTER TABLE public.versements_associes ADD CONSTRAINT versements_associes_nature_check
  CHECK (nature IN ('Bénéfice', 'Capital', 'Avance', 'Retour avance'));

NOTIFY pgrst, 'reload schema';
