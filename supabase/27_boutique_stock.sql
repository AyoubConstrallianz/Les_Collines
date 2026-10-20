-- ════════════════════════════════════════════════════════════════
-- 27 — Boutique avec gestion de stock
--   • produits          : catalogue (nom, catégorie, prix d'achat, prix de vente, stock, seuil d'alerte)
--   • stock_mouvements  : historique de chaque entrée / sortie (achat, vente, ajustement d'inventaire, retour)
--   • ventes            : + article du catalogue (produit_id) et quantité
--   • Le stock se calcule tout seul : achat → +, vente → −, vente supprimée → stock remis.
--     Une vente est refusée si le stock est insuffisant.
--   • Les articles déjà vendus (boutique simple) sont ajoutés au catalogue avec un stock de 0.
-- Script autonome (inutile de lancer 20 ou 21). À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

-- ── Ventes (créée ici si le script 21 n'a pas été exécuté) ──────────────────
CREATE TABLE IF NOT EXISTS public.ventes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date_vente  DATE NOT NULL DEFAULT CURRENT_DATE,
  client_id   UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  client_nom  TEXT,
  created_by  UUID DEFAULT auth.uid(),
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS article    TEXT;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS prix_achat NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS prix_vente NUMERIC(10,2) NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS ventes_date_idx ON public.ventes (date_vente);

-- ── Catalogue ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.produits (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom         TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS categorie    TEXT;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS prix_achat   NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS prix_vente   NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS stock        INT NOT NULL DEFAULT 0;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS seuil_alerte INT NOT NULL DEFAULT 2;
ALTER TABLE public.produits ADD COLUMN IF NOT EXISTS actif        BOOLEAN NOT NULL DEFAULT true;
CREATE UNIQUE INDEX IF NOT EXISTS produits_nom_uniq ON public.produits (lower(trim(nom)));

-- ── Ventes : article du catalogue + quantité (prix_achat / prix_vente = prix UNITAIRES) ─
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS produit_id UUID REFERENCES public.produits(id) ON DELETE SET NULL;
ALTER TABLE public.ventes ADD COLUMN IF NOT EXISTS quantite   INT NOT NULL DEFAULT 1;
DO $$ BEGIN
  ALTER TABLE public.ventes ADD CONSTRAINT ventes_quantite_positive CHECK (quantite > 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── Mouvements de stock ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stock_mouvements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_mouvement  DATE NOT NULL DEFAULT CURRENT_DATE,
  produit_id      UUID NOT NULL REFERENCES public.produits(id) ON DELETE CASCADE,
  type            TEXT NOT NULL CHECK (type IN ('Achat','Vente','Ajustement','Retour')),
  quantite        INT NOT NULL CHECK (quantite <> 0),          -- + entrée, − sortie
  prix_unitaire   NUMERIC(10,2) NOT NULL DEFAULT 0,
  vente_id        UUID REFERENCES public.ventes(id) ON DELETE CASCADE,
  note            TEXT,
  created_by      UUID DEFAULT auth.uid()
);
CREATE INDEX IF NOT EXISTS stock_mouvements_produit_idx ON public.stock_mouvements (produit_id, date_mouvement DESC);
CREATE INDEX IF NOT EXISTS stock_mouvements_vente_idx   ON public.stock_mouvements (vente_id);

-- Stock = somme des mouvements (tenu à jour automatiquement, jamais négatif)
CREATE OR REPLACE FUNCTION public.maj_stock_produit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock INT;
  v_nom   TEXT;
BEGIN
  IF TG_OP IN ('UPDATE','DELETE') THEN
    UPDATE public.produits SET stock = stock - OLD.quantite WHERE id = OLD.produit_id RETURNING stock, nom INTO v_stock, v_nom;
    IF v_stock < 0 THEN
      RAISE EXCEPTION 'Stock insuffisant pour « % » : il manquerait % unité(s).', v_nom, -v_stock;
    END IF;
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') THEN
    UPDATE public.produits SET stock = stock + NEW.quantite WHERE id = NEW.produit_id RETURNING stock, nom INTO v_stock, v_nom;
    IF v_stock < 0 THEN
      RAISE EXCEPTION 'Stock insuffisant pour « % » : il manque % unité(s).', v_nom, -v_stock;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_maj_stock ON public.stock_mouvements;
CREATE TRIGGER trg_maj_stock AFTER INSERT OR UPDATE OR DELETE ON public.stock_mouvements
  FOR EACH ROW EXECUTE FUNCTION public.maj_stock_produit();

-- Une vente d'un article du catalogue crée sa sortie de stock (modifiée / supprimée avec la vente)
CREATE OR REPLACE FUNCTION public.vente_sortie_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.produit_id IS NOT DISTINCT FROM OLD.produit_id AND NEW.quantite = OLD.quantite
     AND NEW.date_vente = OLD.date_vente AND NEW.prix_vente = OLD.prix_vente THEN
    RETURN NULL;                                    -- rien qui touche au stock
  END IF;
  IF TG_OP IN ('UPDATE','DELETE') THEN
    DELETE FROM public.stock_mouvements WHERE vente_id = OLD.id;
  END IF;
  IF TG_OP IN ('INSERT','UPDATE') AND NEW.produit_id IS NOT NULL THEN
    INSERT INTO public.stock_mouvements (date_mouvement, produit_id, type, quantite, prix_unitaire, vente_id)
    VALUES (NEW.date_vente, NEW.produit_id, 'Vente', -NEW.quantite, NEW.prix_vente, NEW.id);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_vente_stock ON public.ventes;
CREATE TRIGGER trg_vente_stock AFTER INSERT OR UPDATE OR DELETE ON public.ventes
  FOR EACH ROW EXECUTE FUNCTION public.vente_sortie_stock();

-- ── Catalogue de départ : les articles déjà vendus (stock 0, derniers prix) ──
INSERT INTO public.produits (nom, prix_achat, prix_vente, stock)
SELECT DISTINCT ON (lower(trim(article))) trim(article), coalesce(prix_achat, 0), coalesce(prix_vente, 0), 0
FROM public.ventes
WHERE coalesce(trim(article), '') <> ''
ORDER BY lower(trim(article)), date_vente DESC
ON CONFLICT DO NOTHING;

-- ── Sécurité (RLS) : module « boutique » ───────────────────────────────────
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['ventes','produits','stock_mouvements'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_select" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_insert" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_update" ON public.%I', t, t);
    EXECUTE format('DROP POLICY IF EXISTS "%s_delete" ON public.%I', t, t);
    EXECUTE format('CREATE POLICY "%s_select" ON public.%I FOR SELECT USING (public.has_perm(''boutique'',''lire''))', t, t);
    EXECUTE format('CREATE POLICY "%s_insert" ON public.%I FOR INSERT WITH CHECK (public.has_perm(''boutique'',''ecrire''))', t, t);
    EXECUTE format('CREATE POLICY "%s_update" ON public.%I FOR UPDATE USING (public.has_perm(''boutique'',''ecrire''))', t, t);
    EXECUTE format('CREATE POLICY "%s_delete" ON public.%I FOR DELETE USING (public.has_perm(''boutique'',''supprimer''))', t, t);
  END LOOP;
END $$;

-- ── Validation des gérants (script 25) : suivre aussi le catalogue et les mouvements ─
-- Le stock recalculé automatiquement n'est pas une « modification » à valider.
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.produits';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.produits FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.stock_mouvements';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.stock_mouvements FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

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
  IF to_regclass('public.modifications') IS NULL THEN RETURN NULL; END IF;   -- script 25 non exécuté
  IF public.get_my_role() IS DISTINCT FROM 'gerant' THEN RETURN NULL; END IF;
  -- Sorties de stock créées automatiquement par une vente : suivies via la vente elle-même
  IF TG_TABLE_NAME = 'stock_mouvements' AND (v_ligne->>'vente_id') IS NOT NULL THEN RETURN NULL; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF (v_avant - 'updated_at') = (v_apres - 'updated_at') THEN RETURN NULL; END IF;
    IF TG_TABLE_NAME = 'clients'
       AND (v_avant - 'updated_at' - 'statut') = (v_apres - 'updated_at' - 'statut')
       AND (v_avant->>'statut') IN ('Actif','Inactif') AND (v_apres->>'statut') IN ('Actif','Inactif') THEN
      RETURN NULL;
    END IF;
    -- Stock recalculé par les mouvements
    IF TG_TABLE_NAME = 'produits' AND (v_avant - 'stock') = (v_apres - 'stock') THEN RETURN NULL; END IF;
  END IF;
  SELECT trim(coalesce(prenom,'') || ' ' || coalesce(nom,'')) INTO v_nom FROM public.profils WHERE id = auth.uid();
  INSERT INTO public.modifications (user_id, user_nom, table_nom, operation, ligne_id, avant, apres)
  VALUES (auth.uid(), v_nom, TG_TABLE_NAME, TG_OP, COALESCE(v_ligne->>'id', v_ligne->>'cle'), v_avant, v_apres);
  RETURN NULL;
END;
$$;

DO $$
BEGIN
  -- Annulation d'un refus : le stock (recalculé) est ignoré dans la comparaison « modifié depuis »
  IF to_regproc('public.annuler_une_modification') IS NOT NULL THEN
    EXECUTE $f$
    CREATE OR REPLACE FUNCTION public.annuler_une_modification(p_id BIGINT)
    RETURNS void
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public
    AS $body$
    DECLARE
      m        RECORD;
      v_cle    TEXT;
      v_actuel JSONB;
      v_set    TEXT;
      v_libre  TEXT;
      v_ign    TEXT[];
    BEGIN
      IF public.get_my_role() IS DISTINCT FROM 'super_admin' THEN
        RAISE EXCEPTION 'Action réservée au super admin';
      END IF;
      SELECT * INTO m FROM public.modifications WHERE id = p_id AND statut = 'En attente';
      IF NOT FOUND THEN RETURN; END IF;
      v_cle := CASE WHEN m.table_nom = 'parametres' THEN 'cle' ELSE 'id' END;
      v_ign := CASE m.table_nom WHEN 'clients' THEN ARRAY['updated_at','statut']
                                WHEN 'produits' THEN ARRAY['updated_at','stock'] ELSE ARRAY['updated_at'] END;
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
        WHERE k <> v_cle AND NOT (k = ANY(v_ign) AND m.table_nom = 'produits')
          AND EXISTS (SELECT 1 FROM information_schema.columns c
                      WHERE c.table_schema = 'public' AND c.table_name = m.table_nom AND c.column_name = k
                        AND c.is_generated = 'NEVER');
        IF v_set IS NOT NULL THEN
          EXECUTE format('UPDATE public.%I t SET %s FROM jsonb_populate_record(NULL::public.%I, $1) r WHERE t.%I::text = $2',
                         m.table_nom, v_set, m.table_nom, v_cle) USING m.avant, m.ligne_id;
        END IF;

      ELSE
        IF v_actuel IS NOT NULL THEN
          RAISE EXCEPTION 'Refus impossible : % existe de nouveau.', v_libre;
        END IF;
        IF m.table_nom = 'produits' THEN
          -- Article recréé avec un stock de 0 : ses mouvements (supprimés avec lui) ne reviennent pas
          EXECUTE 'INSERT INTO public.produits SELECT * FROM jsonb_populate_record(NULL::public.produits, $1)'
            USING jsonb_set(m.avant, '{stock}', '0'::jsonb);
        ELSE
          EXECUTE format('INSERT INTO public.%I SELECT * FROM jsonb_populate_record(NULL::public.%I, $1)',
                         m.table_nom, m.table_nom) USING m.avant;
        END IF;
      END IF;
    END;
    $body$;
    $f$;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
