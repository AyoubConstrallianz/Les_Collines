-- ════════════════════════════════════════════════════════════════
-- 50 — Contrôle d'accès : accès selon les horaires des séances (onglet Planning)
--   Un client entre par la porte de sa discipline à partir de N minutes avant le début d'une
--   séance de sa discipline (ce jour-là, dans le Planning), et jusqu'à M minutes avant la fin.
--   N et M se règlent dans Accès & Portes (15 et 30 par défaut).
--   Une discipline sans aucune séance dans le Planning (ex. Musculation) : accès toute la journée.
--   Le personnel : toujours. Le site ouvre / retire le droit d'ouvrir sur l'appareil chaque minute
--   (la fiche et le visage restent sur l'appareil). L'appareil doit être en mode « contrôle de porte ».
-- Prérequis : scripts 43 à 49. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.acces_appareils ADD COLUMN IF NOT EXISTS derniere_bascule TIMESTAMPTZ;
INSERT INTO public.parametres (cle, valeur) VALUES ('acces_avant_min', '15'), ('acces_fin_min', '30')
  ON CONFLICT (cle) DO NOTHING;

-- ── Personnes qui peuvent ouvrir la porte EN CE MOMENT (sous-ensemble de acces_autorises) ──
CREATE OR REPLACE FUNCTION public.acces_ouverts(p_porte INT)
RETURNS TABLE (pin TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_maint  TIMESTAMP := now() AT TIME ZONE 'Africa/Casablanca';
  v_heure  TIME;
  v_jour   TEXT;
  v_avant  INTERVAL;
  v_fin    INTERVAL;
BEGIN
  v_heure := v_maint::time;
  v_jour  := (ARRAY['Lundi','Mardi','Mercredi','Jeudi','Vendredi','Samedi','Dimanche'])[extract(isodow FROM v_maint)::int];
  v_avant := make_interval(mins => coalesce((SELECT nullif(valeur, '')::int FROM public.parametres WHERE cle = 'acces_avant_min'), 15));
  v_fin   := make_interval(mins => coalesce((SELECT nullif(valeur, '')::int FROM public.parametres WHERE cle = 'acces_fin_min'), 30));
  RETURN QUERY
  SELECT a.pin FROM public.acces_autorises(p_porte) a
  WHERE
    -- Personnel (pas un N° d'adhérent) : toujours
    NOT EXISTS (SELECT 1 FROM public.clients c WHERE c.numero_adherent::text = a.pin)
    -- Client : une de ses disciplines de cette porte est sans séance au planning, ou en séance maintenant
    OR EXISTS (
      SELECT 1
      FROM public.clients c
      JOIN public.sports s ON (s.porte = p_porte OR s.porte = 0) AND (to_jsonb(c.sports) ? s.nom OR s.nom = c.sport)
      WHERE c.numero_adherent::text = a.pin
        AND (
          NOT EXISTS (SELECT 1 FROM public.planning pl WHERE lower(trim(pl.sport)) = lower(trim(s.nom)))
          OR EXISTS (
            SELECT 1 FROM public.planning pl
            WHERE lower(trim(pl.sport)) = lower(trim(s.nom))
              AND pl.jour = v_jour
              AND v_heure >= pl.heure_debut::time - v_avant
              AND v_heure <  pl.heure_fin::time - v_fin)));
END;
$$;

-- ── Ouvre / retire le droit d'ouvrir selon l'heure (personnes déjà sur l'appareil) ──
CREATE OR REPLACE FUNCTION public.acces_basculer(p_sn TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_porte SMALLINT;
  v_acc   BOOLEAN;
  v_auto  TEXT[];
  v_ouv   TEXT[];
  v_n     INT := 0;
  r       RECORD;
BEGIN
  SELECT porte, coalesce(protocole, 'att') = 'acc' INTO v_porte, v_acc FROM public.acces_appareils WHERE sn = p_sn AND actif;
  IF v_porte IS NULL OR NOT v_acc THEN RETURN 0; END IF;
  v_auto := ARRAY(SELECT a.pin FROM public.acces_autorises(v_porte) a);
  v_ouv  := ARRAY(SELECT o.pin FROM public.acces_ouverts(v_porte) o);
  FOR r IN
    SELECT u.pin, u.autorise, (u.pin = ANY (v_ouv)) AS ouvert
    FROM public.acces_utilisateurs u
    WHERE u.sn = p_sn AND u.pin = ANY (v_auto)
      AND u.autorise IS DISTINCT FROM (u.pin = ANY (v_ouv))
  LOOP
    INSERT INTO public.acces_commandes (sn, pin, commande)
    VALUES (p_sn, r.pin, CASE WHEN r.ouvert
                              THEN 'DATA UPDATE userauthorize Pin=' || r.pin || E'\tAuthorizeTimezoneId=1\tAuthorizeDoorId=1'
                              ELSE 'DATA DELETE userauthorize Pin=' || r.pin END);
    UPDATE public.acces_utilisateurs SET autorise = r.ouvert WHERE sn = p_sn AND pin = r.pin;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.acces_synchroniser(p_sn TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_porte SMALLINT;
  v_acc   BOOLEAN;
  v_n     INT := 0;
  v_pins  TEXT[];
  v_cmd   TEXT;
  r       RECORD;
  v       RECORD;
  v_ouv   TEXT[];
  v_ouvert BOOLEAN;
BEGIN
  SELECT porte, coalesce(protocole, 'att') = 'acc' INTO v_porte, v_acc FROM public.acces_appareils WHERE sn = p_sn AND actif;
  UPDATE public.acces_appareils SET synchro_demandee = false, derniere_synchro = now() WHERE sn = p_sn;
  DELETE FROM public.acces_journal WHERE le < now() - interval '7 days';
  DELETE FROM public.acces_commandes WHERE termine_le < now() - interval '30 days';
  IF v_porte IS NULL THEN RETURN 0; END IF;
  v_ouv := ARRAY(SELECT o.pin FROM public.acces_ouverts(v_porte) o);

  -- Ajouts et mises à jour
  FOR r IN
    SELECT a.pin, a.nom, u.pin AS u_pin, u.nom AS u_nom, coalesce(u.pri, 0) AS u_pri, u.visage_maj,
           coalesce(u.autorise, false) AS u_autorise,
           (SELECT vc.ligne FROM public.acces_visages vc WHERE vc.pin = a.pin AND vc.cle = 'CARTE') AS carte
    FROM public.acces_autorises(v_porte) a
    LEFT JOIN public.acces_utilisateurs u ON u.sn = p_sn AND u.pin = a.pin
  LOOP
    IF r.u_pri > 0 THEN CONTINUE; END IF;   -- administrateur : fiche jamais modifiée (droit d'ouvrir : acces_basculer)
    v_cmd := NULL;
    v_ouvert := r.pin = ANY (v_ouv);
    IF r.u_pin IS NULL OR r.u_nom IS DISTINCT FROM r.nom THEN
      DELETE FROM public.acces_commandes WHERE sn = p_sn AND pin = r.pin AND envoyee_le IS NULL;
      IF v_acc THEN
        v_cmd := 'DATA UPDATE user CardNo=' || coalesce(r.carte, '') || E'\tPin=' || r.pin
                 || E'\tPassword=\tGroup=1\tStartTime=0\tEndTime=0\tName=' || r.nom || E'\tPrivilege=0';
        INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
        -- Droit d'ouvrir : seulement pendant le créneau autorisé (sinon retiré)
        v_cmd := CASE WHEN v_ouvert
                      THEN 'DATA UPDATE userauthorize Pin=' || r.pin || E'\tAuthorizeTimezoneId=1\tAuthorizeDoorId=1'
                      ELSE 'DATA DELETE userauthorize Pin=' || r.pin END;
        INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
      ELSE
        v_cmd := 'DATA UPDATE USERINFO PIN=' || r.pin || E'\tName=' || r.nom || E'\tPri=0'
                 || CASE WHEN r.carte IS NOT NULL THEN E'\tCard=' || r.carte ELSE '' END;
        INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
      END IF;
    END IF;
    FOR v IN
      SELECT vv.ligne FROM public.acces_visages vv
      WHERE vv.pin = r.pin AND vv.cle <> 'CARTE'
        AND (r.u_pin IS NULL OR vv.maj > coalesce(r.visage_maj, '-infinity'::timestamptz))
    LOOP
      v_cmd := 'DATA UPDATE ' || v.ligne;
      INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
    END LOOP;
    IF v_cmd IS NOT NULL THEN
      INSERT INTO public.acces_utilisateurs (sn, pin, nom, pri, visage_maj, autorise) VALUES (p_sn, r.pin, r.nom, 0, now(), v_acc AND v_ouvert)
      ON CONFLICT (sn, pin) DO UPDATE SET nom = EXCLUDED.nom, visage_maj = now(), maj = now(),
        autorise = CASE WHEN r.u_pin IS NULL OR r.u_nom IS DISTINCT FROM r.nom THEN v_acc AND v_ouvert ELSE acces_utilisateurs.autorise END;
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- Retraits : toute personne (non administrateur) qui n'est plus autorisée sur cette porte
  v_pins := ARRAY(SELECT a.pin FROM public.acces_autorises(v_porte) a);
  IF cardinality(v_pins) = 0
     AND (SELECT count(*) FROM public.acces_utilisateurs WHERE sn = p_sn AND pri = 0) > 3 THEN
    INSERT INTO public.acces_journal (sn, requete, reponse)
    VALUES (p_sn, 'synchro', 'Retraits annulés : aucune personne autorisée sur cette porte (vérifiez les portes des disciplines).');
    RETURN v_n;
  END IF;
  FOR r IN
    SELECT u.pin FROM public.acces_utilisateurs u
    WHERE u.sn = p_sn AND u.pri = 0 AND NOT (u.pin = ANY (v_pins))
  LOOP
    DELETE FROM public.acces_commandes WHERE sn = p_sn AND pin = r.pin AND envoyee_le IS NULL;
    IF v_acc THEN
      INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, 'DATA DELETE userauthorize Pin=' || r.pin);
      INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, 'DATA DELETE user Pin=' || r.pin);
    ELSE
      INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, 'DATA DELETE USERINFO PIN=' || r.pin);
    END IF;
    DELETE FROM public.acces_utilisateurs WHERE sn = p_sn AND pin = r.pin;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

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
  -- Horaires des séances : ouverture / fermeture du droit d'ouvrir, chaque minute
  IF v.derniere_bascule IS NULL OR v.derniere_bascule < now() - interval '50 seconds' THEN
    BEGIN
      PERFORM public.acces_basculer(p_sn);
    EXCEPTION WHEN others THEN
      INSERT INTO public.acces_journal (sn, requete, reponse) VALUES (p_sn, 'horaires', 'ERREUR : ' || SQLERRM);
    END;
    UPDATE public.acces_appareils SET derniere_bascule = now() WHERE sn = p_sn;
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

-- ── Réglage des délais depuis Accès & Portes ──
CREATE OR REPLACE FUNCTION public.acces_regler_horaires(p_avant INT, p_fin INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_perm('acces', 'ecrire') THEN RAISE EXCEPTION 'Droit « Accès & Portes » (écriture) nécessaire.'; END IF;
  IF p_avant IS NULL OR p_avant < 0 OR p_avant > 180 OR p_fin IS NULL OR p_fin < 0 OR p_fin > 180 THEN
    RAISE EXCEPTION 'Délais invalides (entre 0 et 180 minutes).';
  END IF;
  INSERT INTO public.parametres (cle, valeur, updated_at) VALUES ('acces_avant_min', p_avant::text, now()), ('acces_fin_min', p_fin::text, now())
  ON CONFLICT (cle) DO UPDATE SET valeur = EXCLUDED.valeur, updated_at = now();
  UPDATE public.acces_appareils SET derniere_bascule = NULL WHERE derniere_bascule IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.acces_ouverts(INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_basculer(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_synchroniser(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_ouverts(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_basculer(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_synchroniser(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) TO service_role;
REVOKE ALL ON FUNCTION public.acces_regler_horaires(INT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acces_regler_horaires(INT, INT) TO authenticated;

NOTIFY pgrst, 'reload schema';
