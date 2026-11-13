-- ════════════════════════════════════════════════════════════════
-- 44 — Contrôle d'accès : protocole « contrôle d'accès » (Push 3.x, DeviceType=acc)
--   Les SpeedFace-V3L se présentent en mode « acc » : les personnes s'envoient avec
--   « user » + « userauthorize » (droit d'ouvrir la porte), et non « USERINFO ».
--   • acces_appareils.protocole : 'acc' ou 'att', noté à la connexion de l'appareil
--   • À chaque connexion d'un appareil « acc », le site lui demande la liste de ses
--     utilisateurs et visages (pour garder les visages déjà enregistrés sur l'appareil)
-- Prérequis : script 43. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.acces_appareils ADD COLUMN IF NOT EXISTS protocole TEXT;
ALTER TABLE public.acces_utilisateurs ADD COLUMN IF NOT EXISTS autorise BOOLEAN NOT NULL DEFAULT false;

-- ── Connexion : note le protocole ; en « acc », demande la liste des utilisateurs et visages ──
DROP FUNCTION IF EXISTS public.acces_connexion(TEXT, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.acces_connexion(p_sn TEXT, p_ip TEXT, p_infos TEXT, p_protocole TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v RECORD;
BEGIN
  SELECT * INTO v FROM public.acces_appareils WHERE sn = p_sn AND actif;
  IF NOT FOUND THEN
    INSERT INTO public.acces_journal (sn, requete, reponse) VALUES (p_sn, 'connexion ' || coalesce(p_infos, ''), 'Appareil inconnu : refusé');
    RETURN NULL;
  END IF;
  UPDATE public.acces_appareils
  SET derniere_connexion = now(), ip = coalesce(p_ip, ip), infos = coalesce(nullif(p_infos, ''), infos),
      protocole = coalesce(nullif(p_protocole, ''), protocole), synchro_demandee = true
  WHERE sn = p_sn;
  IF p_protocole = 'acc' THEN
    INSERT INTO public.acces_commandes (sn, commande)
    SELECT p_sn, q FROM unnest(ARRAY['DATA QUERY tablename=user,fielddesc=*,filter=*',
                                     'DATA QUERY tablename=biodata,fielddesc=*,filter=*']) AS q
    WHERE NOT EXISTS (SELECT 1 FROM public.acces_commandes c WHERE c.sn = p_sn AND c.commande = q AND c.termine_le IS NULL);
  END IF;
  RETURN jsonb_build_object('attlog', v.stamp_attlog, 'operlog', v.stamp_operlog);
END;
$$;
REVOKE ALL ON FUNCTION public.acces_connexion(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_connexion(TEXT, TEXT, TEXT, TEXT) TO service_role;

-- ── Synchronisation : commandes selon le protocole de l'appareil ──
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
    IF r.u_pri > 0 THEN CONTINUE; END IF;     -- administrateur de l'appareil : jamais modifié
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

-- ── Résultats : un échec sera retenté à la prochaine synchro ──
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
BEGIN
  FOR e IN SELECT * FROM jsonb_array_elements(coalesce(p_res, '[]'::jsonb)) LOOP
    UPDATE public.acces_commandes
    SET retour = nullif(e->>'retour', '')::int, termine_le = now()
    WHERE id = nullif(e->>'id', '')::bigint AND sn = p_sn
    RETURNING commande, pin INTO c;
    CONTINUE WHEN NOT FOUND;
    v_n := v_n + 1;
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

NOTIFY pgrst, 'reload schema';
