-- ════════════════════════════════════════════════════════════════
-- 46 — Contrôle d'accès : correction « UPDATE requires a WHERE clause »
--   Supabase refuse une mise à jour sans condition (WHERE) venant de l'API : la réception de la
--   liste des personnes envoyée par un appareil échouait, et l'appareil la renvoyait en boucle.
-- Prérequis : script 45. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.acces_recevoir(p_sn TEXT, p_table TEXT, p_stamp TEXT, p_donnees JSONB)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_porte  SMALLINT;
  v_n      INT := 0;
  e        JSONB;
  v_pin    TEXT;
  v_change BOOLEAN := false;
  v_rows   INT;
BEGIN
  SELECT porte INTO v_porte FROM public.acces_appareils WHERE sn = p_sn AND actif;
  IF NOT FOUND THEN RETURN -1; END IF;
  UPDATE public.acces_appareils
  SET derniere_connexion = now(),
      stamp_attlog  = CASE WHEN upper(p_table) = 'ATTLOG'  THEN coalesce(nullif(p_stamp, ''), stamp_attlog)  ELSE stamp_attlog END,
      stamp_operlog = CASE WHEN upper(p_table) = 'OPERLOG' THEN coalesce(nullif(p_stamp, ''), stamp_operlog) ELSE stamp_operlog END
  WHERE sn = p_sn;

  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_donnees, '[]'::jsonb)) LOOP
    v_pin := nullif(trim(e->>'pin'), '');
    CONTINUE WHEN v_pin IS NULL;
    IF e->>'type' = 'ATTLOG' THEN
      BEGIN
        INSERT INTO public.acces_entrees (sn, porte, pin, date_heure, statut, verification, carte, client_id, employe_id)
        VALUES (p_sn, v_porte, v_pin, (e->>'date_heure')::timestamp,
                nullif(e->>'statut', '')::int, nullif(e->>'verification', '')::int,
                left(nullif(e->>'carte', ''), 40),
                (SELECT c.id FROM public.clients c WHERE c.numero_adherent::text = v_pin LIMIT 1),
                (SELECT m.id FROM public.employes m WHERE m.numero_acces::text = v_pin LIMIT 1))
        ON CONFLICT (sn, pin, date_heure) DO NOTHING;
        v_n := v_n + 1;
      EXCEPTION WHEN others THEN
        INSERT INTO public.acces_journal (sn, requete, corps, reponse) VALUES (p_sn, 'entrée illisible', e::text, SQLERRM);
      END;
    ELSIF e->>'type' = 'USER' THEN
      INSERT INTO public.acces_utilisateurs AS u (sn, pin, nom, pri)
      VALUES (p_sn, v_pin, nullif(e->>'nom', ''), coalesce(nullif(e->>'pri', '')::int, 0))
      ON CONFLICT (sn, pin) DO UPDATE SET nom = EXCLUDED.nom, pri = EXCLUDED.pri, maj = now()
        WHERE u.nom IS DISTINCT FROM EXCLUDED.nom OR u.pri IS DISTINCT FROM EXCLUDED.pri;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows > 0 THEN v_change := true; END IF;
      IF nullif(e->>'carte', '') IS NOT NULL THEN
        INSERT INTO public.acces_visages AS vv (pin, cle, ligne, sn_source) VALUES (v_pin, 'CARTE', e->>'carte', p_sn)
        ON CONFLICT (pin, cle) DO UPDATE SET ligne = EXCLUDED.ligne, sn_source = EXCLUDED.sn_source, maj = now()
          WHERE vv.ligne IS DISTINCT FROM EXCLUDED.ligne;
      END IF;
      v_n := v_n + 1;
    ELSIF e->>'type' = 'BIO' AND nullif(e->>'ligne', '') IS NOT NULL THEN
      -- Un modèle identique déjà connu (renvoi d'un modèle envoyé par le site) ne déclenche rien
      INSERT INTO public.acces_visages AS vv (pin, cle, ligne, sn_source) VALUES (v_pin, e->>'cle', e->>'ligne', p_sn)
      ON CONFLICT (pin, cle) DO UPDATE SET ligne = EXCLUDED.ligne, sn_source = EXCLUDED.sn_source, maj = now()
        WHERE vv.ligne IS DISTINCT FROM EXCLUDED.ligne;
      GET DIAGNOSTICS v_rows = ROW_COUNT;
      IF v_rows > 0 THEN v_change := true; END IF;
      INSERT INTO public.acces_utilisateurs (sn, pin, visage_maj) VALUES (p_sn, v_pin, now())
      ON CONFLICT (sn, pin) DO UPDATE SET visage_maj = now();
      v_n := v_n + 1;
    END IF;
  END LOOP;

  IF v_change THEN UPDATE public.acces_appareils SET synchro_demandee = true WHERE NOT synchro_demandee; END IF;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.acces_attribuer_badge(p_pin TEXT, p_carte TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_carte TEXT := nullif(trim(coalesce(p_carte, '')), '');
  v_autre TEXT;
BEGIN
  IF NOT public.has_perm('acces', 'ecrire') THEN RAISE EXCEPTION 'Droit « Accès & Portes » (écriture) nécessaire.'; END IF;
  IF coalesce(p_pin, '') !~ '^[0-9]{1,9}$' THEN RAISE EXCEPTION 'N° d''accès invalide.'; END IF;
  IF v_carte IS NOT NULL AND v_carte !~ '^[0-9A-Fa-f]{1,20}$' THEN RAISE EXCEPTION 'N° de badge invalide.'; END IF;
  IF v_carte IS NOT NULL THEN
    SELECT pin INTO v_autre FROM public.acces_visages WHERE cle = 'CARTE' AND ligne = v_carte AND pin <> p_pin LIMIT 1;
    IF FOUND THEN RAISE EXCEPTION 'Ce badge est déjà attribué au N° %.', v_autre; END IF;
    INSERT INTO public.acces_visages AS vv (pin, cle, ligne, sn_source) VALUES (p_pin, 'CARTE', v_carte, 'site')
    ON CONFLICT (pin, cle) DO UPDATE SET ligne = EXCLUDED.ligne, sn_source = 'site', maj = now();
  ELSE
    DELETE FROM public.acces_visages WHERE pin = p_pin AND cle = 'CARTE';
  END IF;
  -- La fiche de la personne sera renvoyée aux appareils (avec le nouveau badge), sans toucher aux visages
  UPDATE public.acces_utilisateurs SET nom = NULL WHERE pin = p_pin AND pri = 0;
  UPDATE public.acces_appareils SET synchro_demandee = true WHERE NOT synchro_demandee;
END;
$$;

REVOKE ALL ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) TO service_role;
REVOKE ALL ON FUNCTION public.acces_attribuer_badge(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acces_attribuer_badge(TEXT, TEXT) TO authenticated;

NOTIFY pgrst, 'reload schema';
