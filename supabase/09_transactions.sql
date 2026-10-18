-- ════════════════════════════════════════════════════════════════
-- 09 — Transactions : plusieurs mouvements encaissés ensemble
--      (ex. mensualité + frais d'inscription + assurance)
--  • transaction_id relie les lignes d'un même encaissement
--  • un seul numéro de reçu par transaction
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.paiements ADD COLUMN IF NOT EXISTS transaction_id UUID;
CREATE INDEX IF NOT EXISTS idx_paie_transaction ON public.paiements(transaction_id);

-- Les lignes d'une même transaction partagent le numéro de reçu
ALTER TABLE public.paiements DROP CONSTRAINT IF EXISTS paiements_numero_recu_key;

CREATE OR REPLACE FUNCTION public.attribuer_numero_recu()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_annee INT := EXTRACT(YEAR FROM COALESCE(NEW.date_paiement, CURRENT_DATE))::INT;
  v_num   INT;
  v_exist TEXT;
BEGIN
  IF NEW.numero_recu IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- Ligne d'une transaction déjà numérotée (lignes précédentes du même INSERT) : même numéro
  IF NEW.transaction_id IS NOT NULL THEN
    SELECT numero_recu INTO v_exist FROM public.paiements
    WHERE transaction_id = NEW.transaction_id AND numero_recu IS NOT NULL LIMIT 1;
    IF v_exist IS NOT NULL THEN
      NEW.numero_recu := v_exist;
      RETURN NEW;
    END IF;
  END IF;
  INSERT INTO public.compteurs_recus (annee, dernier) VALUES (v_annee, 1)
    ON CONFLICT (annee) DO UPDATE SET dernier = public.compteurs_recus.dernier + 1
    RETURNING dernier INTO v_num;
  NEW.numero_recu := 'R-' || v_annee || '-' || LPAD(v_num::TEXT, 4, '0');
  RETURN NEW;
END;
$$;
