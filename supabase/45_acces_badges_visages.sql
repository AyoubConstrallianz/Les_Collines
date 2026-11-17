-- ════════════════════════════════════════════════════════════════
-- 45 — Contrôle d'accès : badges et visages depuis le site (onglet Accès & Portes → Personnel)
--   • Badge : on passe un badge inconnu devant un appareil ; son numéro arrive avec le passage
--     refusé (acces_entrees.carte) et le site l'attribue à la personne → envoyé aux 2 portes.
--   • Visage : le site demande à un appareil d'ouvrir son écran d'enregistrement (ENROLL_BIO) ;
--     une fois le visage pris, le site récupère le modèle et le copie sur l'autre porte.
--   • Une erreur de synchronisation n'empêche plus l'appareil d'apparaître « En ligne ».
-- Prérequis : scripts 43 et 44. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.acces_entrees ADD COLUMN IF NOT EXISTS carte TEXT;

-- ── Données envoyées par l'appareil (ajout : N° de badge des passages refusés) ──
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

-- ── Interrogation régulière : commandes en attente ──
--   • une erreur de synchro est notée au journal sans annuler le « En ligne »
--   • les demandes d'enregistrement (ENROLL) passent en premier et ne sont jamais renvoyées
CREATE OR REPLACE FUNCTION public.acces_requete(p_sn TEXT, p_ip TEXT, p_info TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v   RECORD;
  r   RECORD;
  txt TEXT := '';
BEGIN
  SELECT * INTO v FROM public.acces_appareils WHERE sn = p_sn AND actif;
  IF NOT FOUND THEN RETURN NULL; END IF;
  UPDATE public.acces_appareils
  SET derniere_connexion = now(), ip = coalesce(p_ip, ip), infos = coalesce(nullif(p_info, ''), infos)
  WHERE sn = p_sn;
  IF v.synchro_demandee OR v.derniere_synchro IS NULL OR v.derniere_synchro < now() - interval '10 minutes' THEN
    BEGIN
      PERFORM public.acces_synchroniser(p_sn);
    EXCEPTION WHEN others THEN
      INSERT INTO public.acces_journal (sn, requete, reponse) VALUES (p_sn, 'synchro', 'ERREUR : ' || SQLERRM);
      UPDATE public.acces_appareils SET synchro_demandee = false, derniere_synchro = now() WHERE sn = p_sn;
    END;
  END IF;
  -- Une commande sans réponse après 5 essais est abandonnée ; un enregistrement après 10 minutes
  UPDATE public.acces_commandes SET termine_le = now(), retour = -999
  WHERE sn = p_sn AND termine_le IS NULL AND tentatives >= 5;
  UPDATE public.acces_commandes SET termine_le = now(), retour = -998
  WHERE sn = p_sn AND termine_le IS NULL AND commande LIKE 'ENROLL%' AND cree_le < now() - interval '10 minutes';
  FOR r IN
    SELECT id, commande FROM public.acces_commandes
    WHERE sn = p_sn AND termine_le IS NULL
      AND (envoyee_le IS NULL OR (envoyee_le < now() - interval '3 minutes' AND commande NOT LIKE 'ENROLL%'))
    ORDER BY (commande LIKE 'ENROLL%') DESC, id
    LIMIT 25
  LOOP
    txt := txt || 'C:' || r.id || ':' || r.commande || E'\n';
    UPDATE public.acces_commandes SET envoyee_le = now(), tentatives = tentatives + 1 WHERE id = r.id;
  END LOOP;
  RETURN txt;
END;
$$;

-- ── Résultats (ajout : visage enregistré → le site récupère le modèle) ──
CREATE OR REPLACE FUNCTION public.acces_resultats(p_sn TEXT, p_res JSONB)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  e   JSONB;
  c   RECORD;
  v_n INT := 0;
  v_q TEXT := 'DATA QUERY tablename=biodata,fielddesc=*,filter=*';
BEGIN
  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_res, '[]'::jsonb)) LOOP
    UPDATE public.acces_commandes
    SET retour = nullif(e->>'retour', '')::int, termine_le = now()
    WHERE id = nullif(e->>'id', '')::bigint AND sn = p_sn
    RETURNING commande, pin INTO c;
    CONTINUE WHEN NOT FOUND;
    v_n := v_n + 1;
    IF c.commande LIKE 'ENROLL%' AND coalesce(nullif(e->>'retour', '')::int, 0) = 0 THEN
      INSERT INTO public.acces_commandes (sn, commande)
      SELECT p_sn, v_q
      WHERE NOT EXISTS (SELECT 1 FROM public.acces_commandes x WHERE x.sn = p_sn AND x.commande = v_q AND x.termine_le IS NULL);
    END IF;
    IF coalesce(nullif(e->>'retour', '')::int, 0) < 0 AND c.pin IS NOT NULL THEN
      IF c.commande LIKE 'DATA UPDATE USERINFO%' OR c.commande LIKE 'DATA UPDATE user %' THEN
        DELETE FROM public.acces_utilisateurs WHERE sn = p_sn AND pin = c.pin;
      ELSIF c.commande LIKE 'DATA UPDATE userauthorize%' THEN
        UPDATE public.acces_utilisateurs SET autorise = false WHERE sn = p_sn AND pin = c.pin;
      ELSIF c.commande LIKE 'DATA DELETE USERINFO%' OR c.commande LIKE 'DATA DELETE user %' THEN
        INSERT INTO public.acces_utilisateurs (sn, pin) VALUES (p_sn, c.pin) ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── Attribuer (ou retirer, si p_carte est vide) un badge à une personne ──
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

-- ── Demander à un appareil d'ouvrir l'écran d'enregistrement du visage ──
CREATE OR REPLACE FUNCTION public.acces_enroler_visage(p_sn TEXT, p_pin TEXT)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id BIGINT;
BEGIN
  IF NOT public.has_perm('acces', 'ecrire') THEN RAISE EXCEPTION 'Droit « Accès & Portes » (écriture) nécessaire.'; END IF;
  IF coalesce(p_pin, '') !~ '^[0-9]{1,9}$' THEN RAISE EXCEPTION 'N° d''accès invalide.'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.acces_appareils WHERE sn = p_sn AND actif) THEN RAISE EXCEPTION 'Appareil inconnu.'; END IF;
  -- Une seule demande à la fois par appareil
  UPDATE public.acces_commandes SET termine_le = now(), retour = -997
  WHERE sn = p_sn AND termine_le IS NULL AND commande LIKE 'ENROLL%';
  INSERT INTO public.acces_commandes (sn, commande)
  VALUES (p_sn, 'ENROLL_BIO TYPE=9' || E'\tPIN=' || p_pin || E'\tRETRY=3\tOVERWRITE=1')
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.acces_attribuer_badge(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acces_attribuer_badge(TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.acces_enroler_visage(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acces_enroler_visage(TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_resultats(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_resultats(TEXT, JSONB) TO service_role;

NOTIFY pgrst, 'reload schema';
