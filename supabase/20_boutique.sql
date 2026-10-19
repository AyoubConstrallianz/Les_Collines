-- ════════════════════════════════════════════════════════════════
-- 20 — Boutique : produits (gants, T-shirts…), tailles avec stock, ventes
--   • produits            : nom, catégorie, prix de vente / d'achat
--   • produit_variantes   : taille / couleur d'un produit, avec son stock et un seuil d'alerte
--   • ventes + vente_lignes : une vente (client facultatif) et ses articles
--   • Le stock diminue à chaque vente et est remis si la vente est supprimée (triggers)
--   • Droits : module « boutique » (Utilisateurs → Habilitations)
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.produits (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom         TEXT NOT NULL,
  categorie   TEXT,
  prix_vente  NUMERIC(10,2) NOT NULL DEFAULT 0,
  prix_achat  NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.produit_variantes (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  produit_id    UUID NOT NULL REFERENCES public.produits(id) ON DELETE CASCADE,
  libelle       TEXT NOT NULL DEFAULT 'Unique',
  stock         INT  NOT NULL DEFAULT 0,
  seuil_alerte  INT  NOT NULL DEFAULT 3
);
CREATE INDEX IF NOT EXISTS produit_variantes_produit_idx ON public.produit_variantes (produit_id);

CREATE TABLE IF NOT EXISTS public.ventes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  date_vente  DATE NOT NULL DEFAULT CURRENT_DATE,
  client_id   UUID REFERENCES public.clients(id) ON DELETE SET NULL,
  client_nom  TEXT,
  mode        TEXT NOT NULL DEFAULT 'Espèces',
  total       NUMERIC(10,2) NOT NULL DEFAULT 0,
  note        TEXT,
  created_by  UUID DEFAULT auth.uid(),
  created_at  TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ventes_date_idx ON public.ventes (date_vente);

CREATE TABLE IF NOT EXISTS public.vente_lignes (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vente_id          UUID NOT NULL REFERENCES public.ventes(id) ON DELETE CASCADE,
  variante_id       UUID REFERENCES public.produit_variantes(id) ON DELETE SET NULL,
  produit_nom       TEXT NOT NULL,
  variante_libelle  TEXT,
  quantite          INT NOT NULL CHECK (quantite > 0),
  prix_unitaire     NUMERIC(10,2) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS vente_lignes_vente_idx ON public.vente_lignes (vente_id);

-- ── Stock : diminue à la vente, remis si la ligne est supprimée ─────────────
CREATE OR REPLACE FUNCTION public.maj_stock_vente()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_stock INT;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.variante_id IS NOT NULL THEN
      UPDATE public.produit_variantes SET stock = stock - NEW.quantite
      WHERE id = NEW.variante_id RETURNING stock INTO v_stock;
      IF v_stock < 0 THEN
        RAISE EXCEPTION 'Stock insuffisant pour %', NEW.produit_nom;
      END IF;
    END IF;
    RETURN NEW;
  ELSE
    IF OLD.variante_id IS NOT NULL THEN
      UPDATE public.produit_variantes SET stock = stock + OLD.quantite WHERE id = OLD.variante_id;
    END IF;
    RETURN OLD;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_stock_vente_ins ON public.vente_lignes;
CREATE TRIGGER trg_stock_vente_ins AFTER INSERT ON public.vente_lignes
  FOR EACH ROW EXECUTE FUNCTION public.maj_stock_vente();
DROP TRIGGER IF EXISTS trg_stock_vente_del ON public.vente_lignes;
CREATE TRIGGER trg_stock_vente_del AFTER DELETE ON public.vente_lignes
  FOR EACH ROW EXECUTE FUNCTION public.maj_stock_vente();

-- ── Sécurité (RLS) : module « boutique » ───────────────────────────────────
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['produits','produit_variantes','ventes','vente_lignes'] LOOP
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

NOTIFY pgrst, 'reload schema';
