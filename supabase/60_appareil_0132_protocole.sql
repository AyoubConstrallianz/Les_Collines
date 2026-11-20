-- ════════════════════════════════════════════════════════════════
-- 60 — Nouvel appareil de la Porte 2 (NQN5235200132) : protocole « acc »
--   L'appareil a été paramétré avant d'être inscrit (script 59) : sa demande
--   d'enregistrement a été refusée et son protocole n'a pas été noté.
--   Sans le protocole « acc », le site n'envoie pas le droit d'ouvrir aux
--   heures des séances (refus « code 23 »).
--   Ce script note le protocole (même modèle que l'appareil de la Porte 1)
--   et renvoie toutes les fiches, droits et visages à l'appareil.
-- À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

UPDATE public.acces_appareils
SET protocole = 'acc', synchro_demandee = true, derniere_bascule = NULL
WHERE sn = 'NQN5235200132';

-- Tout renvoyer : commandes en attente annulées, fiches renvoyées au prochain passage de l'appareil
DELETE FROM public.acces_commandes
WHERE sn = 'NQN5235200132' AND termine_le IS NULL;

DELETE FROM public.acces_utilisateurs
WHERE sn = 'NQN5235200132' AND pri = 0;

NOTIFY pgrst, 'reload schema';
