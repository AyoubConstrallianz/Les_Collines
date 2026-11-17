-- ════════════════════════════════════════════════════════════════
-- 51 — Écran client : passages aux portes avec le nom de la personne
--   L'écran client lisait les noms dans « clients » et « employes » : un compte
--   qui n'a que le droit « Accès & Portes » voyait les passages sans le nom.
--   Cette fonction renvoie, pour chaque passage, seulement ce que l'écran affiche :
--   prénom, nom, photo, N° d'adhérent, disciplines, et la date + le type des paiements
--   (pour « Abonnement valable jusqu'au… » et l'assurance). Ni téléphone, ni CIN,
--   ni email, ni notes, ni montants.
--   Droit nécessaire : « Accès & Portes » en lecture.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ecran_passages(p_apres BIGINT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_perm('acces', 'lire') THEN
    RAISE EXCEPTION 'Droit « Accès & Portes » (lecture) nécessaire.';
  END IF;
  IF p_apres IS NULL THEN
    RETURN jsonb_build_object('dernier', (SELECT coalesce(max(id), 0) FROM public.acces_entrees), 'passages', '[]'::jsonb);
  END IF;
  RETURN jsonb_build_object('dernier', NULL, 'passages', coalesce((
    SELECT jsonb_agg(q.x ORDER BY q.id)
    FROM (
      SELECT e.id, jsonb_build_object(
        'id', e.id, 'porte', e.porte, 'pin', e.pin, 'date_heure', e.date_heure, 'statut', e.statut,
        'clients', CASE WHEN c.id IS NULL THEN NULL ELSE jsonb_build_object(
          'id', c.id, 'prenom', c.prenom, 'nom', c.nom, 'photo_url', c.photo_url,
          'numero_adherent', c.numero_adherent, 'sports', c.sports, 'sport', c.sport) END,
        'employes', CASE WHEN m.id IS NULL THEN NULL ELSE jsonb_build_object('prenom', m.prenom, 'nom', m.nom) END,
        'paiements', CASE WHEN c.id IS NULL THEN NULL ELSE coalesce((
          SELECT jsonb_agg(jsonb_build_object('date_paiement', p.date_paiement, 'type', p.type))
          FROM public.paiements p WHERE p.client_id = c.id), '[]'::jsonb) END) AS x
      FROM public.acces_entrees e
      LEFT JOIN public.clients c ON c.id = e.client_id
      LEFT JOIN public.employes m ON m.id = e.employe_id
      WHERE e.id > p_apres
      ORDER BY e.id
      LIMIT 30) q), '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.ecran_passages(BIGINT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ecran_passages(BIGINT) TO authenticated;

NOTIFY pgrst, 'reload schema';
