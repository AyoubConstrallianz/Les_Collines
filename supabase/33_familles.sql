-- ════════════════════════════════════════════════════════════════
-- 33 — Familles (pack famille)
--   • familles : une famille regroupe plusieurs clients (chacun garde sa fiche et ses disciplines)
--   • clients.famille_id     : famille du client
--   • clients.famille_actif  : abonnement du membre en cours (false = arrêté)
--   • Tarif famille appliqué tant qu'il reste au moins 2 membres actifs dans la famille
--   • Comprend aussi les colonnes du script 32 (tarifs pack famille) si elles manquent
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.familles (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom         TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by  UUID DEFAULT auth.uid()
);

ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS famille_id    UUID REFERENCES public.familles(id) ON DELETE SET NULL;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS famille_actif BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE public.clients ADD COLUMN IF NOT EXISTS pack_famille  BOOLEAN NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS clients_famille_idx ON public.clients (famille_id);

-- Tarifs pack famille par sport (script 32)
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS famille_mensuel     NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS famille_trimestriel NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS famille_semestriel  NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE public.sports ADD COLUMN IF NOT EXISTS famille_annuel      NUMERIC(10,2) NOT NULL DEFAULT 0;

-- ── Sécurité (RLS) : mêmes droits que les clients ──────────────────────────
ALTER TABLE public.familles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "familles_select" ON public.familles;
DROP POLICY IF EXISTS "familles_insert" ON public.familles;
DROP POLICY IF EXISTS "familles_update" ON public.familles;
DROP POLICY IF EXISTS "familles_delete" ON public.familles;
CREATE POLICY "familles_select" ON public.familles FOR SELECT USING (public.has_perm('clients','lire'));
CREATE POLICY "familles_insert" ON public.familles FOR INSERT WITH CHECK (public.has_perm('clients','ecrire'));
CREATE POLICY "familles_update" ON public.familles FOR UPDATE USING (public.has_perm('clients','ecrire'));
CREATE POLICY "familles_delete" ON public.familles FOR DELETE USING (public.has_perm('clients','supprimer'));

-- ── Validation des gérants (script 25) : suivre aussi les familles ─────────
DO $$
BEGIN
  IF to_regproc('public.suivre_modif_gerant') IS NOT NULL AND to_regclass('public.modifications') IS NOT NULL THEN
    EXECUTE 'DROP TRIGGER IF EXISTS trg_suivi_gerant ON public.familles';
    EXECUTE 'CREATE TRIGGER trg_suivi_gerant AFTER INSERT OR UPDATE OR DELETE ON public.familles FOR EACH ROW EXECUTE FUNCTION public.suivre_modif_gerant()';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
