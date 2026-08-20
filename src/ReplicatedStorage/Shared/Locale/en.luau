--!strict
-- Anglais. LANGUE DE REFERENCE.
--
-- Toute cle doit exister ici : les autres langues retombent dessus quand il
-- leur manque quelque chose. LocaleTests echoue si une cle presente ailleurs
-- manque ici.
--
-- Convention de nommage : `zone.element.variante`. Les variantes numerotees
-- (`.1`, `.2`) sont tirees au hasard sans remise par le commanditaire.

return {
	-- ------------------------------------------------------------ HUD ----
	["hud.threat"] = "THREAT",
	["hud.band.SAFE"] = "SAFE",
	["hud.band.ALERT"] = "ELEVATED",
	["hud.band.DANGER"] = "ELEVATED",
	["hud.band.SEVERE"] = "HIGH",
	["hud.band.CRITICAL"] = "CRITICAL",
	["hud.band.HUNT"] = "THE HUNT",

	["hud.hunt.title"] = "THE HUNT",
	["hud.hunt.sub"] = "WARDEN DEPLOYED   EXTRACT IMMEDIATELY",

	["hud.contract.current"] = "CURRENT CONTRACT",
	["hud.contract.complete"] = "CONTRACT COMPLETE",
	["hud.contract.pressPrefix"] = "PRESS",
	["hud.contract.pressSuffix"] = "TO VIEW MAP",

	["hud.extraction.available"] = "EXTRACTION AVAILABLE",
	["hud.extraction.inProgress"] = "EXTRACTION IN PROGRESS",
	["hud.extraction.goTo"] = "Go to {zone}",
	["hud.extraction.secured"] = "CARGO SECURED   +{credits}",
	["hud.extraction.brokenZone"] = "EXTRACTION ABORTED   LEFT ZONE",
	["hud.extraction.brokenDead"] = "EXTRACTION ABORTED   SIGNAL LOST",
	["hud.extraction.brokenClosed"] = "EXTRACTION ABORTED   EXIT CLOSED",
	["hud.extraction.brokenRun"] = "EXTRACTION ABORTED   CONTRACT CLOSED",

	["hud.vitals.health"] = "HEALTH",
	["hud.vitals.armor"] = "ARMOR",
	["hud.vitals.stamina"] = "STAMINA",
	["hud.vitals.battery"] = "BATTERY",
	["hud.vitals.batteryOff"] = "BATTERY OFF",

	["hud.weapon.reloading"] = "RELOADING",
	["hud.weapon.empty"] = "EMPTY",
	["hud.weapon.semi"] = "SEMI-AUTO",
	["hud.weapon.auto"] = "FULL-AUTO",

	["hud.interaction.mapUnavailable"] = "MAP UNAVAILABLE",
	["hud.interaction.hold"] = "HOLD",
	["prompt.search"] = "SEARCH",
	["prompt.container"] = "CONTAINER",
	["prompt.crate"] = "SUPPLY CRATE",
	["prompt.locker"] = "LOCKER",
	["prompt.safe"] = "SAFE",
	["prompt.armory"] = "ARMORY",
	["prompt.medical"] = "MEDICAL CABINET",

	["hud.feed.kill"] = "TARGET DOWN",
	["hud.feed.headshot"] = "TARGET DOWN   PRECISION",
	["hud.feed.objective"] = "OBJECTIVE COMPLETE",
	["hud.feed.contract"] = "CONTRACT COMPLETE   +{reward}",
	["hud.feed.medical"] = "MEDICAL APPLIED",
	["hud.feed.armor"] = "ARMOR PLATE APPLIED",
	["hud.feed.battery"] = "BATTERY REPLACED",

	["hud.boot.1"] = "MERIDIAN FIELD TERMINAL",
	["hud.boot.2"] = "UPLINK ESTABLISHED",
	["hud.boot.3"] = "ASSET {tag} ACTIVE",

	["hud.band.announce"] = "THREAT LEVEL   {band}",

	-- ------------------------------------------------------ Contrats ----
	["contract.C001.title"] = "CONTRACT #001",
	["contract.C001.subtitle"] = "FIRST RUN",
	["contract.C001.obj1"] = "Find 3 Military Batteries",
	["contract.C001.obj2"] = "Reach the Extraction Point",
	["contract.C001.obj3"] = "Extract and Survive",

	["contract.C002.title"] = "CONTRACT #002",
	["contract.C002.subtitle"] = "SALVAGE RUN",
	["contract.C002.obj1"] = "Recover 8 Scrap Metal",
	["contract.C002.obj2"] = "Recover 2 Weapon Parts",
	["contract.C002.obj3"] = "Extract and Survive",

	["contract.C003.title"] = "CONTRACT #003",
	["contract.C003.subtitle"] = "DATA RECOVERY",
	["contract.C003.obj1"] = "Secure the Black Box",
	["contract.C003.obj2"] = "Reach the Extraction Point",
	["contract.C003.obj3"] = "Extract and Survive",

	["contract.C004.title"] = "CONTRACT #004",
	["contract.C004.subtitle"] = "FIELD MEDICINE",
	["contract.C004.obj1"] = "Recover 2 Medical Kits",
	["contract.C004.obj2"] = "Recover 3 Painkillers",
	["contract.C004.obj3"] = "Extract and Survive",

	-- ------------------------------------------------ Commanditaire ----
	--
	-- La voix de MERIDIAN. Froide, administrative, jamais inquiete pour le
	-- joueur — seulement pour la cargaison.
	["handler.deploy.1"] = "Uplink established. Your feed is being recorded.",
	["handler.firstLoot.1"] = "Item logged. Property of {company} until extraction.",

	["handler.cargoLow.1"] = "Cargo uninsured beyond this threshold.",
	["handler.cargoMid.1"] = "Notable cargo value. Extraction advised.",
	["handler.cargoMid.2"] = "Our underwriters are tracking your cargo live.",
	["handler.cargoHigh.1"] = "You are carrying more than your contract covers.",
	["handler.cargoHigh.2"] = "Estimated loss on incident: {cargo} credits.",

	["handler.bandALERT.1"] = "Irregular acoustic readings in your sector.",
	["handler.bandDANGER.1"] = "Hostile activity confirmed. Proceed if the yield justifies it.",
	["handler.bandSEVERE.1"] = "We are losing the sector feed. Decision is yours.",
	["handler.bandCRITICAL.1"] = "Withdrawal advised. We no longer guarantee your coverage.",

	["handler.hunt.1"] = "Total interference on the relay. We can no longer see you.\nContract coverage terminated.",
	["handler.huntEnd.1"] = "Relay restored. Your feed resumes.",

	["handler.teammateDown.1"] = "Asset {tag} lost. Cargo unrecovered.",
	["handler.teammateExtracted.1"] = "{tag} extracted. Cargo credited to contract.",

	["handler.lowHealth.1"] = "Biometrics degraded. A replacement is already queued.",

	["handler.idle.1"] = "No acquisitions logged for {seconds} seconds.",
	["handler.idle.2"] = "Reminder: time spent in the zone is billed to you.",
	["handler.idle.3"] = "Your contract is indexed on yield, not on duration.",

	["handler.windowWarning.1"] = "Contract window: {minutes} minutes remaining.",
	["handler.windowFinal.1"] = "{seconds} seconds. The relay closes, with or without you.",
	["handler.windowClosed.1"] = "Contract closed. Unextracted assets: acceptable losses.",

	["handler.extractionOpen.1"] = "Exit {zone} is open. Narrow window.",
	["handler.extractionDone.1"] = "Cargo secured. Balance credited: {credits}.",
	["handler.extractionLost.1"] = "Extraction interrupted. The contract remains open.",

	["handler.contractAssigned.1"] = "Contract {title} opened. Bonus {reward} credits.",
	["handler.objectiveDone.1"] = "Objective cleared: {objective}.",
	["handler.contractDone.1"] = "Contract fulfilled. Bonus {reward} paid on extraction.",

	["handler.ambient.1"] = "Feed nominal. Archiving in progress.",
	["handler.ambient.2"] = "Position logged. Timestamp transmitted.",
	["handler.ambient.3"] = "Any undeclared resource constitutes contractual fraud.",
	["handler.ambient.4"] = "Biometric record forwarded to insurance.",
	["handler.ambient.5"] = "You are the only variable cost on this contract.",


	-- Releves de capteurs. Le commanditaire ne devine rien : chacune de
	-- ces lignes repond a un fait mesure sur le serveur — un ennemi dans un
	-- rayon, un verrouillage, un depart de coup, un front meteo.
	["handler.contact.1"] = "Hostile signature — sector {bearing}, {distance} m.",
	["handler.contact.2"] = "Movement logged {distance} m out, sector {bearing}.",
	["handler.contactClose.1"] = "Contact at {distance} m, sector {bearing}. Close.",
	["handler.hunted.1"] = "You have been acquired. Something is tracking your position.",
	["handler.hunted.2"] = "Contact locked on you, sector {bearing}. Break line of sight.",
	["handler.gunfire.1"] = "Weapon discharge logged — sector {bearing}, {distance} m.",
	["handler.gunfire.2"] = "Small arms fire, {distance} m out. Not yours.",
	["handler.heavySignature.1"] = "Heavy signature in the sector. We do not have a classification for it.",
	["handler.weather.1"] = "{weather} front moving over the sector.",
	["handler.district.1"] = "You have entered {district}.",
	["handler.batteryLow.1"] = "Cell at {percent} per cent. Light fails before the contract does.",


	-- Secteurs cardinaux, employes par les releves de contact. Ils doivent
	-- correspondre a ceux de la boussole, sinon le joueur cherche au mauvais
	-- endroit.
	["sector.0"] = "N",
	["sector.1"] = "NE",
	["sector.2"] = "E",
	["sector.3"] = "SE",
	["sector.4"] = "S",
	["sector.5"] = "SW",
	["sector.6"] = "W",
	["sector.7"] = "NW",


	-- Verdicts d'emplacement. Un refus DOIT se lire : une touche qui ne
	-- produit rien passe pour cassee, meme quand le refus est legitime.
	["slot.VIDE"] = "EMPTY SLOT",
	["slot.VIE_PLEINE"] = "HEALTH ALREADY FULL",
	["slot.BATTERIE_PLEINE"] = "CELL ALREADY FULL",
	["slot.NON_UTILISABLE"] = "NOT USABLE",
	["slot.MORT"] = "UNAVAILABLE",
	["slot.RETRAIT_REFUSE"] = "ITEM UNAVAILABLE",
	["slot.SERVICE_INDISPONIBLE"] = "SYSTEM OFFLINE",
	["hud.sprint"] = "SPRINT",

	-- -------------------------------------------------------- Divers ----
	["item.pickup"] = "{name}",

	-- ---------------------------------------------------- Spectator view ----
	--
	-- The handler's vocabulary throughout : it never says "you died", it says
	-- the feed is lost and it is switching to another one.
	["spectate.down"] = "FEED LOST   SWITCHING TO ANOTHER ASSET",
	["spectate.extracted"] = "ASSET OFF SITE   CONTRACT STILL UNDER WATCH",
	["spectate.noSignal"] = "NO SIGNAL",
	["spectate.hint"] = "A / D   SWITCH FEED",

	-- ---------------------------------------------------- End-of-raid report --
	--
	-- Administrative register. The handler neither congratulates nor
	-- consoles : it records an accounting operation. "WRITE-OFF" is a balance
	-- sheet term, not an insult — which is exactly what makes it cold.
	["debrief.header"] = "MERIDIAN / OVERSIGHT",
	["debrief.subheader"] = "EXIT REPORT",
	["debrief.dossier"] = "FILE",
	["debrief.archived"] = "AUTOMATICALLY ARCHIVED",
	-- Classification band at the head of the document. The wording
	-- matters : the handler does not say "dead", it says "asset loss".
	["debrief.class.EXTRACTED"] = "CARGO RECEIVED",
	["debrief.class.KIA"] = "ASSET LOSS",
	["debrief.class.EXPIRED"] = "CONTRACT NOT EXECUTED",

	["debrief.outcome.EXTRACTED"] = "EXTRACTION CONFIRMED",
	["debrief.outcome.KIA"] = "SIGNAL LOST",
	["debrief.outcome.EXPIRED"] = "WINDOW CLOSED",

	["debrief.cause.EXTRACTED"] = "{zone}   ·   {duration} IN ZONE",
	["debrief.cause.KIA"] = "ASSET NEUTRALISED AFTER {duration}",
	["debrief.cause.EXPIRED"] = "ASSET ABANDONED ON SITE AFTER {duration}",

	["debrief.manifest.recovered"] = "RECOVERED MANIFEST",
	["debrief.manifest.lost"] = "CARGO LOST",
	["debrief.manifest.empty"] = "NO CARGO",
	["debrief.manifest.overflow"] = "AND {count} MORE",
	["debrief.manifest.total"] = "TOTAL",
	["debrief.manifest.leftBehind"] = "{count} STACK(S) LEFT BEHIND — STASH FULL",

	["debrief.log.title"] = "MISSION LOG",
	["debrief.log.kills"] = "KILLS",
	["debrief.log.damage"] = "DAMAGE TAKEN",
	["debrief.log.peak"] = "PEAK THREAT",
	["debrief.log.objectives"] = "OBJECTIVES",
	["debrief.log.duration"] = "DURATION",

	["debrief.balance.cargo"] = "CARGO",
	["debrief.balance.bonus"] = "EXIT BONUS",
	["debrief.balance.paid"] = "PAID",
	["debrief.balance.nothing"] = "NO PAYMENT",
	["debrief.balance.account"] = "BALANCE",
	["debrief.balance.xp"] = "EXPERIENCE",
	["debrief.balance.level"] = "LEVEL {level}",
	["debrief.balance.levelUp"] = "PROMOTED   LEVEL {level}",

	["debrief.rating"] = "ASSESSMENT",
	["debrief.rating.EXEMPLARY"] = "EXEMPLARY",
	["debrief.rating.SATISFACTORY"] = "SATISFACTORY",
	["debrief.rating.MARGINAL"] = "MARGINAL",
	["debrief.rating.DEFICIENT"] = "DEFICIENT",
	["debrief.rating.WRITE_OFF"] = "WRITE-OFF",

	["debrief.contract.complete"] = "CONTRACT FULFILLED",
	["debrief.contract.failed"] = "CONTRACT UNFULFILLED",

	["debrief.closing.EXTRACTED"] = "Cargo received. Remain available.",
	["debrief.closing.KIA"] = "Asset lost. Cargo unrecovered.",
	["debrief.closing.EXPIRED"] = "Window closed. No payment for this run.",

	["debrief.dismiss"] = "ACKNOWLEDGE",

	-- Noms d'objets. ItemDatabase garde les siens pour les journaux
	-- serveur ; c'est cette table qui s'affiche au joueur.
	["item.military_battery"] = "Military Battery",
	["item.scrap_metal"] = "Scrap Metal",
	["item.bandage"] = "Bandage",
	["item.painkillers"] = "Painkillers",
	["item.gold_chain"] = "Gold Chain",
	["item.graphics_card"] = "Graphics Card",
	["item.keycard_blue"] = "Blue Keycard",
	["item.black_box"] = "Black Box",
	["item.medkit"] = "Medkit",
	["item.ammo_762"] = "7.62 Ammo",
	["item.armor_plate"] = "Ballistic Plate",
	["item.weapon_parts"] = "Weapon Parts",
	["item.pistol_mk1"] = "Pistol MK1",
	["item.rifle_ak"] = "7.62 Rifle",
	["item.ammo_9mm"] = "9mm Ammo",
	["item.prototype_core"] = "Prototype Core",


	-- Lieux. Traduits comme des noms communs plutot que laisses en nom
	-- propre : « QUARTIER NORD » situe, « NORTH DISTRICT » ne dit rien a un
	-- joueur francophone.
	["world.district.NORTH DISTRICT"] = "NORTH DISTRICT",
	["world.district.PORT AUTHORITY"] = "PORT AUTHORITY",
	["world.district.OLD TOWN"] = "OLD TOWN",
	["world.district.INDUSTRIAL BELT"] = "INDUSTRIAL BELT",
	["zone.NORTH GATE"] = "NORTH GATE",
	["zone.EAST DOCKS"] = "EAST DOCKS",
	["zone.SOUTH YARD"] = "SOUTH YARD",
	["zone.WEST TUNNEL"] = "WEST TUNNEL",
	["world.weather.CLEAR"] = "CLEAR",
	["world.weather.RAIN"] = "RAIN",
	["world.weather.FOG"] = "FOG",
	["world.weather.STORM"] = "STORM",
}
