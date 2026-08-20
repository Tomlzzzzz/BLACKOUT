--!strict
-- Francais.
--
-- La voix du commanditaire est la piece delicate. Elle ne se traduit pas mot
-- a mot : ce qui doit passer, c'est le registre — administratif, froid,
-- jamais inquiet pour le joueur, seulement pour la cargaison. « Asset lost,
-- cargo unrecovered » devient « Actif perdu. Cargaison non recouvree » et
-- garde son ordre, parce que c'est l'ordre qui dit le mepris.
--
-- Les libelles du HUD restent courts et en capitales : ils doivent tenir dans
-- la meme largeur de panneau que l'anglais, qui est souvent plus compact.
-- « OBJECTIVES » -> « OBJECTIFS » passe, « EXTRACTION AVAILABLE » ->
-- « EXTRACTION DISPONIBLE » aussi de justesse.

return {
	-- ------------------------------------------------------------ HUD ----
	["hud.threat"] = "MENACE",
	["hud.band.SAFE"] = "STABLE",
	["hud.band.ALERT"] = "ELEVEE",
	["hud.band.DANGER"] = "ELEVEE",
	["hud.band.SEVERE"] = "HAUTE",
	["hud.band.CRITICAL"] = "CRITIQUE",
	["hud.band.HUNT"] = "LA TRAQUE",

	["hud.hunt.title"] = "LA TRAQUE",
	["hud.hunt.sub"] = "WARDEN DEPLOYE   EXTRACTION IMMEDIATE",

	["hud.contract.current"] = "CONTRAT EN COURS",
	["hud.contract.complete"] = "CONTRAT REMPLI",
	["hud.contract.pressPrefix"] = "APPUYER",
	["hud.contract.pressSuffix"] = "POUR LA CARTE",

	["hud.extraction.available"] = "EXTRACTION DISPONIBLE",
	["hud.extraction.inProgress"] = "EXTRACTION EN COURS",
	["hud.extraction.goTo"] = "Rejoindre {zone}",
	["hud.extraction.secured"] = "CARGAISON SECURISEE   +{credits}",
	["hud.extraction.brokenZone"] = "EXTRACTION ROMPUE   ZONE QUITTEE",
	["hud.extraction.brokenDead"] = "EXTRACTION ROMPUE   SIGNAL PERDU",
	["hud.extraction.brokenClosed"] = "EXTRACTION ROMPUE   SORTIE FERMEE",
	["hud.extraction.brokenRun"] = "EXTRACTION ROMPUE   CONTRAT CLOS",

	["hud.vitals.health"] = "VIE",
	["hud.vitals.armor"] = "ARMURE",
	["hud.vitals.stamina"] = "SOUFFLE",
	["hud.vitals.battery"] = "BATTERIE",
	["hud.vitals.batteryOff"] = "LAMPE COUPEE",

	["hud.weapon.reloading"] = "RECHARGEMENT",
	["hud.weapon.empty"] = "VIDE",
	["hud.weapon.semi"] = "SEMI-AUTO",
	["hud.weapon.auto"] = "AUTOMATIQUE",

	["hud.interaction.mapUnavailable"] = "CARTE INDISPONIBLE",
	["hud.interaction.hold"] = "MAINTENIR",
	["prompt.search"] = "FOUILLER",
	["prompt.container"] = "CONTENEUR",
	["prompt.crate"] = "CAISSE",
	["prompt.locker"] = "CASIER",
	["prompt.safe"] = "COFFRE",
	["prompt.armory"] = "ARMURERIE",
	["prompt.medical"] = "ARMOIRE A PHARMACIE",

	["hud.feed.kill"] = "CIBLE ABATTUE",
	["hud.feed.headshot"] = "CIBLE ABATTUE   PRECISION",
	["hud.feed.objective"] = "OBJECTIF REMPLI",
	["hud.feed.contract"] = "CONTRAT REMPLI   +{reward}",
	["hud.feed.medical"] = "SOIN APPLIQUE",
	["hud.feed.armor"] = "PLAQUE POSEE",
	["hud.feed.battery"] = "BATTERIE REMPLACEE",

	["hud.boot.1"] = "TERMINAL DE TERRAIN MERIDIAN",
	["hud.boot.2"] = "LIAISON ETABLIE",
	["hud.boot.3"] = "ACTIF {tag} ACTIF",

	["hud.band.announce"] = "NIVEAU DE MENACE   {band}",

	-- ------------------------------------------------------ Contrats ----
	["contract.C001.title"] = "CONTRAT #001",
	["contract.C001.subtitle"] = "PREMIERE SORTIE",
	["contract.C001.obj1"] = "Trouver 3 batteries militaires",
	["contract.C001.obj2"] = "Atteindre le point d'extraction",
	["contract.C001.obj3"] = "Extraire et survivre",

	["contract.C002.title"] = "CONTRAT #002",
	["contract.C002.subtitle"] = "RECUPERATION",
	["contract.C002.obj1"] = "Recuperer 8 ferrailles",
	["contract.C002.obj2"] = "Recuperer 2 pieces d'armurerie",
	["contract.C002.obj3"] = "Extraire et survivre",

	["contract.C003.title"] = "CONTRAT #003",
	["contract.C003.subtitle"] = "RECUPERATION DE DONNEES",
	["contract.C003.obj1"] = "Securiser la boite noire",
	["contract.C003.obj2"] = "Atteindre le point d'extraction",
	["contract.C003.obj3"] = "Extraire et survivre",

	["contract.C004.title"] = "CONTRAT #004",
	["contract.C004.subtitle"] = "MEDECINE DE TERRAIN",
	["contract.C004.obj1"] = "Recuperer 2 trousses de soin",
	["contract.C004.obj2"] = "Recuperer 3 antidouleurs",
	["contract.C004.obj3"] = "Extraire et survivre",

	-- ------------------------------------------------ Commanditaire ----
	["handler.deploy.1"] = "Liaison etablie. Votre flux est enregistre en continu.",
	["handler.firstLoot.1"] = "Article inventorie. Propriete {company} jusqu'a extraction.",

	["handler.cargoLow.1"] = "Cargaison non assuree au-dela de ce seuil.",
	["handler.cargoMid.1"] = "Valeur transportee notable. Extraction recommandee.",
	["handler.cargoMid.2"] = "Nos actuaires suivent votre cargaison en direct.",
	["handler.cargoHigh.1"] = "Vous transportez plus que votre contrat ne couvre.",
	["handler.cargoHigh.2"] = "Perte estimee en cas d'incident : {cargo} credits.",

	["handler.bandALERT.1"] = "Releves acoustiques anormaux sur votre secteur.",
	["handler.bandDANGER.1"] = "Activite hostile confirmee. Poursuivez si le rendement le justifie.",
	["handler.bandSEVERE.1"] = "Nous perdons la lecture du secteur. Decision a votre charge.",
	["handler.bandCRITICAL.1"] = "Retrait conseille. Nous ne garantissons plus votre couverture.",

	["handler.hunt.1"] = "Interference totale sur le relais. Nous ne vous voyons plus.\nFin de la couverture contractuelle.",
	["handler.huntEnd.1"] = "Relais retabli. Votre flux reprend.",

	["handler.teammateDown.1"] = "Actif {tag} perdu. Cargaison non recouvree.",
	["handler.teammateExtracted.1"] = "{tag} extrait. Cargaison creditee au contrat.",

	["handler.lowHealth.1"] = "Biometrie degradee. Un remplacant est deja en liste d'attente.",

	["handler.idle.1"] = "Aucune acquisition depuis {seconds} secondes.",
	["handler.idle.2"] = "Rappel : le temps passe en zone vous est facture.",
	["handler.idle.3"] = "Votre contrat est indexe sur le rendement, pas sur la duree.",

	["handler.windowWarning.1"] = "Fenetre de contrat : {minutes} minutes restantes.",
	["handler.windowFinal.1"] = "{seconds} secondes. Le relais sera coupe, avec ou sans vous.",
	["handler.windowClosed.1"] = "Contrat clos. Actifs non extraits : pertes acceptables.",

	["handler.extractionOpen.1"] = "Sortie {zone} ouverte. Fenetre courte.",
	["handler.extractionDone.1"] = "Cargaison securisee. Solde credite : {credits}.",
	["handler.extractionLost.1"] = "Extraction interrompue. Le contrat reste ouvert.",

	["handler.contractAssigned.1"] = "Contrat {title} ouvert. Prime {reward} credits.",
	["handler.objectiveDone.1"] = "Objectif valide : {objective}.",
	["handler.contractDone.1"] = "Contrat rempli. Prime {reward} versee a l'extraction.",

	["handler.ambient.1"] = "Flux nominal. Archivage en cours.",
	["handler.ambient.2"] = "Position relevee. Horodatage transmis.",
	["handler.ambient.3"] = "Toute ressource non declaree constitue une fraude contractuelle.",
	["handler.ambient.4"] = "Releve biometrique transmis a l'assurance.",
	["handler.ambient.5"] = "Vous etes le seul cout variable de ce contrat.",


	-- Releves de capteurs. Le commanditaire ne devine rien : chacune de
	-- ces lignes repond a un fait mesure sur le serveur — un ennemi dans un
	-- rayon, un verrouillage, un depart de coup, un front meteo.
	["handler.contact.1"] = "Signature hostile — secteur {bearing}, {distance} m.",
	["handler.contact.2"] = "Mouvement releve a {distance} m, secteur {bearing}.",
	["handler.contactClose.1"] = "Contact a {distance} m, secteur {bearing}. Proche.",
	["handler.hunted.1"] = "Vous etes acquis. Quelque chose suit votre position.",
	["handler.hunted.2"] = "Contact verrouille sur vous, secteur {bearing}. Rompez le contact visuel.",
	["handler.gunfire.1"] = "Depart de coup releve — secteur {bearing}, {distance} m.",
	["handler.gunfire.2"] = "Tirs d'armes legeres a {distance} m. Pas les votres.",
	["handler.heavySignature.1"] = "Signature lourde dans le secteur. Nous n'avons pas de classification.",
	["handler.weather.1"] = "Front {weather} sur le secteur.",
	["handler.district.1"] = "Vous entrez dans {district}.",
	["handler.batteryLow.1"] = "Cellule a {percent} pour cent. La lumiere lachera avant le contrat.",


	-- Secteurs cardinaux, employes par les releves de contact. Ils doivent
	-- correspondre a ceux de la boussole, sinon le joueur cherche au mauvais
	-- endroit.
	["sector.0"] = "N",
	["sector.1"] = "NE",
	["sector.2"] = "E",
	["sector.3"] = "SE",
	["sector.4"] = "S",
	["sector.5"] = "SO",
	["sector.6"] = "O",
	["sector.7"] = "NO",


	-- Verdicts d'emplacement. Un refus DOIT se lire : une touche qui ne
	-- produit rien passe pour cassee, meme quand le refus est legitime.
	["slot.VIDE"] = "EMPLACEMENT VIDE",
	["slot.VIE_PLEINE"] = "VIE DEJA PLEINE",
	["slot.BATTERIE_PLEINE"] = "CELLULE DEJA PLEINE",
	["slot.NON_UTILISABLE"] = "NON UTILISABLE",
	["slot.MORT"] = "INDISPONIBLE",
	["slot.RETRAIT_REFUSE"] = "OBJET INDISPONIBLE",
	["slot.SERVICE_INDISPONIBLE"] = "SYSTEME HORS LIGNE",
	["hud.sprint"] = "COURSE",

	-- -------------------------------------------------------- Divers ----
	["item.pickup"] = "{name}",

	-- ------------------------------------------------- Vue spectateur ----
	--
	-- Le vocabulaire reste celui du commanditaire : on ne dit pas « vous etes
	-- mort », on dit que le flux est perdu et qu'on bascule sur un autre.
	["spectate.down"] = "FLUX PERDU   BASCULE SUR UN AUTRE ACTIF",
	["spectate.extracted"] = "ACTIF HORS ZONE   SURVEILLANCE DU CONTRAT EN COURS",
	["spectate.noSignal"] = "AUCUN SIGNAL",
	["spectate.hint"] = "A / D   CHANGER DE FLUX",

	-- ------------------------------------------- Rapport de fin de raid ----
	--
	-- Registre administratif. Le commanditaire ne felicite pas et ne console
	-- pas : il enregistre une operation comptable. « PERTE SECHE » est un
	-- terme de bilan, pas une insulte — c'est precisement ce qui le rend
	-- glacant.
	["debrief.header"] = "MERIDIAN / SUPERVISION",
	["debrief.subheader"] = "RAPPORT DE SORTIE",
	["debrief.dossier"] = "DOSSIER",
	["debrief.archived"] = "ARCHIVE AUTOMATIQUEMENT",
	-- Bandeau de classement, en tete de document. Le mot compte : le
	-- commanditaire ne dit pas « mort », il dit « perte d'actif ».
	["debrief.class.EXTRACTED"] = "CARGAISON RECEPTIONNEE",
	["debrief.class.KIA"] = "PERTE D'ACTIF",
	["debrief.class.EXPIRED"] = "CONTRAT NON EXECUTE",

	["debrief.outcome.EXTRACTED"] = "EXTRACTION CONFIRMEE",
	["debrief.outcome.KIA"] = "SIGNAL PERDU",
	["debrief.outcome.EXPIRED"] = "FENETRE CLOSE",

	["debrief.cause.EXTRACTED"] = "{zone}   ·   {duration} EN ZONE",
	["debrief.cause.KIA"] = "ACTIF NEUTRALISE APRES {duration}",
	["debrief.cause.EXPIRED"] = "ACTIF ABANDONNE SUR ZONE APRES {duration}",

	["debrief.manifest.recovered"] = "MANIFESTE RAPATRIE",
	["debrief.manifest.lost"] = "CARGAISON PERDUE",
	["debrief.manifest.empty"] = "AUCUNE CARGAISON",
	["debrief.manifest.overflow"] = "ET {count} AUTRES",
	["debrief.manifest.total"] = "TOTAL",
	["debrief.manifest.leftBehind"] = "{count} PILE(S) LAISSEE(S) — COFFRE PLEIN",

	["debrief.log.title"] = "RELEVE DE MISSION",
	["debrief.log.kills"] = "ELIMINATIONS",
	["debrief.log.damage"] = "DEGATS SUBIS",
	["debrief.log.peak"] = "PIC DE MENACE",
	["debrief.log.objectives"] = "OBJECTIFS",
	["debrief.log.duration"] = "DUREE",

	["debrief.balance.cargo"] = "CARGAISON",
	["debrief.balance.bonus"] = "PRIME DE SORTIE",
	["debrief.balance.paid"] = "VERSE",
	["debrief.balance.nothing"] = "AUCUN VERSEMENT",
	["debrief.balance.account"] = "SOLDE",
	["debrief.balance.xp"] = "EXPERIENCE",
	["debrief.balance.level"] = "NIVEAU {level}",
	["debrief.balance.levelUp"] = "PROMOTION   NIVEAU {level}",

	["debrief.rating"] = "EVALUATION",
	["debrief.rating.EXEMPLARY"] = "EXEMPLAIRE",
	["debrief.rating.SATISFACTORY"] = "SATISFAISANT",
	["debrief.rating.MARGINAL"] = "MARGINAL",
	["debrief.rating.DEFICIENT"] = "DEFICITAIRE",
	["debrief.rating.WRITE_OFF"] = "PERTE SECHE",

	["debrief.contract.complete"] = "CONTRAT REMPLI",
	["debrief.contract.failed"] = "CONTRAT NON REMPLI",

	["debrief.closing.EXTRACTED"] = "Cargaison receptionnee. Restez disponible.",
	["debrief.closing.KIA"] = "Actif perdu. Cargaison non recouvree.",
	["debrief.closing.EXPIRED"] = "Fenetre close. Aucun versement au titre de cette sortie.",

	["debrief.dismiss"] = "ACQUITTER",

	-- Noms d'objets. ItemDatabase garde les siens pour les journaux
	-- serveur ; c'est cette table qui s'affiche au joueur.
	["item.military_battery"] = "Batterie militaire",
	["item.scrap_metal"] = "Ferraille",
	["item.bandage"] = "Bandage",
	["item.painkillers"] = "Antidouleurs",
	["item.gold_chain"] = "Chaine en or",
	["item.graphics_card"] = "Carte graphique",
	["item.keycard_blue"] = "Carte d'acces bleue",
	["item.black_box"] = "Boite noire",
	["item.medkit"] = "Trousse de soin",
	["item.ammo_762"] = "Munitions 7.62",
	["item.armor_plate"] = "Plaque balistique",
	["item.weapon_parts"] = "Pieces d'armurerie",
	["item.pistol_mk1"] = "Pistolet MK1",
	["item.rifle_ak"] = "Fusil 7.62",
	["item.ammo_9mm"] = "Munitions 9mm",
	["item.prototype_core"] = "Noyau prototype",


	-- Lieux. Traduits comme des noms communs plutot que laisses en nom
	-- propre : « QUARTIER NORD » situe, « NORTH DISTRICT » ne dit rien a un
	-- joueur francophone.
	["world.district.NORTH DISTRICT"] = "QUARTIER NORD",
	["world.district.PORT AUTHORITY"] = "AUTORITE PORTUAIRE",
	["world.district.OLD TOWN"] = "VIEILLE VILLE",
	["world.district.INDUSTRIAL BELT"] = "CEINTURE INDUSTRIELLE",
	["zone.NORTH GATE"] = "PORTE NORD",
	["zone.EAST DOCKS"] = "DOCKS EST",
	["zone.SOUTH YARD"] = "DEPOT SUD",
	["zone.WEST TUNNEL"] = "TUNNEL OUEST",
	["world.weather.CLEAR"] = "DEGAGE",
	["world.weather.RAIN"] = "PLUIE",
	["world.weather.FOG"] = "BROUILLARD",
	["world.weather.STORM"] = "ORAGE",
}
