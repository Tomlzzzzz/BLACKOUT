# BLACKOUT — Game Design Document

> Squelette. Les sections marquees TBD attendent tes decisions de design ;
> je ne les invente pas.

## Pitch

TBD — une phrase, le genre d'accroche qui tient dans une description de jeu.

## Boucle de jeu

L'arborescence (`ExtractionService`, `LootSpawns`, `ThreatService`) decrit un
**extraction shooter** : deploiement, pillage sous pression, extraction ou
mort avec perte du butin.

1. Lobby — preparation du sac, choix du contrat
2. Deploiement — insertion sur la carte
3. Raid — loot, ennemis, menace croissante
4. Extraction — maintien dans la zone / mort
5. Retour — stash, vente, progression

TBD : confirmer, et preciser ce qui se perd exactement a la mort.

## Piliers

TBD — trois maximum. Ils servent d'arbitre quand deux features se disputent.

## Progression

TBD — niveaux, deblocages, ce qui fait revenir au raid suivant.

## Cible

TBD — age, temps de session vise, plateforme prioritaire (mobile ?).

## Camera — DECISION REVUE

Le GDD d'origine annonce une camera a la **troisieme personne**. La decision
a ete revue en production : le jeu est en **premiere personne**.

Raison : pour un survival horror, le champ de vision doit etre une ressource.
Ce que le joueur ne voit pas derriere lui doit lui couter quelque chose, ce
qui est impossible avec une camera qui voit a 360 degres.

Consequence : la camera devient un canal d'information a part entiere.
L'escalade de menace y vit autant que dans le HUD — resserrement du champ,
respiration, tremblement. Voir `Shared/Config/CameraConfig`.

Revenir en arriere se fait en deux lignes : `StarterPlayer.CameraMode` dans
`default.project.json` et `lockFirstPerson()` dans `CameraController`.

## Le commanditaire

Le document dit que « des entreprises privees recrutent des Scavengers ».
C'est le pilier de ton du jeu, et il est desormais implemente.

Le joueur ne pille pas pour lui : il est **envoye**, **surveille** et
**comptabilise**. Concretement, a l'ecran :

- une camera embarquee qui enregistre en continu (temoin, horodatage)
- une liaison qui se degrade a mesure que la menace monte
- une fenetre de contrat qui se referme, qu'il soit sorti ou non
- une directive imposee, qu'il n'a pas choisie
- des transmissions froides d'un bureau qui parle de lui comme d'un actif

Le retournement : **a THE HUNT, le bureau se tait**. La liaison est perdue,
la surveillance qui pesait tout le raid disparait au moment ou le joueur en
aurait besoin. C'est le seul moment ou il est vraiment seul.

Le nom de l'entreprise (`MERIDIAN`) est le seul element de lore ajoute qui
ne vient pas de ce document. Une ligne a changer dans
`Shared/Config/HandlerConfig`.

TBD : confirmer le nom, ou en choisir un autre.
