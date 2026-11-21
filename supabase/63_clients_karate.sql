-- ════════════════════════════════════════════════════════════════
-- 63 — Clients : mettre « Karaté » (nom exact de Sports & Tarifs) sur les fiches
--   Toute discipline de client qui contient « karat », « kyo » ou « kyu »
--   (Karaté Kyokushin, Kyokushin, KARATE, Karate sans accent…) et qui n'est
--   pas une discipline de Sports & Tarifs devient « Karaté ».
--   Même correction dans le Planning et les packs de la boutique.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_nouveau  TEXT;
  v_type     TEXT;
  v_anciens  TEXT[];
  v_tmp      TEXT[];
  v_ancien   TEXT;
  v_n        INT;
BEGIN
  -- Nom exact de la discipline dans Sports & Tarifs
  SELECT nom INTO v_nouveau FROM public.sports
  WHERE lower(trim(nom)) IN ('karaté', 'karate') ORDER BY nom LIMIT 1;
  IF v_nouveau IS NULL THEN
    RAISE EXCEPTION 'Aucune discipline « Karaté » dans Sports & Tarifs : rien n''a été modifié.';
  END IF;

  SELECT data_type INTO v_type FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'sports';

  -- Anciens noms : ressemblent au karaté mais ne sont pas une discipline de Sports & Tarifs
  SELECT array_agg(DISTINCT x) INTO v_anciens FROM (
    SELECT sport AS x FROM public.clients WHERE sport IS NOT NULL
    UNION SELECT sport FROM public.planning WHERE sport IS NOT NULL
  ) t
  WHERE (x ILIKE '%karat%' OR x ILIKE '%kyo%' OR x ILIKE '%kyu%')
    AND NOT EXISTS (SELECT 1 FROM public.sports s WHERE s.nom = x);

  IF v_type = 'ARRAY' THEN
    EXECUTE 'SELECT array_agg(DISTINCT x) FROM public.clients, unnest(sports) x
             WHERE (x ILIKE ''%karat%'' OR x ILIKE ''%kyo%'' OR x ILIKE ''%kyu%'')
               AND NOT EXISTS (SELECT 1 FROM public.sports s WHERE s.nom = x)' INTO v_tmp;
  ELSIF v_type IN ('jsonb', 'json') THEN
    EXECUTE 'SELECT array_agg(DISTINCT x) FROM public.clients, jsonb_array_elements_text(sports::jsonb) x
             WHERE jsonb_typeof(sports::jsonb) = ''array''
               AND (x ILIKE ''%karat%'' OR x ILIKE ''%kyo%'' OR x ILIKE ''%kyu%'')
               AND NOT EXISTS (SELECT 1 FROM public.sports s WHERE s.nom = x)' INTO v_tmp;
  END IF;
  SELECT array_agg(DISTINCT x) INTO v_anciens
  FROM unnest(coalesce(v_anciens, '{}') || coalesce(v_tmp, '{}')) x;

  IF v_anciens IS NULL THEN
    RAISE EXCEPTION 'Aucune fiche client avec un ancien nom de karaté : rien n''a été modifié.';
  END IF;
  RAISE NOTICE 'Remplacés par « % » : %', v_nouveau, array_to_string(v_anciens, ' | ');

  -- Fiches clients : discipline principale
  UPDATE public.clients SET sport = v_nouveau WHERE sport = ANY(v_anciens);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (discipline) : % fiche(s)', v_n;

  -- Fiches clients : liste des disciplines (sans doublon si « Karaté » y est déjà)
  IF v_type = 'ARRAY' THEN
    EXECUTE 'UPDATE public.clients
             SET sports = ARRAY(SELECT y FROM (
                   SELECT DISTINCT ON (y) y, i FROM (
                     SELECT CASE WHEN x = ANY($2) THEN $1 ELSE x END AS y, i
                     FROM unnest(sports) WITH ORDINALITY AS u(x, i)) a
                   ORDER BY y, i) b ORDER BY i)
             WHERE sports && $2'
      USING v_nouveau, v_anciens;
    GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (disciplines) : % fiche(s)', v_n;
  ELSIF v_type IN ('jsonb', 'json') THEN
    EXECUTE format('UPDATE public.clients
             SET sports = (SELECT jsonb_agg(to_jsonb(y) ORDER BY i) FROM (
                   SELECT DISTINCT ON (y) y, i FROM (
                     SELECT CASE WHEN x = ANY($2) THEN $1 ELSE x END AS y, i
                     FROM jsonb_array_elements_text(sports::jsonb) WITH ORDINALITY AS u(x, i)) a
                   ORDER BY y, i) b)::%s
             WHERE jsonb_typeof(sports::jsonb) = ''array''
               AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(sports::jsonb) x WHERE x = ANY($2))', v_type)
      USING v_nouveau, v_anciens;
    GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (disciplines) : % fiche(s)', v_n;
  END IF;

  -- Planning
  UPDATE public.planning SET sport = v_nouveau WHERE sport = ANY(v_anciens);
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Planning : % séance(s)', v_n;

  -- Packs de la boutique (script 61)
  IF to_regclass('public.boutique_packs') IS NOT NULL THEN
    EXECUTE 'UPDATE public.boutique_packs SET sport = $1 WHERE sport = ANY($2)' USING v_nouveau, v_anciens;
  END IF;

  -- Salaires déjà payés : nom du sport dans le détail
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'salaires_paie' AND column_name = 'detail' AND data_type = 'jsonb') THEN
    FOREACH v_ancien IN ARRAY v_anciens LOOP
      UPDATE public.salaires_paie
      SET detail = replace(detail::text, to_jsonb(v_ancien)::text, to_jsonb(v_nouveau)::text)::jsonb
      WHERE detail IS NOT NULL AND strpos(detail::text, to_jsonb(v_ancien)::text) > 0;
    END LOOP;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
