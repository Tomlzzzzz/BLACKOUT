# BLACKOUT

Extraction horror Roblox, 1 a 6 joueurs. Le disque est la source de verite ;
Studio est un miroir alimente par Rojo.

## Arborescence

- `src/` — miroir du DataModel (voir `default.project.json`)
- `assets/` — sources hors-jeu (modeles, textures, audio) avant upload
- `docs/` — design, economie, systemes, roadmap
- `tests/` — 15 suites, lancees depuis Studio
- `attic/` — code retire de la place mais conserve. Ne PAS remettre dans
  `src/` : Rojo le resynchroniserait dans le jeu.

## Sync

```
rojo serve
```

puis dans Studio : plugin Rojo -> Connect.

## Tests

Pendant un playtest, dans la console du serveur :

```lua
require(game.ServerStorage.Tests.RunAll).run()
```

## Deux regles qui evitent de perdre du travail

**Ne pas editer les scripts dans Studio** quand `rojo serve` tourne : la
prochaine sync ecrase sans prevenir. Les scripts se modifient sur le disque.
Ce qui se construit dans Studio, c'est la geometrie de `Workspace` —
protegee par `$ignoreUnknownInstances` pour que Rojo n'y touche pas.

**Une suppression faite dans Studio n'existe pas tant que la place n'est pas
enregistree.** Un script retire reapparait au rechargement suivant si on a
oublie le Ctrl+S — c'est deja arrive.

## Git

Les fins de ligne sont normalisees en LF dans le depot (`.gitattributes`).
Sans ca, Windows reecrit chaque fichier entier a l'aller-retour et produit
des conflits sur des lignes que personne n'a touchees.

Les fichiers de place (`.rbxl`, `.rbxlx`) sont ignores volontairement : les
versionner reintroduirait une seconde source de verite qui divergerait au
premier playtest.
