# BLACKOUT — Systemes

## Contrat de service

Tout module de `Server/Services/` retourne une table respectant
`Types.Service` :

```lua
Service.Name = "MonService"   -- defaut : nom du ModuleScript
Service.Priority = 50         -- defaut : 100, croissant = plus tard
function Service.Init(ctx) end
function Service.Start() end
function Service.Stop() end
```

Le meme contrat vaut pour les controllers client.

## Les deux phases du boot

`Bootstrap.server.luau` fait deux passes, et la distinction est structurante :

- **Init** — chaque service prepare son etat seul. **Interdit d'appeler un
  autre service ici** : l'ordre n'est garanti que par `Priority`, et une
  dependance croisee en Init produit un nil silencieux.
- **Start** — tout le monde est enregistre, `ctx.Get("Autre")` repond.
  C'est la que les services se parlent.

Un service qui leve dans `Init` ou `Start` est retire du registre et
journalise. Le serveur demarre quand meme, amputé, et le dit dans la console.

## Priorites actuelles

| Priority | Service |
| --- | --- |
| 10 | DataService |
| 20 | PlayerService |
| 30 | InventoryService |
| 40 | EconomyService |
| 50 | LootService |
| 60 | EnemyService |
| 65 | ThreatService |
| 70 | ExtractionService |
| 80 | MissionService |
| 90 | MatchService |
| 95 | MonetizationService |
| 99 | AnalyticsService |

## Remotes

Declares dans `Shared/Constants` (`Constants.REMOTES`), instancies au boot
sous `ReplicatedStorage.Remotes`. Aucun RemoteEvent ne doit etre cree
ailleurs : sinon le client ne sait plus ce qui existe, et rien ne garantit
l'ordre de creation.

## Autorite

Le serveur decide, le client demande. Inventaire, credits et extraction sont
valides serveur ; le client n'envoie que des intentions.
