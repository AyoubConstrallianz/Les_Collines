-- ════════════════════════════════════════════════════════════════
-- 34 — Boutique : factures fournisseurs
--   • boutique_factures : date, fournisseur, n° de facture, MONTANT TOTAL de la facture, note
--   • Le montant total devient automatiquement une CHARGE de la salle (catégorie « Achats boutique ») :
--     modifier / supprimer la facture modifie / supprime la charge
--   • Les articles achetés (quantité, prix d'achat, prix de vente) entrent en stock : mouvements « Achat »
--     liés à la facture (supprimés avec elle ; suppression refusée si les articles ont déjà été vendus)
--   • enregistrer_facture_boutique(facture, articles) : la facture et ses articles en une seule fois (tout ou rien)
--   • Les entrées de stock se font UNIQUEMENT par une facture (les sorties restent libres : ventes, inventaire à la baisse)
-- Prérequis : script 27 (boutique). À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.boutique_factures (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_facture  DATE NOT NULL DEFAULT CURRENT_DATE,
  fournisseur   TEXT,
  numero        TEXT,
  montant       NUMERIC(10,2) NOT NULL CHECK (montant > 0),
  note          TEXT,
  charge_id     UUID,                                   -- charge de la salle correspondante
  created_by    UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS boutique_factures_date_idx ON public.boutique_factures (date_facture DESC);

ALTER TABLE public.stock_mouvements ADD COLUMN IF NOT EXISTS facture_id UUID REFERENCES public.boutique_factures(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS stock_mouvements_facture_idx ON public.stock_mouvements (facture_id);
ALTER TABLE public.stock_mouvements ADD COLUMN IF NOT EXISTS prix_vente NUMERIC(10,2);   -- prix de vente saisi sur la facture

-- ── Charge de la salle créée / mise à jour avec la facture ─────────────────
CREATE OR REPLACE FUNCTION public.boutique_facture_charge()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lib TEXT := 'Facture fournisseur boutique'
    || coalesce(' — ' || nullif(trim(NEW.fournisseur), ''), '')
    || coalesce(' n° ' || nullif(trim(NEW.numero), ''), '');
BEGIN
  IF NEW.charge_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.charges WHERE id = NEW.charge_id) THEN
    UPDATE public.charges SET libelle = v_lib, montant = NEW.montant, date_charge = NEW.date_facture
    WHERE id = NEW.charge_id;
  ELSE
    -- nouvelle facture (ou charge supprimée entre-temps) : la charge est (re)créée
    INSERT INTO public.charges (libelle, montant, categorie, date_charge, recurrence)
    VALUES (v_lib, NEW.montant, 'Achats boutique', NEW.date_facture, 'Ponctuelle')
    RETURNING id INTO NEW.charge_id;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_facture_charge ON public.boutique_factures;
CREATE TRIGGER trg_facture_charge BEFORE INSERT OR UPDATE ON public.boutique_factures
  FOR EACH ROW EXECUTE FUNCTION public.boutique_facture_charge();

-- Facture supprimée → charge supprimée
CREATE OR REPLACE FUNCTION public.boutique_facture_suppr_charge()
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
DROP TRIGGER IF EXISTS trg_facture_suppr_charge ON public.boutique_factures;
CREATE TRIGGER trg_facture_suppr_charge AFTER DELETE ON public.boutique_factures
  FOR EACH ROW EXECUTE FUNCTION public.boutique_facture_suppr_charge();

-- ── Enregistrer une facture et ses articles (nouvelle facture ou modification) ──
-- p_facture : {id?, date_facture, fournisseur, numero, montant, note}
-- p_lignes  : [{produit_id?, article, categorie?, quantite, prix_achat, prix_vente}]
-- Article inconnu → créé dans le stock ; article connu → prix d'achat et de vente mis à jour.
-- Exécutée avec les droits de l'utilisateur (sécurité RLS appliquée).
CREATE OR REPLACE FUNCTION public.enregistrer_facture_boutique(p_facture JSONB, p_lignes JSONB)
RETURNS UUID
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id     UUID := nullif(p_facture->>'id', '')::uuid;
  v_date   DATE := coalesce(nullif(p_facture->>'date_facture', '')::date, CURRENT_DATE);
  v_note   TEXT;
  v_nouv   UUID[] := '{}';
  v_mvt    UUID;
  l        JSONB;
  v_nom    TEXT;
  v_pid    UUID;
  v_qte    INT;
  v_pa     NUMERIC(10,2);
  v_pv     NUMERIC(10,2);
BEGIN
  IF jsonb_typeof(p_lignes) IS DISTINCT FROM 'array' OR jsonb_array_length(p_lignes) = 0 THEN
    RAISE EXCEPTION 'Ajoutez au moins un article à la facture.';
  END IF;

  IF v_id IS NULL THEN
    INSERT INTO public.boutique_factures (date_facture, fournisseur, numero, montant, note)
    VALUES (v_date, nullif(trim(p_facture->>'fournisseur'), ''), nullif(trim(p_facture->>'numero'), ''),
            (p_facture->>'montant')::numeric, nullif(trim(p_facture->>'note'), ''))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.boutique_factures
    SET date_facture = v_date, fournisseur = nullif(trim(p_facture->>'fournisseur'), ''),
        numero = nullif(trim(p_facture->>'numero'), ''), montant = (p_facture->>'montant')::numeric,
        note = nullif(trim(p_facture->>'note'), '')
    WHERE id = v_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Facture introuvable.'; END IF;
  END IF;

  v_note := 'Facture' || coalesce(' n° ' || nullif(trim(p_facture->>'numero'), ''), '')
         || coalesce(' — ' || nullif(trim(p_facture->>'fournisseur'), ''), '');

  FOR l IN SELECT * FROM jsonb_array_elements(p_lignes) LOOP
    v_nom := regexp_replace(trim(coalesce(l->>'article', '')), '\s+', ' ', 'g');
    v_qte := nullif(l->>'quantite', '')::int;
    v_pa  := coalesce(nullif(l->>'prix_achat', '')::numeric, 0);
    v_pv  := coalesce(nullif(l->>'prix_vente', '')::numeric, 0);
    IF v_nom = '' THEN RAISE EXCEPTION 'Un article de la facture n''a pas de nom.'; END IF;
    IF v_qte IS NULL OR v_qte <= 0 THEN RAISE EXCEPTION 'Quantité invalide pour « % ».', v_nom; END IF;
    IF v_pa < 0 OR v_pv < 0 THEN RAISE EXCEPTION 'Prix invalide pour « % ».', v_nom; END IF;

    v_pid := nullif(l->>'produit_id', '')::uuid;
    IF v_pid IS NULL THEN
      SELECT id INTO v_pid FROM public.produits WHERE lower(trim(nom)) = lower(v_nom) LIMIT 1;
    END IF;
    IF v_pid IS NULL THEN
      INSERT INTO public.produits (nom, categorie, prix_achat, prix_vente)
      VALUES (v_nom, nullif(trim(l->>'categorie'), ''), v_pa, v_pv)
      RETURNING id INTO v_pid;
    ELSE
      UPDATE public.produits
      SET prix_achat = v_pa, prix_vente = CASE WHEN v_pv > 0 THEN v_pv ELSE prix_vente END, actif = true,
          categorie = coalesce(categorie, nullif(trim(l->>'categorie'), ''))
      WHERE id = v_pid;
    END IF;

    INSERT INTO public.stock_mouvements (date_mouvement, produit_id, type, quantite, prix_unitaire, prix_vente, note, facture_id)
    VALUES (v_date, v_pid, 'Achat', v_qte, v_pa, v_pv, v_note, v_id)
    RETURNING id INTO v_mvt;
    v_nouv := v_nouv || v_mvt;
  END LOOP;

  -- Modification : les anciens articles sont retirés APRÈS l'ajout des nouveaux (le stock ne passe jamais sous zéro à tort)
  DELETE FROM public.stock_mouvements WHERE facture_id = v_id AND NOT (id = ANY (v_nouv));
  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.enregistrer_facture_boutique(JSONB, JSONB) TO authenticated;

-- ── Entrées de stock : UNIQUEMENT par une facture fournisseur ─────────────
-- Toute entrée (quantité positive) doit être liée à une facture. Les sorties restent libres :
-- ventes, inventaire à la baisse (casse, perte). Les mouvements déjà enregistrés ne sont pas touchés.
CREATE OR REPLACE FUNCTION public.entree_stock_par_facture()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.quantite > 0 AND NEW.facture_id IS NULL THEN
    RAISE EXCEPTION 'Les entrées de stock se font uniquement par une facture fournisseur (Boutique → Factures fournisseurs).';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_entree_par_facture ON public.stock_mouvements;
CREATE TRIGGER trg_entree_par_facture BEFORE INSERT ON public.stock_mouvements
  FOR EACH ROW EXECUTE FUNCTION public.entree_stock_par_facture();

-- ── Sécurité (RLS) : voir = boutique ; saisir / supprimer = boutique ET charges ──
ALTER TABLE public.boutique_factures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "boutique_factures_select" ON public.boutique_factures;
DROP POLICY IF EXISTS "boutique_factures_insert" ON public.boutique_factures;
DROP POLICY IF EXISTS "boutique_factures_update" ON public.boutique_factures;
DROP POLICY IF EXISTS "boutique_factures_delete" ON public.boutique_factures;
CREATE POLICY "boutique_factures_select" ON public.boutique_factures FOR SELECT USING (public.has_perm('boutique','lire'));
CREATE POLICY "boutique_factures_insert" ON public.boutique_factures FOR INSERT
  WITH CHECK (public.has_perm('boutique','ecrire') AND public.has_perm('charges','ecrire'));
CREATE POLICY "boutique_factures_update" ON public.boutique_factures FOR UPDATE
  USING (public.has_perm('boutique','ecrire') AND public.has_perm('charges','ecrire'));
CREATE POLICY "boutique_factures_delete" ON public.boutique_factures FOR DELETE
  USING (public.has_perm('boutique','supprimer') AND public.has_perm('charges','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les factures ─────────
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.boutique_factures';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.boutique_factures FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
