-- ════════════════════════════════════════════════════════════════
-- 12 — Mise en forme des noms des clients déjà enregistrés
--      Prénom : « Mohamed Taha » (majuscule au début de chaque mot)
--      Nom    : « ELAZIZI »      (tout en majuscules)
-- Les nouvelles saisies sont mises en forme par l'application.
-- À exécuter une fois dans Supabase : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

UPDATE public.clients
SET prenom     = initcap(lower(btrim(regexp_replace(prenom, '\s+', ' ', 'g')))),
    nom        = upper(btrim(regexp_replace(nom, '\s+', ' ', 'g'))),
    updated_at = NOW()
WHERE prenom IS DISTINCT FROM initcap(lower(btrim(regexp_replace(prenom, '\s+', ' ', 'g'))))
   OR nom    IS DISTINCT FROM upper(btrim(regexp_replace(nom, '\s+', ' ', 'g')));

-- Résultat
SELECT prenom, nom FROM public.clients ORDER BY nom, prenom;
