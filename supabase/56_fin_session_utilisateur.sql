-- ════════════════════════════════════════════════════════════════
-- 56 — Fin de session par utilisateur (déconnexion après inactivité)
--   profils.inactivite_minutes :
--     vide = par défaut (10 minutes ; jamais pour le super admin)
--     0    = jamais déconnecté
--     n    = déconnecté après n minutes sans activité
--   Réglé dans Utilisateurs → Modifier. Seuls le super admin et les
--   utilisateurs qui peuvent modifier « Utilisateurs » peuvent le changer
--   (un utilisateur ne peut pas changer sa propre durée).
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.profils ADD COLUMN IF NOT EXISTS inactivite_minutes INTEGER;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                 WHERE conrelid = 'public.profils'::regclass AND conname = 'profils_inactivite_minutes_check') THEN
    ALTER TABLE public.profils ADD CONSTRAINT profils_inactivite_minutes_check
      CHECK (inactivite_minutes IS NULL OR (inactivite_minutes >= 0 AND inactivite_minutes <= 1440));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.proteger_inactivite_profil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.inactivite_minutes IS DISTINCT FROM OLD.inactivite_minutes
     AND NOT EXISTS (SELECT 1 FROM public.profils a WHERE a.id = auth.uid() AND a.role = 'super_admin')
     AND NOT EXISTS (SELECT 1 FROM public.habilitations h
                     WHERE h.user_id = auth.uid() AND h.module = 'utilisateurs' AND h.peut_ecrire) THEN
    NEW.inactivite_minutes := OLD.inactivite_minutes;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_inactivite_profil ON public.profils;
CREATE TRIGGER trg_proteger_inactivite_profil
  BEFORE UPDATE ON public.profils
  FOR EACH ROW EXECUTE FUNCTION public.proteger_inactivite_profil();

NOTIFY pgrst, 'reload schema';
