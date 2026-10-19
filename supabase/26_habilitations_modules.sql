-- ════════════════════════════════════════════════════════════════
-- 26 — Droits des utilisateurs : accepter tous les modules de l'application
--   La table « habilitations » n'acceptait que les modules d'origine
--   (dashboard, clients, paiements, sports, charges, salaires, planning, stats, utilisateurs).
--   Les droits sur Coaches & Salariés, Présence, Boutique, Associés… étaient refusés sans message.
--   Ce script retire cette liste fermée. Aucune donnée n'est modifiée.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- Ensuite : réenregistrez les droits des utilisateurs concernés (Utilisateurs → Modifier → Enregistrer).
-- ════════════════════════════════════════════════════════════════

DO $$
DECLARE c TEXT;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.habilitations'::regclass AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%module%'
  LOOP
    EXECUTE format('ALTER TABLE public.habilitations DROP CONSTRAINT %I', c);
    RAISE NOTICE 'Contrainte supprimée : %', c;
  END LOOP;
END $$;

-- Garde-fou minimal : un nom de module non vide
ALTER TABLE public.habilitations DROP CONSTRAINT IF EXISTS habilitations_module_non_vide;
ALTER TABLE public.habilitations ADD CONSTRAINT habilitations_module_non_vide CHECK (length(trim(module)) > 0);

NOTIFY pgrst, 'reload schema';
