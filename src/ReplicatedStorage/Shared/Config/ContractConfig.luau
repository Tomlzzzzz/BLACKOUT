--!strict
-- Contrats a objectifs.
--
-- La maquette montre un contrat en trois lignes :
--
--   CONTRACT #001 / FIRST RUN
--     ◇ Find 3 Military Batteries      2/3
--     ◇ Reach the Extraction Point
--     ◇ Extract and Survive
--
-- C'est la structure retenue : un contrat porte une suite d'objectifs de
-- types differents, pas une simple quantite d'items. La directive du
-- commanditaire (HandlerConfig) devient le PREMIER objectif de ce contrat au
-- lieu d'un systeme parallele — deux listes d'objectifs a l'ecran seraient
-- deux fois la meme idee.
--
-- Types d'objectif reconnus par MissionService :
--   collect   ramasser `quantity` fois `item`
--   reach     entrer dans une zone d'extraction ouverte
--   extract   terminer une extraction

local ContractConfig = {}

-- Libelles affiches. En anglais : c'est la langue de la maquette et de
-- toutes les chaines du HUD v2. Les commentaires restent en francais.
-- Les libelles ne sont PAS ici : ils vivent dans Shared/Locale, sous
-- « contract.<id>.title », « .subtitle » et « .obj1 », « .obj2 »...
-- Ce fichier ne decrit que la MECANIQUE d'un contrat.
ContractConfig.contracts = {
	{
		id = "C001",
		objectives = {
			{ kind = "collect", item = "military_battery", quantity = 3 },
			{ kind = "reach" },
			{ kind = "extract" },
		},
		reward = 1500,
	},
	{
		id = "C002",
		objectives = {
			{ kind = "collect", item = "scrap_metal", quantity = 8 },
			{ kind = "collect", item = "weapon_parts", quantity = 2 },
			{ kind = "extract" },
		},
		reward = 1100,
	},
	{
		id = "C003",
		objectives = {
			{ kind = "collect", item = "black_box", quantity = 1 },
			{ kind = "reach" },
			{ kind = "extract" },
		},
		reward = 2600,
	},
	{
		id = "C004",
		objectives = {
			{ kind = "collect", item = "medkit", quantity = 2 },
			{ kind = "collect", item = "painkillers", quantity = 3 },
			{ kind = "extract" },
		},
		reward = 1300,
	},
}

-- Distance en studs sous laquelle un objectif `reach` est valide. Plus large
-- que le rayon d'extraction : atteindre la sortie et extraire sont deux
-- objectifs distincts, le premier ne doit pas exiger le second.
ContractConfig.reachRadius = 40

return ContractConfig
