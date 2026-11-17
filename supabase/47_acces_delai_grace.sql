-- ════════════════════════════════════════════════════════════════
-- 47 — Contrôle d'accès : 5 jours de grâce après la fin de l'abonnement
--   Un client garde l'accès aux portes jusqu'à 5 jours après la fin de son abonnement
--   (même s'il est passé « Inactif »), puis il est retiré des appareils automatiquement.
--   Un client « Suspendu » n'a jamais accès.
-- Prérequis : script 43. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.acces_autorises(p_porte INT)
RETURNS TABLE (pin TEXT, nom TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- Clients : abonnement en cours (ou terminé depuis 5 jours au plus) + une discipline sur cette porte
  SELECT c.numero_adherent::text, public.acces_nom(c.prenom, c.nom)
  FROM public.clients c
  WHERE c.numero_adherent IS NOT NULL
    -- « Inactif » est mis automatiquement à la fin de l'abonnement : il garde l'accès pendant le délai de grâce
    AND coalesce(c.statut, 'Actif') <> 'Suspendu'
    AND EXISTS (
      SELECT 1 FROM public.paiements p
      WHERE p.client_id = c.id
        AND p.date_paiement::date <= (now() AT TIME ZONE 'Africa/Casablanca')::date
        AND public.acces_fin_couverture(p.date_paiement::date, p.type) + 5 >= (now() AT TIME ZONE 'Africa/Casablanca')::date)
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

REVOKE ALL ON FUNCTION public.acces_autorises(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.acces_autorises(INT) TO service_role;

-- Les appareils recalculent leur liste au prochain passage
UPDATE public.acces_appareils SET synchro_demandee = true WHERE NOT synchro_demandee;

NOTIFY pgrst, 'reload schema';
