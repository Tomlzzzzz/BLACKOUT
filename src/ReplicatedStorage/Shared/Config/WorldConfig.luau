--!strict
-- Zone, heure et meteo.
--
-- Le bandeau superieur droit de la maquette affiche « NORTH DISTRICT /
-- 17:42 / RAIN ». Trois lectures d'ambiance, mais elles font un vrai travail :
-- elles disent que la ville existe au-dela de ce que le joueur voit.
--
-- ATTENTION — limite assumee : il n'y a pas encore de carte. Les districts
-- sont donc declares ici avec un centre et un rayon, et un seul est actif
-- tant que Workspace.Map est vide. Quand la carte arrivera, il suffira de
-- poser les vrais centres : rien d'autre ne bougera.

local WorldConfig = {}

-- Districts. `center` et `radius` sont en studs, dans l'espace du monde.
-- Le joueur appartient au district le plus proche dont il est dans le rayon,
-- sinon au district par defaut.
WorldConfig.districts = {
	{ name = "NORTH DISTRICT", center = Vector3.new(0, 0, -200), radius = 260 },
	{ name = "PORT AUTHORITY", center = Vector3.new(220, 0, 0), radius = 240 },
	{ name = "OLD TOWN", center = Vector3.new(0, 0, 200), radius = 260 },
	{ name = "INDUSTRIAL BELT", center = Vector3.new(-220, 0, 0), radius = 240 },
}

WorldConfig.defaultDistrict = "NORTH DISTRICT"

-- Meteo. Purement cosmetique pour l'instant : elle change l'ambiance et le
-- bandeau, elle ne modifie aucune regle. Le jour ou elle influencera la
-- detection ennemie, c'est ici que le coefficient viendra.
--
-- `clock` est l'heure Roblox associee. La ville est en nuit permanente : on
-- reste entre 19h et 5h, jamais en plein jour.
WorldConfig.weathers = {
	{ name = "CLEAR", weight = 3, fog = 320, brightness = 0.9 },
	{ name = "RAIN", weight = 4, fog = 180, brightness = 0.6 },
	{ name = "FOG", weight = 3, fog = 90, brightness = 0.5 },
	{ name = "STORM", weight = 1, fog = 130, brightness = 0.35 },
}

-- Duree d'un regime meteo, en secondes. Une fenetre de contrat en voit deux
-- ou trois : assez pour que ca change, pas assez pour que ca clignote.
WorldConfig.weatherDuration = { min = 420, max = 700 }

-- Heure de depart et vitesse d'ecoulement. 0.4 heure Roblox par minute
-- reelle : la nuit avance sans jamais atteindre le jour sur une partie.
WorldConfig.startClock = 19.5
WorldConfig.clockPerMinute = 0.4
WorldConfig.clockRange = { min = 19, max = 29 } -- 29 = 5h du matin

-- Cadence de diffusion. Le district peut changer en marchant, la meteo est
-- rare : une seconde suffit largement.
WorldConfig.pushRate = 1

return WorldConfig
