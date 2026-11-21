-- ════════════════════════════════════════════════════════════════
-- 62 — Renommer la discipline « Karaté Kyokushin » en « Karaté »
--   Partout sur le site : Sports & Tarifs, fiches clients (discipline et
--   liste des disciplines), Planning, packs de la boutique et détail des
--   salaires déjà payés (% par sport).
--   Toutes les orthographes sont reconnues : Karaté/Karate + Kyokushin,
--   Kyokuchin, Kyukunchin… (tout nom qui commence par « Karat » et contient « ky »).
--   Les droits d'accès aux portes et les coachs restent les mêmes.
--   Si une discipline « Karaté » existe déjà, le script s'arrête sans rien changer.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_nouveau  TEXT := 'Karaté';
  v_motif    TEXT := 'karat%ky%';
  v_anciens  TEXT[];
  v_ancien   TEXT;
  v_type     TEXT;
  v_n        INT;
BEGIN
  -- Une discipline « Karaté » existe déjà : fusion à faire autrement
  IF EXISTS (SELECT 1 FROM public.sports WHERE lower(trim(nom)) IN ('karaté', 'karate')) THEN
    RAISE EXCEPTION 'Une discipline « Karaté » existe déjà dans Sports & Tarifs : rien n''a été modifié.';
  END IF;

  -- Anciens noms trouvés (sports, clients, planning)
  SELECT array_agg(DISTINCT x) INTO v_anciens FROM (
    SELECT nom AS x FROM public.sports WHERE nom ILIKE v_motif
    UNION SELECT sport FROM public.clients WHERE sport ILIKE v_motif
    UNION SELECT sport FROM public.planning WHERE sport ILIKE v_motif
  ) t;
  IF v_anciens IS NULL THEN
    RAISE EXCEPTION 'Aucune discipline « Karaté Kyokushin » trouvée : rien n''a été modifié.';
  END IF;
  RAISE NOTICE 'Noms remplacés par « % » : %', v_nouveau, array_to_string(v_anciens, ' | ');

  -- Sports & Tarifs
  UPDATE public.sports SET nom = v_nouveau WHERE nom ILIKE v_motif;
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Sports & Tarifs : % ligne(s)', v_n;

  -- Fiches clients : discipline principale
  UPDATE public.clients SET sport = v_nouveau WHERE sport ILIKE v_motif;
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (discipline) : % fiche(s)', v_n;

  -- Fiches clients : liste des disciplines (tableau ou JSON selon la base)
  SELECT data_type INTO v_type FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'clients' AND column_name = 'sports';
  IF v_type = 'ARRAY' THEN
    EXECUTE 'UPDATE public.clients
             SET sports = ARRAY(SELECT CASE WHEN x ILIKE $2 THEN $1 ELSE x END FROM unnest(sports) WITH ORDINALITY AS u(x, i) ORDER BY i)
             WHERE EXISTS (SELECT 1 FROM unnest(sports) x WHERE x ILIKE $2)'
      USING v_nouveau, v_motif;
    GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (disciplines) : % fiche(s)', v_n;
  ELSIF v_type IN ('jsonb', 'json') THEN
    EXECUTE format('UPDATE public.clients
             SET sports = (SELECT jsonb_agg(CASE WHEN x ILIKE $2 THEN to_jsonb($1) ELSE to_jsonb(x) END ORDER BY i) FROM jsonb_array_elements_text(sports::jsonb) WITH ORDINALITY AS u(x, i))::%s
             WHERE jsonb_typeof(sports::jsonb) = ''array''
               AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(sports::jsonb) x WHERE x ILIKE $2)', v_type)
      USING v_nouveau, v_motif;
    GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Clients (disciplines) : % fiche(s)', v_n;
  END IF;

  -- Planning
  UPDATE public.planning SET sport = v_nouveau WHERE sport ILIKE v_motif;
  GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Planning : % séance(s)', v_n;

  -- Packs de la boutique (script 61)
  IF to_regclass('public.boutique_packs') IS NOT NULL THEN
    EXECUTE 'UPDATE public.boutique_packs SET sport = $1 WHERE sport ILIKE $2' USING v_nouveau, v_motif;
    GET DIAGNOSTICS v_n = ROW_COUNT; RAISE NOTICE 'Packs boutique : % pack(s)', v_n;
  END IF;

  -- Salaires déjà payés : nom du sport dans le détail (% par sport)
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
