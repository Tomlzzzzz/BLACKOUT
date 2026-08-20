--!strict
-- Rapport de fin de raid.
--
-- Le debrief n'est pas un tableau de scores : c'est le RAPPORT QUE LE
-- COMMANDITAIRE ECRIT SUR L'ACTIF. C'est la derniere chose que le joueur
-- lit avant de repartir, donc le meilleur endroit pour dire qui l'emploie
-- et sur quels criteres il est juge.
--
-- La note qui suit est le coeur de cette idee. Elle ne recompense ni la
-- survie ni le courage : elle chiffre la cargaison rapatriee. Un actif qui
-- rentre les mains vides est « DEFICITAIRE » meme s'il a survecu a la
-- traque, et un actif mort est une PERTE SECHE quoi qu'il ait fait avant.
-- C'est volontairement injuste — c'est ce qui fait qu'on travaille pour
-- quelqu'un et non pour soi.

local DebriefConfig = {}

-- ------------------------------------------------------------- Notation --
--
-- Paliers sur la valeur REELLEMENT rapatriee, en credits, du plus haut au
-- plus bas. Le premier palier atteint gagne : l'ordre compte.
DebriefConfig.rating = {
	{ key = "EXEMPLARY", minValue = 2500 },
	{ key = "SATISFACTORY", minValue = 800 },
	{ key = "MARGINAL", minValue = 150 },
	{ key = "DEFICIENT", minValue = 0 },
}

-- Note d'un actif qui n'est pas rentre. Elle ne se calcule pas : elle
-- remplace le bareme.
DebriefConfig.lostRating = "WRITE_OFF"

-- Un contrat rempli fait monter d'un cran. Le commanditaire ne paie pas la
-- bonne volonte, mais il tient ses propres commandes pour du rendement.
DebriefConfig.contractPromotion = 1

-- ------------------------------------------------------------ Manifeste --
--
-- Nombre de lignes detaillees. Au-dela, le reste est agrege en une ligne
-- « et N autres » : un manifeste de trente lignes ne se lit pas, et l'ecran
-- doit rester une page.
DebriefConfig.manifestLimit = 6

-- ------------------------------------------------------------ Reference --
--
-- Numero de dossier. Sans interet mecanique, essentiel au ton : il dit que
-- la sortie a ete archivee quelque part, dans un classeur qui n'appartient
-- pas au joueur.
DebriefConfig.referencePrefix = "MRD"

return DebriefConfig
