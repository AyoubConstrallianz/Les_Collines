-- ════════════════════════════════════════════════════════════════
-- 18 — Numéro d'adhérent : attribution automatique des NOUVEAUX clients
--   • Un client créé SANS numéro reçoit « dernier numéro + 1 »
--   • Un numéro saisi à la main (fiche ou import Excel) est toujours respecté
--   • Tant qu'aucun client n'a de numéro (saisie manuelle pas commencée), rien n'est attribué :
--     les numéros que vous saisissez ensuite ne risquent donc pas d'entrer en conflit
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.attribuer_numero_adherent()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_max INT;
BEGIN
  IF NEW.numero_adherent IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- Verrou : deux créations simultanées ne peuvent pas obtenir le même numéro
  PERFORM pg_advisory_xact_lock(hashtext('numero_adherent'));
  SELECT MAX(numero_adherent) INTO v_max FROM public.clients;
  IF v_max IS NOT NULL THEN
    NEW.numero_adherent := v_max + 1;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_numero_adherent ON public.clients;
CREATE TRIGGER trg_numero_adherent
  BEFORE INSERT ON public.clients
  FOR EACH ROW EXECUTE FUNCTION public.attribuer_numero_adherent();

NOTIFY pgrst, 'reload schema';
