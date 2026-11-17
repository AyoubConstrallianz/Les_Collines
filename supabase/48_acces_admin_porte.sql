-- ════════════════════════════════════════════════════════════════
-- 48 — Contrôle d'accès : un administrateur de l'appareil reçoit aussi le droit d'ouvrir la porte
--   Sa fiche (nom, badge, rôle) n'est toujours jamais modifiée par le site ; seul le droit
--   « userauthorize » de la porte lui est envoyé, s'il a droit à cette porte.
-- Prérequis : scripts 44 à 46. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

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
BEGIN
  SELECT porte, coalesce(protocole, 'att') = 'acc' INTO v_porte, v_acc FROM public.acces_appareils WHERE sn = p_sn AND actif;
  UPDATE public.acces_appareils SET synchro_demandee = false, derniere_synchro = now() WHERE sn = p_sn;
  DELETE FROM public.acces_journal WHERE le < now() - interval '7 days';
  DELETE FROM public.acces_commandes WHERE termine_le < now() - interval '30 days';
  IF v_porte IS NULL THEN RETURN 0; END IF;

  -- Ajouts et mises à jour
  FOR r IN
    SELECT a.pin, a.nom, u.pin AS u_pin, u.nom AS u_nom, coalesce(u.pri, 0) AS u_pri, u.visage_maj,
           coalesce(u.autorise, false) AS u_autorise,
           (SELECT vc.ligne FROM public.acces_visages vc WHERE vc.pin = a.pin AND vc.cle = 'CARTE') AS carte
    FROM public.acces_autorises(v_porte) a
    LEFT JOIN public.acces_utilisateurs u ON u.sn = p_sn AND u.pin = a.pin
  LOOP
    IF r.u_pri > 0 THEN
      -- Administrateur de l'appareil : sa fiche n'est jamais modifiée, mais il reçoit le droit d'ouvrir la porte
      IF v_acc AND NOT r.u_autorise THEN
        INSERT INTO public.acces_commandes (sn, pin, commande)
        VALUES (p_sn, r.pin, 'DATA UPDATE userauthorize Pin=' || r.pin || E'\tAuthorizeTimezoneId=1\tAuthorizeDoorId=1');
        UPDATE public.acces_utilisateurs SET autorise = true WHERE sn = p_sn AND pin = r.pin;
      END IF;
      CONTINUE;
    END IF;
    v_cmd := NULL;
    IF r.u_pin IS NULL OR r.u_nom IS DISTINCT FROM r.nom OR (v_acc AND NOT r.u_autorise) THEN
      DELETE FROM public.acces_commandes WHERE sn = p_sn AND pin = r.pin AND envoyee_le IS NULL;
      IF v_acc THEN
        v_cmd := 'DATA UPDATE user CardNo=' || coalesce(r.carte, '') || E'\tPin=' || r.pin
                 || E'\tPassword=\tGroup=0\tStartTime=0\tEndTime=0\tName=' || r.nom || E'\tPrivilege=0';
        INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
        v_cmd := 'DATA UPDATE userauthorize Pin=' || r.pin || E'\tAuthorizeTimezoneId=1\tAuthorizeDoorId=1';
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
      INSERT INTO public.acces_utilisateurs (sn, pin, nom, pri, visage_maj, autorise) VALUES (p_sn, r.pin, r.nom, 0, now(), true)
      ON CONFLICT (sn, pin) DO UPDATE SET nom = EXCLUDED.nom, visage_maj = now(), autorise = true, maj = now();
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

REVOKE ALL ON FUNCTION public.acces_synchroniser(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_synchroniser(TEXT) TO service_role;

UPDATE public.acces_appareils SET synchro_demandee = true WHERE NOT synchro_demandee;

NOTIFY pgrst, 'reload schema';
