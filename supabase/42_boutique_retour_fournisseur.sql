-- ════════════════════════════════════════════════════════════════
-- 42 — Boutique : retours fournisseur
--   • boutique_retours_fournisseur : articles d'une facture fournisseur renvoyés au fournisseur
--   • Le stock baisse (mouvements « Retour fournisseur », quantité négative) : refusé si le stock est insuffisant
--   • On ne peut pas retourner plus que la quantité achetée sur la facture (moins les retours déjà faits)
--   • Le remboursement du fournisseur devient une charge NÉGATIVE de la salle (catégorie « Achats boutique ») :
--     la caisse remonte du montant remboursé. Supprimer le retour supprime ce remboursement et remet le stock.
--   • enregistrer_retour_fournisseur(retour, articles) : tout en une seule fois (tout ou rien)
-- Prérequis : script 34 (factures fournisseurs). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.boutique_retours_fournisseur (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_retour  DATE NOT NULL DEFAULT CURRENT_DATE,
  facture_id   UUID NOT NULL REFERENCES public.boutique_factures(id) ON DELETE CASCADE,
  montant      NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (montant >= 0),   -- remboursé par le fournisseur
  mode         TEXT NOT NULL DEFAULT 'Espèces',
  note         TEXT,
  charge_id    UUID,
  created_by   UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS boutique_retours_fournisseur_facture_idx ON public.boutique_retours_fournisseur (facture_id);

ALTER TABLE public.stock_mouvements ADD COLUMN IF NOT EXISTS retour_fournisseur_id UUID
  REFERENCES public.boutique_retours_fournisseur(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS stock_mouvements_retour_fournisseur_idx ON public.stock_mouvements (retour_fournisseur_id);

-- Nouveau type de mouvement « Retour fournisseur »
DO $$ DECLARE c RECORD; BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.stock_mouvements'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) ILIKE '%Ajustement%' LOOP
    EXECUTE format('ALTER TABLE public.stock_mouvements DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.stock_mouvements ADD CONSTRAINT stock_mouvements_type_check
  CHECK (type IN ('Achat','Vente','Ajustement','Retour','Retour fournisseur'));

-- Charges : un remboursement est une charge négative (on retire seulement une éventuelle règle « montant > 0 »)
DO $$ DECLARE c RECORD; BEGIN
  FOR c IN SELECT conname FROM pg_constraint
           WHERE conrelid = 'public.charges'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) ILIKE '%montant%' LOOP
    EXECUTE format('ALTER TABLE public.charges DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

-- ── Remboursement → charge négative de la salle ─────────────────────────────
CREATE OR REPLACE FUNCTION public.retour_fournisseur_charge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_f   RECORD;
  v_lib TEXT;
BEGIN
  IF NEW.montant > 0 THEN
    SELECT fournisseur, numero INTO v_f FROM public.boutique_factures WHERE id = NEW.facture_id;
    v_lib := 'Retour fournisseur boutique (remboursement)'
      || coalesce(' — ' || nullif(trim(v_f.fournisseur), ''), '')
      || coalesce(' — facture n° ' || nullif(trim(v_f.numero), ''), '');
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'public' AND table_name = 'charges' AND column_name = 'mode') THEN
      INSERT INTO public.charges (libelle, montant, categorie, date_charge, recurrence, mode)
      VALUES (v_lib, -NEW.montant, 'Achats boutique', NEW.date_retour, 'Ponctuelle', NEW.mode)
      RETURNING id INTO NEW.charge_id;
    ELSE
      INSERT INTO public.charges (libelle, montant, categorie, date_charge, recurrence)
      VALUES (v_lib, -NEW.montant, 'Achats boutique', NEW.date_retour, 'Ponctuelle')
      RETURNING id INTO NEW.charge_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_retour_fournisseur_charge ON public.boutique_retours_fournisseur;
CREATE TRIGGER trg_retour_fournisseur_charge BEFORE INSERT ON public.boutique_retours_fournisseur
  FOR EACH ROW EXECUTE FUNCTION public.retour_fournisseur_charge();

CREATE OR REPLACE FUNCTION public.retour_fournisseur_suppr_charge()
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
DROP TRIGGER IF EXISTS trg_retour_fournisseur_suppr_charge ON public.boutique_retours_fournisseur;
CREATE TRIGGER trg_retour_fournisseur_suppr_charge AFTER DELETE ON public.boutique_retours_fournisseur
  FOR EACH ROW EXECUTE FUNCTION public.retour_fournisseur_suppr_charge();

-- ── Enregistrer un retour fournisseur ─────────────────────────────────────
-- p_retour : {facture_id, date_retour, mode, note}
-- p_lignes : [{produit_id, quantite, prix_unitaire}]   (prix_unitaire = remboursement par article)
CREATE OR REPLACE FUNCTION public.enregistrer_retour_fournisseur(p_retour JSONB, p_lignes JSONB)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_fid    UUID := nullif(p_retour->>'facture_id', '')::uuid;
  v_date   DATE := coalesce(nullif(p_retour->>'date_retour', '')::date, CURRENT_DATE);
  v_f      RECORD;
  v_id     UUID;
  v_total  NUMERIC := 0;
  v_note   TEXT;
  l        JSONB;
  v_pid    UUID;
  v_qte    INT;
  v_pu     NUMERIC(10,2);
  v_nom    TEXT;
  v_achete INT;
  v_rendu  INT;
BEGIN
  SELECT * INTO v_f FROM public.boutique_factures WHERE id = v_fid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Facture fournisseur introuvable.'; END IF;
  IF jsonb_typeof(p_lignes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lignes) = 0 THEN
    RAISE EXCEPTION 'Indiquez au moins un article à retourner.';
  END IF;

  -- Contrôles et montant total
  FOR l IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    v_pid := nullif(l->>'produit_id', '')::uuid;
    v_qte := nullif(l->>'quantite', '')::int;
    v_pu  := coalesce(nullif(l->>'prix_unitaire', '')::numeric, 0);
    SELECT nom INTO v_nom FROM public.produits WHERE id = v_pid;
    IF v_nom IS NULL THEN RAISE EXCEPTION 'Article introuvable.'; END IF;
    IF v_qte IS NULL OR v_qte <= 0 THEN RAISE EXCEPTION 'Quantité invalide pour « % ».', v_nom; END IF;
    IF v_pu < 0 THEN RAISE EXCEPTION 'Prix invalide pour « % ».', v_nom; END IF;
    SELECT coalesce(sum(quantite), 0) INTO v_achete FROM public.stock_mouvements
      WHERE facture_id = v_fid AND produit_id = v_pid AND type = 'Achat';
    SELECT coalesce(-sum(m.quantite), 0) INTO v_rendu FROM public.stock_mouvements m
      JOIN public.boutique_retours_fournisseur r ON r.id = m.retour_fournisseur_id
      WHERE r.facture_id = v_fid AND m.produit_id = v_pid;
    IF v_qte > v_achete - v_rendu THEN
      RAISE EXCEPTION 'Impossible de retourner % « % » : % acheté(s) sur cette facture, % déjà retourné(s).', v_qte, v_nom, v_achete, v_rendu;
    END IF;
    v_total := v_total + v_qte * v_pu;
  END LOOP;

  INSERT INTO public.boutique_retours_fournisseur (date_retour, facture_id, montant, mode, note)
  VALUES (v_date, v_fid, round(v_total, 2), coalesce(nullif(trim(p_retour->>'mode'), ''), 'Espèces'), nullif(trim(p_retour->>'note'), ''))
  RETURNING id INTO v_id;

  v_note := 'Retour fournisseur' || coalesce(' — ' || nullif(trim(v_f.fournisseur), ''), '')
         || coalesce(' (facture n° ' || nullif(trim(v_f.numero), '') || ')', '');
  -- Sorties de stock (refusées par le stock si les articles ne sont plus là)
  FOR l IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    INSERT INTO public.stock_mouvements (date_mouvement, produit_id, type, quantite, prix_unitaire, note, retour_fournisseur_id)
    VALUES (v_date, (l->>'produit_id')::uuid, 'Retour fournisseur', -((l->>'quantite')::int),
            coalesce(nullif(l->>'prix_unitaire', '')::numeric, 0), v_note, v_id);
  END LOOP;
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enregistrer_retour_fournisseur(JSONB, JSONB) TO authenticated;

-- ── Sécurité (RLS) : voir = boutique ; saisir / supprimer = boutique ET charges (comme les factures) ──
ALTER TABLE public.boutique_retours_fournisseur ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "boutique_retours_fournisseur_select" ON public.boutique_retours_fournisseur;
DROP POLICY IF EXISTS "boutique_retours_fournisseur_insert" ON public.boutique_retours_fournisseur;
DROP POLICY IF EXISTS "boutique_retours_fournisseur_delete" ON public.boutique_retours_fournisseur;
CREATE POLICY "boutique_retours_fournisseur_select" ON public.boutique_retours_fournisseur FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "boutique_retours_fournisseur_insert" ON public.boutique_retours_fournisseur FOR INSERT
  WITH CHECK (public.has_perm('boutique','ecrire') AND public.has_perm('charges','ecrire'));
CREATE POLICY "boutique_retours_fournisseur_delete" ON public.boutique_retours_fournisseur FOR DELETE
  USING (public.has_perm('boutique','supprimer') AND public.has_perm('charges','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les retours fournisseur ──
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.boutique_retours_fournisseur';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.boutique_retours_fournisseur FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
