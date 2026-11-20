-- ════════════════════════════════════════════════════════════════
-- 59 — Remplacement de l'appareil de la Porte 2
--   Ancien : NQN5235200124 (Porte 2) → désactivé (historique conservé)
--   Nouveau : NQN5235200132 (SpeedFace-V3L Lite) → Porte 2
--   À sa première connexion, le site lui envoie tous les adhérents et le
--   personnel autorisés sur la Porte 2, avec les badges et visages connus.
-- Prérequis : scripts 43 à 58. À exécuter une fois : SQL Editor → New query → Run
-- ════════════════════════════════════════════════════════════════

-- Nouvel appareil, sur la porte de l'ancien (Porte 2 par défaut)
INSERT INTO public.acces_appareils (sn, nom, porte, actif, synchro_demandee)
VALUES ('NQN5235200132', 'Appareil …0132',
        COALESCE((SELECT porte FROM public.acces_appareils WHERE sn = 'NQN5235200124'), 2),
        true, true)
ON CONFLICT (sn) DO UPDATE
  SET porte = EXCLUDED.porte, actif = true, synchro_demandee = true;

-- Ancien appareil : désactivé et retiré de la porte (ses passages restent dans l'historique)
UPDATE public.acces_appareils
SET actif = false, porte = NULL
WHERE sn = 'NQN5235200124';

-- Commandes encore en attente pour l'ancien appareil : inutiles
DELETE FROM public.acces_commandes
WHERE sn = 'NQN5235200124' AND termine_le IS NULL;

NOTIFY pgrst, 'reload schema';
