-- ════════════════════════════════════════════════════════════════
-- 25 — Validation par le super admin des changements faits par un GÉRANT
--   • Chaque ajout / modification / suppression d'un gérant est appliqué tout de suite
--     (le gérant voit son travail normalement) ET enregistré dans « modifications »
--   • Le super admin voit une notification, puis VALIDE ou REFUSE
--   • Refuser = annulation automatique (ajout supprimé, valeurs d'avant remises, élément supprimé recréé)
--   • Les mises à jour automatiques du statut Actif / Inactif des clients ne sont pas suivies
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.modifications (
  id          BIGSERIAL PRIMARY KEY,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  txid        BIGINT NOT NULL DEFAULT txid_current(),   -- regroupe les changements d'une même action
  user_id     UUID DEFAULT auth.uid(),
  user_nom    TEXT,
  table_nom   TEXT NOT NULL,
  operation   TEXT NOT NULL,                             -- INSERT / UPDATE / DELETE
  ligne_id    TEXT,
  avant       JSONB,
  apres       JSONB,
  statut      TEXT NOT NULL DEFAULT 'En attente',        -- En attente / Validée / Refusée
  traite_par  UUID,
  traite_le   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS modifications_statut_idx ON public.modifications (statut, created_at DESC);
CREATE INDEX IF NOT EXISTS modifications_ligne_idx  ON public.modifications (table_nom, ligne_id);

-- Lecture réservée au super admin ; écriture uniquement par les fonctions ci-dessous
ALTER TABLE public.modifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "modifications_select" ON public.modifications;
CREATE POLICY "modifications_select" ON public.modifications FOR SELECT USING (public.get_my_role() = 'super_admin');

-- ── Suivi : enregistre les changements faits par un gérant ─────────────────
CREATE OR REPLACE FUNCTION public.suivre_modif_gerant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avant JSONB := CASE WHEN TG_OP IN ('UPDATE','DELETE') THEN to_jsonb(OLD) END;
  v_apres JSONB := CASE WHEN TG_OP IN ('INSERT','UPDATE') THEN to_jsonb(NEW) END;
  v_ligne JSONB := COALESCE(v_apres, v_avant);
  v_nom   TEXT;
BEGIN
  IF public.get_my_role() IS DISTINCT FROM 'gerant' THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' THEN
    -- Rien de changé (hors date de mise à jour)
    IF (v_avant - 'updated_at') = (v_apres - 'updated_at') THEN RETURN NULL; END IF;
    -- Statut Actif / Inactif recalculé automatiquement par l'application
    IF TG_TABLE_NAME = 'clients'
       AND (v_avant - 'updated_at' - 'statut') = (v_apres - 'updated_at' - 'statut')
       AND (v_avant->>'statut') IN ('Actif','Inactif') AND (v_apres->>'statut') IN ('Actif','Inactif') THEN
      RETURN NULL;
    END IF;
  END IF;
  SELECT trim(coalesce(prenom,'') || ' ' || coalesce(nom,'')) INTO v_nom FROM public.profils WHERE id = auth.uid();
  INSERT INTO public.modifications (user_id, user_nom, table_nom, operation, ligne_id, avant, apres)
  VALUES (auth.uid(), v_nom, TG_TABLE_NAME, TG_OP, COALESCE(v_ligne->>'id', v_ligne->>'cle'), v_avant, v_apres);
  RETURN NULL;
END;
$$;

DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['clients','paiements','charges','sports','planning','employes','salaires_paie',
                           'ventes','parametres','habilitations','associes'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.%I', t);
      EXECUTE format('CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()', t);
    END IF;
  END LOOP;
END $$;

-- ── Annulation d'UN changement (appelée par traiter_modifications) ──────────
CREATE OR REPLACE FUNCTION public.annuler_une_modification(p_id BIGINT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  m        RECORD;
  v_cle    TEXT;
  v_actuel JSONB;
  v_set    TEXT;
  v_libre  TEXT;
  v_ign    TEXT[];   -- champs ignorés dans la comparaison (mis à jour automatiquement)
BEGIN
  IF public.get_my_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Action réservée au super admin';
  END IF;
  SELECT * INTO m FROM public.modifications WHERE id = p_id AND statut = 'En attente';
  IF NOT FOUND THEN RETURN; END IF;
  v_cle := CASE WHEN m.table_nom = 'parametres' THEN 'cle' ELSE 'id' END;
  v_ign := CASE WHEN m.table_nom = 'clients' THEN ARRAY['updated_at','statut'] ELSE ARRAY['updated_at'] END;
  v_libre := CASE m.table_nom WHEN 'clients' THEN 'ce client' WHEN 'paiements' THEN 'ce paiement' ELSE 'cet élément' END;
  EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I::text = $1', m.table_nom, v_cle)
    INTO v_actuel USING m.ligne_id;

  IF m.operation = 'INSERT' THEN
    IF v_actuel IS NOT NULL THEN
      IF (v_actuel - v_ign) <> (m.apres - v_ign) THEN
        RAISE EXCEPTION 'Refus impossible : % a été modifié depuis. Traitez d''abord les changements plus récents.', v_libre;
      END IF;
      EXECUTE format('DELETE FROM public.%I WHERE %I::text = $1', m.table_nom, v_cle) USING m.ligne_id;
    END IF;

  ELSIF m.operation = 'UPDATE' THEN
    IF v_actuel IS NULL THEN
      RAISE EXCEPTION 'Refus impossible : % a été supprimé depuis.', v_libre;
    END IF;
    IF (v_actuel - v_ign) <> (m.apres - v_ign) THEN
      RAISE EXCEPTION 'Refus impossible : % a été modifié depuis. Traitez d''abord les changements plus récents.', v_libre;
    END IF;
    SELECT string_agg(format('%I = r.%I', k, k), ', ') INTO v_set
    FROM jsonb_object_keys(m.avant) k
    WHERE k <> v_cle
      AND EXISTS (SELECT 1 FROM information_schema.columns c
                  WHERE c.table_schema = 'public' AND c.table_name = m.table_nom AND c.column_name = k
                    AND c.is_generated = 'NEVER');
    IF v_set IS NOT NULL THEN
      EXECUTE format('UPDATE public.%I t SET %s FROM jsonb_populate_record(NULL::public.%I, $1) r WHERE t.%I::text = $2',
                     m.table_nom, v_set, m.table_nom, v_cle) USING m.avant, m.ligne_id;
    END IF;

  ELSE  -- DELETE : on recrée l'élément tel qu'il était
    IF v_actuel IS NOT NULL THEN
      RAISE EXCEPTION 'Refus impossible : % existe de nouveau.', v_libre;
    END IF;
    EXECUTE format('INSERT INTO public.%I SELECT * FROM jsonb_populate_record(NULL::public.%I, $1)',
                   m.table_nom, m.table_nom) USING m.avant;
  END IF;
END;
$$;

-- ── Décision du super admin : valider, ou refuser (= annuler les changements) ──
-- Refus : chaque changement est annulé ; un changement qui dépend d'un autre (ex. paiement d'un client
-- supprimé à recréer d'abord) est retenté au tour suivant. Si l'annulation complète est impossible
-- (élément modifié depuis par quelqu'un d'autre…), RIEN n'est changé et le motif est affiché.
CREATE OR REPLACE FUNCTION public.traiter_modifications(p_ids BIGINT[], p_decision TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restant BIGINT[];
  v_suivant BIGINT[];
  v_id      BIGINT;
  v_err     TEXT;
BEGIN
  IF public.get_my_role() IS DISTINCT FROM 'super_admin' THEN
    RAISE EXCEPTION 'Action réservée au super admin';
  END IF;
  IF p_decision NOT IN ('Validée','Refusée') THEN
    RAISE EXCEPTION 'Décision inconnue : %', p_decision;
  END IF;

  IF p_decision = 'Refusée' THEN
    SELECT array_agg(id ORDER BY id DESC) INTO v_restant
    FROM public.modifications WHERE id = ANY(p_ids) AND statut = 'En attente';
    WHILE coalesce(cardinality(v_restant), 0) > 0 LOOP
      v_suivant := ARRAY[]::BIGINT[];
      FOREACH v_id IN ARRAY v_restant LOOP
        BEGIN
          PERFORM public.annuler_une_modification(v_id);
        EXCEPTION WHEN OTHERS THEN
          v_suivant := v_suivant || v_id;
          v_err := SQLERRM;
        END;
      END LOOP;
      IF cardinality(v_suivant) = cardinality(v_restant) THEN
        RAISE EXCEPTION '%', v_err;     -- plus aucun progrès : tout est annulé (transaction)
      END IF;
      v_restant := v_suivant;
    END LOOP;
  END IF;

  UPDATE public.modifications
  SET statut = p_decision, traite_par = auth.uid(), traite_le = now()
  WHERE id = ANY(p_ids) AND statut = 'En attente';
END;
$$;

REVOKE ALL ON FUNCTION public.traiter_modifications(BIGINT[], TEXT) FROM anon;
REVOKE ALL ON FUNCTION public.annuler_une_modification(BIGINT) FROM anon;
GRANT EXECUTE ON FUNCTION public.traiter_modifications(BIGINT[], TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
