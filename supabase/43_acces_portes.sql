-- ════════════════════════════════════════════════════════════════
-- 43 — Contrôle d'accès : 2 appareils ZKTeco SpeedFace-V3L (une porte chacun)
--   • sports.porte : porte de chaque discipline (1, 2 ou 0 = les deux portes)
--   • employes.numero_acces : N° d'accès du personnel (90001, 90002…), à côté des N° d'adhérent des clients
--   • Les appareils se connectent au site (mode ADMS) : le site leur envoie la liste des personnes autorisées
--     et reçoit chaque entrée.
--       – Client autorisé sur une porte = abonnement en cours + une de ses disciplines sur cette porte
--         (et fiche ni « Inactif » ni « Suspendu »)
--       – Coach = portes de ses disciplines ; autre salarié actif = les deux portes
--       – Les administrateurs de l'appareil ne sont jamais modifiés
--   • Le visage enregistré sur un appareil est gardé : il est renvoyé automatiquement à l'autre porte
--     et au renouvellement de l'abonnement (pas besoin de réenregistrer le visage)
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

-- ── Porte de chaque discipline ───────────────────────────────────
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS porte SMALLINT;
ALTER TABLE public.sports DROP CONSTRAINT IF EXISTS sports_porte_check;
ALTER TABLE public.sports ADD CONSTRAINT sports_porte_check CHECK (porte IS NULL OR porte IN (0, 1, 2));

-- ── N° d'accès du personnel ──────────────────────────────────────
ALTER TABLE public.employes ADD COLUMN IF NOT EXISTS numero_acces INT;
CREATE SEQUENCE IF NOT EXISTS public.employes_numero_acces_seq START 90001;
UPDATE public.employes SET numero_acces = nextval('public.employes_numero_acces_seq') WHERE numero_acces IS NULL;
ALTER TABLE public.employes ALTER COLUMN numero_acces SET DEFAULT nextval('public.employes_numero_acces_seq');
CREATE UNIQUE INDEX IF NOT EXISTS employes_numero_acces_uniq ON public.employes (numero_acces);

-- ── Tables ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.acces_appareils (
  sn                 TEXT PRIMARY KEY,                 -- numéro de série
  nom                TEXT,
  porte              SMALLINT CHECK (porte IN (1, 2)),
  actif              BOOLEAN NOT NULL DEFAULT true,
  derniere_connexion TIMESTAMPTZ,
  ip                 TEXT,
  infos              TEXT,
  derniere_synchro   TIMESTAMPTZ,
  synchro_demandee   BOOLEAN NOT NULL DEFAULT true,
  stamp_attlog       TEXT,
  stamp_operlog      TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.acces_appareils (sn, nom) VALUES
  ('NQN5235200109', 'Appareil …0109'),
  ('NQN5235200124', 'Appareil …0124')
ON CONFLICT (sn) DO NOTHING;

-- Personnes présentes sur chaque appareil (d'après le site et ce que l'appareil envoie)
CREATE TABLE IF NOT EXISTS public.acces_utilisateurs (
  sn          TEXT NOT NULL REFERENCES public.acces_appareils(sn) ON DELETE CASCADE,
  pin         TEXT NOT NULL,
  nom         TEXT,
  pri         INT NOT NULL DEFAULT 0,                  -- 14 = administrateur de l'appareil
  visage_maj  TIMESTAMPTZ,
  maj         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (sn, pin)
);

-- Modèles de visage (et N° de badge) envoyés par les appareils, pour les renvoyer à l'autre porte
CREATE TABLE IF NOT EXISTS public.acces_visages (
  pin        TEXT NOT NULL,
  cle        TEXT NOT NULL,
  ligne      TEXT NOT NULL,
  sn_source  TEXT,
  maj        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (pin, cle)
);

-- File d'attente des commandes à envoyer aux appareils
CREATE TABLE IF NOT EXISTS public.acces_commandes (
  id          BIGSERIAL PRIMARY KEY,
  sn          TEXT NOT NULL REFERENCES public.acces_appareils(sn) ON DELETE CASCADE,
  pin         TEXT,
  commande    TEXT NOT NULL,
  cree_le     TIMESTAMPTZ NOT NULL DEFAULT now(),
  envoyee_le  TIMESTAMPTZ,
  tentatives  INT NOT NULL DEFAULT 0,
  retour      INT,
  termine_le  TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS acces_commandes_attente_idx ON public.acces_commandes (sn, id) WHERE termine_le IS NULL;

-- Entrées (passages reconnus par les appareils)
CREATE TABLE IF NOT EXISTS public.acces_entrees (
  id            BIGSERIAL PRIMARY KEY,
  sn            TEXT NOT NULL,
  porte         SMALLINT,
  pin           TEXT NOT NULL,
  date_heure    TIMESTAMP NOT NULL,                     -- heure de l'appareil (heure du Maroc)
  statut        INT,
  verification  INT,
  client_id     UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  employe_id    UUID REFERENCES public.employes(id) ON DELETE SET NULL,
  recu_le       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sn, pin, date_heure)
);
CREATE INDEX IF NOT EXISTS acces_entrees_date_idx ON public.acces_entrees (date_heure DESC);
CREATE INDEX IF NOT EXISTS acces_entrees_client_idx ON public.acces_entrees (client_id);

-- Journal technique (échanges avec les appareils, gardé 7 jours)
CREATE TABLE IF NOT EXISTS public.acces_journal (
  id        BIGSERIAL PRIMARY KEY,
  le        TIMESTAMPTZ NOT NULL DEFAULT now(),
  sn        TEXT,
  requete   TEXT,
  corps     TEXT,
  reponse   TEXT
);

-- ── Fin de couverture d'un abonnement (même règle que l'application) ──
-- Payé le 21/09 (mensuel) → couvert jusqu'au 20/10 ; payé le 31/01 → jusqu'au 28/02
CREATE OR REPLACE FUNCTION public.acces_fin_couverture(p_date DATE, p_type TEXT)
RETURNS DATE
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
           WHEN x.n IS NULL OR p_date IS NULL THEN NULL
           WHEN extract(day FROM (p_date + make_interval(months => x.n))) < extract(day FROM p_date)
             THEN (p_date + make_interval(months => x.n))::date
           ELSE (p_date + make_interval(months => x.n))::date - 1
         END
  FROM (SELECT CASE p_type WHEN 'Mensualité' THEN 1 WHEN 'Trimestriel' THEN 3
                           WHEN 'Semestriel' THEN 6 WHEN 'Annuel' THEN 12 END AS n) x
$$;

-- Nom affiché sur l'appareil : sans accents, 24 caractères au plus
CREATE OR REPLACE FUNCTION public.acces_nom(p_prenom TEXT, p_nom TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT left(trim(regexp_replace(
           translate(coalesce(p_prenom, '') || ' ' || coalesce(p_nom, ''),
                     'éèêëàâäîïôöûüùçÉÈÊËÀÂÄÎÏÔÖÛÜÙÇ', 'eeeeaaaiioouuucEEEEAAAIIOOUUUC'),
           '[\t\r\n=]+', ' ', 'g')), 24)
$$;

-- ── Personnes autorisées sur une porte ──────────────────────────
CREATE OR REPLACE FUNCTION public.acces_autorises(p_porte INT)
RETURNS TABLE (pin TEXT, nom TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Clients : abonnement en cours + une discipline sur cette porte
  SELECT c.numero_adherent::text, public.acces_nom(c.prenom, c.nom)
  FROM public.clients c
  WHERE c.numero_adherent IS NOT NULL
    AND coalesce(c.statut, 'Actif') NOT IN ('Inactif', 'Suspendu')
    AND EXISTS (
      SELECT 1 FROM public.paiements p
      WHERE p.client_id = c.id
        AND p.date_paiement::date <= (now() AT TIME ZONE 'Africa/Casablanca')::date
        AND public.acces_fin_couverture(p.date_paiement::date, p.type) >= (now() AT TIME ZONE 'Africa/Casablanca')::date)
    AND EXISTS (
      SELECT 1 FROM public.sports s
      WHERE (s.porte = p_porte OR s.porte = 0)
        AND (to_jsonb(c.sports) ? s.nom OR s.nom = c.sport))
  UNION
  -- Personnel actif : un coach passe par les portes de ses disciplines, les autres salariés par les deux
  SELECT e.numero_acces::text, public.acces_nom(e.prenom, e.nom)
  FROM public.employes e
  WHERE e.numero_acces IS NOT NULL
    AND e.actif IS DISTINCT FROM false
    AND (
      NOT EXISTS (SELECT 1 FROM public.sports s
                  WHERE lower(trim(s.coach)) = lower(trim(coalesce(e.prenom, '') || ' ' || coalesce(e.nom, ''))))
      OR EXISTS (SELECT 1 FROM public.sports s
                 WHERE lower(trim(s.coach)) = lower(trim(coalesce(e.prenom, '') || ' ' || coalesce(e.nom, '')))
                   AND (s.porte = p_porte OR s.porte = 0)))
$$;

-- ── Synchronisation d'un appareil : prépare les ajouts / retraits ──
CREATE OR REPLACE FUNCTION public.acces_synchroniser(p_sn TEXT)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_porte SMALLINT;
  v_n     INT := 0;
  v_pins  TEXT[];
  v_cmd   TEXT;
  r       RECORD;
  v       RECORD;
BEGIN
  SELECT porte INTO v_porte FROM public.acces_appareils WHERE sn = p_sn AND actif;
  UPDATE public.acces_appareils SET synchro_demandee = false, derniere_synchro = now() WHERE sn = p_sn;
  -- Ménage
  DELETE FROM public.acces_journal WHERE le < now() - interval '7 days';
  DELETE FROM public.acces_commandes WHERE termine_le < now() - interval '30 days';
  IF v_porte IS NULL THEN RETURN 0; END IF;   -- porte pas encore choisie : on ne touche à rien

  -- Ajouts et mises à jour
  FOR r IN
    SELECT a.pin, a.nom, u.pin AS u_pin, u.nom AS u_nom, coalesce(u.pri, 0) AS u_pri, u.visage_maj,
           (SELECT vc.ligne FROM public.acces_visages vc WHERE vc.pin = a.pin AND vc.cle = 'CARTE') AS carte
    FROM public.acces_autorises(v_porte) a
    LEFT JOIN public.acces_utilisateurs u ON u.sn = p_sn AND u.pin = a.pin
  LOOP
    IF r.u_pri > 0 THEN CONTINUE; END IF;     -- administrateur de l'appareil : jamais modifié
    v_cmd := NULL;
    IF r.u_pin IS NULL OR r.u_nom IS DISTINCT FROM r.nom THEN
      DELETE FROM public.acces_commandes WHERE sn = p_sn AND pin = r.pin AND envoyee_le IS NULL;
      v_cmd := 'DATA UPDATE USERINFO PIN=' || r.pin || E'\tName=' || r.nom || E'\tPri=0'
               || CASE WHEN r.carte IS NOT NULL THEN E'\tCard=' || r.carte ELSE '' END;
      INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, v_cmd);
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
      INSERT INTO public.acces_utilisateurs (sn, pin, nom, pri, visage_maj) VALUES (p_sn, r.pin, r.nom, 0, now())
      ON CONFLICT (sn, pin) DO UPDATE SET nom = EXCLUDED.nom, visage_maj = now(), maj = now();
      v_n := v_n + 1;
    END IF;
  END LOOP;

  -- Retraits : toute personne (non administrateur) qui n'est plus autorisée sur cette porte
  v_pins := ARRAY(SELECT a.pin FROM public.acces_autorises(v_porte) a);
  IF cardinality(v_pins) = 0
     AND (SELECT count(*) FROM public.acces_utilisateurs WHERE sn = p_sn AND pri = 0) > 3 THEN
    -- Garde-fou : personne d'autorisé alors que l'appareil est rempli → on ne vide pas l'appareil
    INSERT INTO public.acces_journal (sn, requete, reponse)
    VALUES (p_sn, 'synchro', 'Retraits annulés : aucune personne autorisée sur cette porte (vérifiez les portes des disciplines).');
    RETURN v_n;
  END IF;
  FOR r IN
    SELECT u.pin FROM public.acces_utilisateurs u
    WHERE u.sn = p_sn AND u.pri = 0 AND NOT (u.pin = ANY (v_pins))
  LOOP
    DELETE FROM public.acces_commandes WHERE sn = p_sn AND pin = r.pin AND envoyee_le IS NULL;
    INSERT INTO public.acces_commandes (sn, pin, commande) VALUES (p_sn, r.pin, 'DATA DELETE USERINFO PIN=' || r.pin);
    DELETE FROM public.acces_utilisateurs WHERE sn = p_sn AND pin = r.pin;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ── Appelées par le site quand un appareil se connecte (clé secrète du serveur uniquement) ──

-- Premier contact (au démarrage de l'appareil)
CREATE OR REPLACE FUNCTION public.acces_connexion(p_sn TEXT, p_ip TEXT, p_infos TEXT)
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
  SET derniere_connexion = now(), ip = coalesce(p_ip, ip), infos = coalesce(nullif(p_infos, ''), infos), synchro_demandee = true
  WHERE sn = p_sn;
  RETURN jsonb_build_object('attlog', v.stamp_attlog, 'operlog', v.stamp_operlog);
END;
$$;

-- Interrogation régulière : renvoie les commandes en attente (format ADMS « C:id:commande »)
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
    PERFORM public.acces_synchroniser(p_sn);
  END IF;
  -- Une commande sans réponse après 5 essais est abandonnée
  UPDATE public.acces_commandes SET termine_le = now(), retour = -999
  WHERE sn = p_sn AND termine_le IS NULL AND tentatives >= 5;
  FOR r IN
    SELECT id, commande FROM public.acces_commandes
    WHERE sn = p_sn AND termine_le IS NULL
      AND (envoyee_le IS NULL OR envoyee_le < now() - interval '3 minutes')
    ORDER BY id
    LIMIT 25
  LOOP
    txt := txt || 'C:' || r.id || ':' || r.commande || E'\n';
    UPDATE public.acces_commandes SET envoyee_le = now(), tentatives = tentatives + 1 WHERE id = r.id;
  END LOOP;
  RETURN txt;
END;
$$;

-- Données envoyées par l'appareil : entrées, personnes, visages
-- p_donnees : [{type:'ATTLOG', pin, date_heure, statut, verification}
--              | {type:'USER', pin, nom, pri, carte} | {type:'BIO', pin, cle, ligne}]
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
        INSERT INTO public.acces_entrees (sn, porte, pin, date_heure, statut, verification, client_id, employe_id)
        VALUES (p_sn, v_porte, v_pin, (e->>'date_heure')::timestamp,
                nullif(e->>'statut', '')::int, nullif(e->>'verification', '')::int,
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

  IF v_change THEN UPDATE public.acces_appareils SET synchro_demandee = true; END IF;
  RETURN v_n;
END;
$$;

-- Résultats des commandes (p_res : [{id, retour}]) ; un échec sera retenté à la prochaine synchro
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
      IF c.commande LIKE 'DATA UPDATE USERINFO%' THEN
        DELETE FROM public.acces_utilisateurs WHERE sn = p_sn AND pin = c.pin;
      ELSIF c.commande LIKE 'DATA DELETE USERINFO%' THEN
        INSERT INTO public.acces_utilisateurs (sn, pin) VALUES (p_sn, c.pin) ON CONFLICT DO NOTHING;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$$;

CREATE OR REPLACE FUNCTION public.acces_journaliser(p_sn TEXT, p_requete TEXT, p_corps TEXT, p_reponse TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.acces_journal (sn, requete, corps, reponse)
  VALUES (p_sn, left(p_requete, 500), left(p_corps, 2000), left(p_reponse, 2000));
$$;

-- ── Bouton « Synchroniser » de l'application ─────────────────────
-- p_tout = true : renvoie toutes les personnes (et visages) à l'appareil
CREATE OR REPLACE FUNCTION public.acces_demander_synchro(p_sn TEXT, p_tout BOOLEAN DEFAULT false)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_perm('acces', 'ecrire') THEN RAISE EXCEPTION 'Droit « Accès & Portes » (écriture) nécessaire.'; END IF;
  IF p_tout THEN
    DELETE FROM public.acces_commandes WHERE (p_sn IS NULL OR sn = p_sn) AND termine_le IS NULL;
    DELETE FROM public.acces_utilisateurs WHERE (p_sn IS NULL OR sn = p_sn) AND pri = 0;
  END IF;
  UPDATE public.acces_appareils SET synchro_demandee = true WHERE p_sn IS NULL OR sn = p_sn;
END;
$$;

-- ── Droits d'exécution ───────────────────────────────────────────
REVOKE ALL ON FUNCTION public.acces_autorises(INT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_synchroniser(TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_connexion(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_resultats(TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.acces_journaliser(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_connexion(TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_requete(TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_recevoir(TEXT, TEXT, TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_resultats(TEXT, JSONB) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_journaliser(TEXT, TEXT, TEXT, TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_synchroniser(TEXT) TO service_role;
GRANT EXECUTE ON FUNCTION public.acces_autorises(INT) TO service_role;
REVOKE ALL ON FUNCTION public.acces_demander_synchro(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.acces_demander_synchro(TEXT, BOOLEAN) TO authenticated;

-- ── Une modification (paiement, fiche, discipline, salarié) → synchro au prochain passage ──
CREATE OR REPLACE FUNCTION public.acces_marquer_synchro()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.acces_appareils SET synchro_demandee = true WHERE NOT synchro_demandee;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_acces_synchro ON public.paiements;
CREATE TRIGGER trg_acces_synchro AFTER INSERT OR UPDATE OR DELETE ON public.paiements
  FOR EACH STATEMENT EXECUTE FUNCTION public.acces_marquer_synchro();
DROP TRIGGER IF EXISTS trg_acces_synchro ON public.clients;
CREATE TRIGGER trg_acces_synchro AFTER INSERT OR UPDATE OR DELETE ON public.clients
  FOR EACH STATEMENT EXECUTE FUNCTION public.acces_marquer_synchro();
DROP TRIGGER IF EXISTS trg_acces_synchro ON public.sports;
CREATE TRIGGER trg_acces_synchro AFTER INSERT OR UPDATE OR DELETE ON public.sports
  FOR EACH STATEMENT EXECUTE FUNCTION public.acces_marquer_synchro();
DROP TRIGGER IF EXISTS trg_acces_synchro ON public.employes;
CREATE TRIGGER trg_acces_synchro AFTER INSERT OR UPDATE OR DELETE ON public.employes
  FOR EACH STATEMENT EXECUTE FUNCTION public.acces_marquer_synchro();

-- ── Sécurité (RLS) : module « Accès & Portes » ───────────────────
ALTER TABLE public.acces_appareils    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_utilisateurs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_visages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_commandes    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_entrees      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.acces_journal      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "acces_appareils_select" ON public.acces_appareils;
DROP POLICY IF EXISTS "acces_appareils_update" ON public.acces_appareils;
CREATE POLICY "acces_appareils_select" ON public.acces_appareils FOR SELECT USING (public.has_perm('acces', 'lire'));
CREATE POLICY "acces_appareils_update" ON public.acces_appareils FOR UPDATE
  USING (public.has_perm('acces', 'ecrire')) WITH CHECK (public.has_perm('acces', 'ecrire'));

DROP POLICY IF EXISTS "acces_utilisateurs_select" ON public.acces_utilisateurs;
CREATE POLICY "acces_utilisateurs_select" ON public.acces_utilisateurs FOR SELECT USING (public.has_perm('acces', 'lire'));

DROP POLICY IF EXISTS "acces_commandes_select" ON public.acces_commandes;
CREATE POLICY "acces_commandes_select" ON public.acces_commandes FOR SELECT USING (public.has_perm('acces', 'lire'));

DROP POLICY IF EXISTS "acces_entrees_select" ON public.acces_entrees;
CREATE POLICY "acces_entrees_select" ON public.acces_entrees FOR SELECT USING (public.has_perm('acces', 'lire'));

DROP POLICY IF EXISTS "acces_journal_select" ON public.acces_journal;
CREATE POLICY "acces_journal_select" ON public.acces_journal FOR SELECT USING (public.has_perm('acces', 'ecrire'));

-- Visages : seule l'information « a un visage » est lisible (jamais le modèle biométrique)
REVOKE ALL ON public.acces_visages FROM anon, authenticated;
GRANT SELECT (pin, cle, sn_source, maj) ON public.acces_visages TO authenticated;
DROP POLICY IF EXISTS "acces_visages_select" ON public.acces_visages;
CREATE POLICY "acces_visages_select" ON public.acces_visages FOR SELECT USING (public.has_perm('acces', 'lire'));

NOTIFY pgrst, 'reload schema';
