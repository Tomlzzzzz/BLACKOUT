--!strict
-- Cycle de partie.
--
-- La duree de raid vivait dans Constants, ou elle ne servait a rien : elle
-- s'ecoulait sans que rien ne se produise. Maintenant qu'elle ferme
-- reellement le contrat, c'est une valeur de tuning — elle a sa place ici.

local MatchConfig = {}

-- Fenetre de contrat. Le GDD vise 15 a 25 minutes par partie ; on ouvre au
-- haut de la fourchette, la pression venant surtout de la menace.
MatchConfig.windowDuration = 25 * 60

-- Temps entre la fermeture du contrat et le redeploiement. Assez long pour
-- lire le verdict, assez court pour ne pas quitter le serveur.
MatchConfig.debriefTime = 12

-- Resynchronisation de l'horloge chez les clients.
--
-- Le client decompte tout seul entre deux envois. Diffuser chaque seconde
-- couterait 25 messages par minute et par joueur pour corriger une derive
-- qui n'existe pas ; on renvoie la reference de temps en temps, et a chaque
-- changement d'etat.
MatchConfig.syncInterval = 15

-- Redeploiement automatique. A passer a false pour geler le serveur en raid
-- pendant une session de debug : la fenetre s'ecoule mais rien ne se ferme.
MatchConfig.autoCycle = true

return MatchConfig
