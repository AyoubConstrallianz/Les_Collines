-- ════════════════════════════════════════════════════════════════
-- 06 — Fusion de clients en double
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
--
-- fusionner_clients(garder, doublons[]) :
--   • rattache au client conservé tout ce qui pointe vers les doublons
--     (paiements, et toute table qui référencera clients plus tard)
--   • supprime les doublons
-- La fiche conservée (sports réunis, champs complétés) est mise à jour par
-- l'application juste avant l'appel.
-- Réservé aux utilisateurs ayant le droit « supprimer » sur les clients.
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fusionner_clients(p_garder UUID, p_doublons UUID[])
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fk RECORD;
  v_nb INT;
BEGIN
  IF NOT public.has_perm('clients', 'supprimer') THEN
    RAISE EXCEPTION 'Droit insuffisant : suppression de clients requise pour fusionner';
  END IF;
  p_doublons := ARRAY(SELECT DISTINCT d FROM unnest(p_doublons) d WHERE d IS NOT NULL AND d <> p_garder);
  IF p_garder IS NULL OR cardinality(p_doublons) = 0 THEN
    RAISE EXCEPTION 'Rien à fusionner';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.clients WHERE id = p_garder) THEN
    RAISE EXCEPTION 'Client à conserver introuvable';
  END IF;

  -- Rattacher toutes les colonnes qui référencent clients(id)
  FOR v_fk IN
    SELECT c.conrelid::regclass AS tbl, a.attname AS col
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.confrelid = 'public.clients'::regclass AND cardinality(c.conkey) = 1
  LOOP
    EXECUTE format('UPDATE %s SET %I = $1 WHERE %I = ANY($2)', v_fk.tbl, v_fk.col, v_fk.col)
      USING p_garder, p_doublons;
  END LOOP;

  DELETE FROM public.clients WHERE id = ANY(p_doublons);
  GET DIAGNOSTICS v_nb = ROW_COUNT;
  RETURN v_nb;
END;
$$;

REVOKE ALL ON FUNCTION public.fusionner_clients(UUID, UUID[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fusionner_clients(UUID, UUID[]) TO authenticated;
