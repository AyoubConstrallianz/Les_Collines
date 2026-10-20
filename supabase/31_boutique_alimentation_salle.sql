-- ════════════════════════════════════════════════════════════════
-- 31 — Alimenter la boutique avec la caisse de la salle
--   • Chaque alimentation (date, montant, note) ajoute de l'argent dans la caisse de la boutique
--   • et devient automatiquement une CHARGE de la salle (catégorie « Alimentation boutique »)
--   • Modifier / supprimer l'alimentation modifie / supprime la charge (et inversement : supprimer la charge
--     dans « Charges & Dépenses » supprime l'alimentation)
-- Prérequis : script 27 (boutique). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.boutique_apports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_apport  DATE NOT NULL DEFAULT CURRENT_DATE,
  montant      NUMERIC(12,2) NOT NULL CHECK (montant > 0),
  note         TEXT,
  charge_id    UUID REFERENCES public.charges(id) ON DELETE CASCADE,
  created_by   UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS boutique_apports_date_idx ON public.boutique_apports (date_apport);

-- Charge de la salle créée / mise à jour avec l'alimentation
CREATE OR REPLACE FUNCTION public.boutique_apport_charge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.charges (libelle, montant, categorie, date_charge, recurrence)
    VALUES ('Alimentation de la boutique' || coalesce(' — ' || nullif(trim(NEW.note), ''), ''),
            NEW.montant, 'Alimentation boutique', NEW.date_apport, 'Ponctuelle')
    RETURNING id INTO NEW.charge_id;
  ELSIF NEW.charge_id IS NOT NULL THEN
    UPDATE public.charges
    SET montant = NEW.montant, date_charge = NEW.date_apport,
        libelle = 'Alimentation de la boutique' || coalesce(' — ' || nullif(trim(NEW.note), ''), '')
    WHERE id = NEW.charge_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_apport_charge ON public.boutique_apports;
CREATE TRIGGER trg_apport_charge BEFORE INSERT OR UPDATE ON public.boutique_apports
  FOR EACH ROW EXECUTE FUNCTION public.boutique_apport_charge();

-- Alimentation supprimée → charge supprimée
CREATE OR REPLACE FUNCTION public.boutique_apport_suppr_charge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF OLD.charge_id IS NOT NULL THEN
    DELETE FROM public.charges WHERE id = OLD.charge_id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_apport_suppr_charge ON public.boutique_apports;
CREATE TRIGGER trg_apport_suppr_charge AFTER DELETE ON public.boutique_apports
  FOR EACH ROW EXECUTE FUNCTION public.boutique_apport_suppr_charge();

-- ── Sécurité (RLS) : voir = boutique ; alimenter / supprimer = boutique ET charges ──
ALTER TABLE public.boutique_apports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "boutique_apports_select" ON public.boutique_apports;
DROP POLICY IF EXISTS "boutique_apports_insert" ON public.boutique_apports;
DROP POLICY IF EXISTS "boutique_apports_update" ON public.boutique_apports;
DROP POLICY IF EXISTS "boutique_apports_delete" ON public.boutique_apports;
CREATE POLICY "boutique_apports_select" ON public.boutique_apports FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "boutique_apports_insert" ON public.boutique_apports FOR INSERT
  WITH CHECK (public.has_perm('boutique','ecrire') AND public.has_perm('charges','ecrire'));
CREATE POLICY "boutique_apports_update" ON public.boutique_apports FOR UPDATE
  USING (public.has_perm('boutique','ecrire') AND public.has_perm('charges','ecrire'));
CREATE POLICY "boutique_apports_delete" ON public.boutique_apports FOR DELETE
  USING (public.has_perm('boutique','supprimer') AND public.has_perm('charges','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les alimentations ─────
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.boutique_apports';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.boutique_apports FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
