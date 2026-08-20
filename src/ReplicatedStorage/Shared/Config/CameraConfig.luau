--!strict
-- Camera premiere personne.
--
-- Le GDD d'origine annoncait une camera a la troisieme personne ; la
-- decision a ete revue en cours de production au profit de la premiere.
-- Pour un jeu d'horreur c'est le bon choix : le champ de vision devient une
-- ressource, et ce que le joueur ne voit pas derriere lui compte enfin.
--
-- Consequence a garder en tete : en premiere personne, la camera est le seul
-- endroit ou faire sentir l'etat du corps. Une partie de l'escalade de
-- menace vit donc ici et non dans le HUD.

local CameraConfig = {}

-- Champ de vision. 70 est la valeur Roblox par defaut ; on s'en ecarte peu
-- au repos, les ecarts servent a signaler un etat.
CameraConfig.baseFov = 70
CameraConfig.sprintFov = 78

-- Resserrement a mesure que la menace monte : la vision tunnel de la peur.
-- Ajoute au champ de base, donc negatif.
CameraConfig.threatFov = {
	SAFE = 0,
	ALERT = 0,
	DANGER = -1.5,
	SEVERE = -3,
	CRITICAL = -4.5,
	HUNT = -7,
}

-- Vitesse d'interpolation du champ de vision. Assez lent pour ne jamais
-- etre percu comme un a-coup.
CameraConfig.fovLerp = 4

-- Respiration. Oscillation lente et permanente qui empeche l'image d'etre
-- parfaitement fixe ; c'est ce qui distingue une camera portee d'un support.
-- `amplitude` est en degres, `speed` en cycles par seconde.
CameraConfig.breath = {
	SAFE = { amplitude = 0.08, speed = 0.6 },
	ALERT = { amplitude = 0.14, speed = 0.9 },
	DANGER = { amplitude = 0.22, speed = 1.3 },
	SEVERE = { amplitude = 0.38, speed = 1.9 },
	CRITICAL = { amplitude = 0.55, speed = 2.6 },
	HUNT = { amplitude = 0.9, speed = 3.4 },
}

-- Tremblement aleatoire, en degres. Distinct de la respiration : la
-- respiration est reguliere et lisible, le tremblement est du bruit. Il ne
-- demarre qu'a SEVERE, sinon il ne reste rien pour dire HUNT.
CameraConfig.shake = {
	SAFE = 0,
	ALERT = 0,
	DANGER = 0,
	SEVERE = 0.10,
	CRITICAL = 0.22,
	HUNT = 0.45,
}

-- Secousse encaissee a la prise de degats. `perHundred` est l'amplitude en
-- degres pour 100 points perdus d'un coup ; `decay` la vitesse de retour.
CameraConfig.damageKick = {
	perHundred = 6,
	maximum = 4,
	decay = 7,
}

-- Balancement de marche.
--
-- LE MOUVEMENT SUIT LES PAS. C'est la seule regle qui compte ici.
--
-- Deux versions ont echoue avant celle-ci. La premiere ne produisait QUE du
-- roulis : marcher faisait pencher la tete de gauche a droite comme un
-- metronome, un mouvement qu'aucun corps ne fait en avancant. La seconde a
-- ajoute le tangage mais l'a cadence a DEUX FOIS la phase, soit pres de
-- quatre oscillations verticales par seconde — injouable a l'ecran, et sans
-- rapport avec la marche de qui que ce soit.
--
-- La cadence s'exprime donc en PAS PAR SECONDE, et l'anatomie decoule :
--
--   `rise`  un mouvement vertical PAR PAS
--   `sway`  un roulis par FOULEE, soit un pas sur deux
--
-- Un humain marche a peu pres a 1.75 pas/seconde et court a 2.5. Ce sont ces
-- valeurs-la, pas un multiple arbitraire de l'horloge — et c'est aussi la
-- phase sur laquelle brancher les futurs bruits de pas.
CameraConfig.bob = {
	rise = 0.9,
	sway = 0.35,

	-- Cadence, en pas par seconde.
	walkCadence = 1.75,
	sprintCadence = 2.5,

	-- Vitesse de deplacement au-dela de laquelle le balancement est plein.
	-- Calee sur la marche : on veut le balancement complet en marchant, pas
	-- seulement en courant.
	referenceSpeed = 12,

	-- Amplitude en course. La cadence monte deja ; ce facteur ajoute
	-- l'ampleur, sinon courir ressemble a une marche en avance rapide.
	sprintAmplitude = 1.4,
}

-- ------------------------------------------------ Optique embarquee -----
--
-- La cellule alimente la camera que le joueur regarde. Sous ce seuil de
-- charge, l'image commence a se brouiller ; a zero le flou plafonne.
--
-- Volontairement FAIBLE : le flou doit inquieter, pas rendre le jeu
-- injouable. A 8, on distingue encore une silhouette a vingt metres.
CameraConfig.opticsBlurBelow = 0.2
CameraConfig.opticsBlurMax = 8

return CameraConfig
