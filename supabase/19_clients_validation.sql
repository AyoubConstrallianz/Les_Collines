-- ════════════════════════════════════════════════════════════════
-- 19 — Validation des nouveaux clients saisis par un « employé »
--   • Un client créé par un profil « employe » passe automatiquement en statut « En attente »
--   • Seuls les profils gérant / super admin peuvent le valider (statut → Actif)
--   • Appliqué côté base : un employé ne peut pas contourner la règle
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.clients_validation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT := public.get_my_role();
BEGIN
  IF v_role IS DISTINCT FROM 'employe' THEN
    RETURN NEW;                       -- gérant, super admin, réceptionniste, import…
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.statut := 'En attente';       -- nouveau client saisi par un employé
  ELSIF OLD.statut = 'En attente' THEN
    NEW.statut := 'En attente';       -- un employé ne peut pas valider
  ELSIF NEW.statut = 'En attente' THEN
    NEW.statut := OLD.statut;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clients_validation ON public.clients;
CREATE TRIGGER trg_clients_validation
  BEFORE INSERT OR UPDATE ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.clients_validation();

NOTIFY pgrst, 'reload schema';
