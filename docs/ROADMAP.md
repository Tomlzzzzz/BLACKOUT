# BLACKOUT — Roadmap

## Fait

- [x] Arborescence Rojo + squelette de services
- [x] Boot serveur deux phases avec isolation des pannes
- [x] Boot client symetrique
- [x] Types, Constants, Config partages

## Prochain — rendre le squelette jouable

- [ ] Installer Rojo et verifier la premiere sync vers Studio
- [ ] `DataService` : profil DataStore reel + autosave
- [ ] `PlayerService` : spawn et mort
- [ ] `InventoryService` : structure du sac, poids porte
- [ ] Une zone d'extraction posee dans Workspace + `ExtractionService`
- [ ] Boucle minimale bout en bout : entrer, looter un objet, extraire

## Ensuite

- [ ] Tables de butin remplies (`LootConfig.tables` est vide)
- [ ] `EnemyService` : premier archetype fonctionnel
- [ ] `ThreatService` branche sur EnemyService
- [ ] UI : sac, credits, minuterie de raid
- [ ] `MissionService`

## Plus tard

- [ ] `MonetizationService`
- [ ] `AnalyticsService`
- [ ] Tests dans `tests/`
