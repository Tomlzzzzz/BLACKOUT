# BLACKOUT

Extraction shooter Roblox. Le disque est la source de verite ; Studio est un
miroir alimente par Rojo.

## Arborescence

- `src/` — miroir du DataModel (voir `default.project.json`)
- `assets/` — sources hors-jeu (modeles, textures, audio) avant upload
- `docs/` — design, economie, systemes, roadmap
- `tests/` — vide pour l'instant

## Prerequis

Rojo n'est **pas encore installe** sur cette machine. Il en faut deux moities :

1. le binaire `rojo.exe` — <https://github.com/rojo-rbx/rojo/releases>
2. le plugin Studio « Rojo » — installable depuis le binaire
   (`rojo plugin install`) ou depuis le Creator Store

## Sync

```
rojo serve
```

puis dans Studio : plugin Rojo -> Connect.

## Regle qui evite de perdre du travail

Quand `rojo serve` tourne, **ne pas editer les scripts dans Studio** : la
prochaine sync ecrase. Les scripts se modifient sur le disque. Ce qui se
construit dans Studio, c'est la geometrie de `Workspace` — protegee par
`$ignoreUnknownInstances` pour que Rojo n'y touche pas.
