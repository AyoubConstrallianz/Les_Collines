-- ════════════════════════════════════════════════════════════════
-- 05 — Numérotation des reçus de paiement : R-AAAA-0001, R-AAAA-0002…
-- La numérotation repart à 1 chaque année (année de la date de paiement).
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

ALTER TABLE public.paiements ADD COLUMN IF NOT EXISTS numero_recu TEXT UNIQUE;

-- Dernier numéro attribué par année
CREATE TABLE IF NOT EXISTS public.compteurs_recus (
  annee    INT PRIMARY KEY,
  dernier  INT NOT NULL DEFAULT 0
);
-- Aucun accès direct depuis l'application : seul le trigger (SECURITY DEFINER) l'utilise
ALTER TABLE public.compteurs_recus ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.attribuer_numero_recu()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_annee INT := EXTRACT(YEAR FROM COALESCE(NEW.date_paiement, CURRENT_DATE))::INT;
  v_num   INT;
BEGIN
  IF NEW.numero_recu IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- L'UPSERT verrouille la ligne de l'année : deux paiements simultanés ne peuvent pas avoir le même numéro
  INSERT INTO public.compteurs_recus (annee, dernier) VALUES (v_annee, 1)
    ON CONFLICT (annee) DO UPDATE SET dernier = public.compteurs_recus.dernier + 1
    RETURNING dernier INTO v_num;
  NEW.numero_recu := 'R-' || v_annee || '-' || LPAD(v_num::TEXT, 4, '0');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_numero_recu ON public.paiements;
CREATE TRIGGER trg_numero_recu
  BEFORE INSERT ON public.paiements
  FOR EACH ROW EXECUTE FUNCTION public.attribuer_numero_recu();

-- Numéroter les paiements déjà enregistrés, dans l'ordre chronologique
WITH a_numeroter AS (
  SELECT id,
         EXTRACT(YEAR FROM date_paiement)::INT AS annee,
         ROW_NUMBER() OVER (PARTITION BY EXTRACT(YEAR FROM date_paiement)
                            ORDER BY date_paiement, created_at, id) AS rang
  FROM public.paiements
  WHERE numero_recu IS NULL AND date_paiement IS NOT NULL
)
UPDATE public.paiements p
SET numero_recu = 'R-' || a.annee || '-' || LPAD((a.rang + COALESCE(c.dernier, 0))::TEXT, 4, '0')
FROM a_numeroter a
LEFT JOIN public.compteurs_recus c ON c.annee = a.annee
WHERE p.id = a.id;

-- Mettre les compteurs à jour avec les numéros attribués
INSERT INTO public.compteurs_recus (annee, dernier)
SELECT CAST(SPLIT_PART(numero_recu, '-', 2) AS INT), MAX(CAST(SPLIT_PART(numero_recu, '-', 3) AS INT))
FROM public.paiements
WHERE numero_recu LIKE 'R-%'
GROUP BY 1
ON CONFLICT (annee) DO UPDATE SET dernier = GREATEST(public.compteurs_recus.dernier, EXCLUDED.dernier);
