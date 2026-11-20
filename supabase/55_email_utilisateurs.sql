-- ════════════════════════════════════════════════════════════════
-- 55 — Afficher l'e-mail des comptes utilisateurs
--   L'e-mail de connexion est gardé par Supabase dans auth.users.
--   On le recopie dans profils.email (lu par « Gestion des utilisateurs »)
--   et un déclencheur le tient à jour (création de compte, changement d'e-mail).
--   Les mots de passe ne sont jamais recopiés (Supabase ne garde qu'une empreinte).
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.profils ADD COLUMN IF NOT EXISTS email TEXT;

-- Recopie des e-mails existants
UPDATE public.profils p
SET email = u.email
FROM auth.users u
WHERE u.id = p.id
  AND p.email IS DISTINCT FROM u.email;

-- Mise à jour automatique
CREATE OR REPLACE FUNCTION public.sync_email_profil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profils
  SET email = NEW.email
  WHERE id = NEW.id
    AND email IS DISTINCT FROM NEW.email;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_email_profil ON auth.users;
CREATE TRIGGER trg_sync_email_profil
  AFTER INSERT OR UPDATE OF email ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_email_profil();

-- Nouveau profil (créé après le compte) : e-mail repris du compte
CREATE OR REPLACE FUNCTION public.email_nouveau_profil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.email IS NULL OR NEW.email = '' THEN
    SELECT u.email INTO NEW.email FROM auth.users u WHERE u.id = NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_email_nouveau_profil ON public.profils;
CREATE TRIGGER trg_email_nouveau_profil
  BEFORE INSERT ON public.profils
  FOR EACH ROW EXECUTE FUNCTION public.email_nouveau_profil();

NOTIFY pgrst, 'reload schema';
