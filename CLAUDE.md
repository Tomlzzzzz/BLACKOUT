# BLACKOUT — conventions

## Regle numero un : ou vit le code

Le disque est la source de verite, Rojo synchronise vers Studio.

**Ne jamais editer un script via les outils MCP Studio** (`multi_edit`,
`execute_luau` qui ecrit du code) quand `rojo serve` tourne : la sync
suivante ecrase la modification sans prevenir. Les scripts se modifient dans
`src/`.

Les outils MCP Studio servent a : inspecter l'arbre (`search_game_tree`,
`inspect_instance`), lire la console (`get_console_output`), lancer un
playtest (`start_stop_play`), poser des assets et de la geometrie dans
`Workspace`.

## Luau

- `--!strict` en tete de chaque fichier, sans exception
- Tabulations pour l'indentation (convention Roblox)
- Types partages dans `Shared/Types` — ne jamais redefinir un type localement
- Constantes figees dans `Shared/Constants`, valeurs tunables dans
  `Shared/Config`. Aucun nombre magique dans un service.

## Services

Un service = un ModuleScript dans `Server/Services/`, respectant
`Types.Service`. Voir `docs/SYSTEMS.md` pour le contrat complet et la regle
Init/Start.

Ajouter un service = poser le fichier. Le Bootstrap le ramasse tout seul,
aucun registre a mettre a jour.

## Reseau

Tout remote est declare dans `Constants.REMOTES`. Le serveur valide, le
client demande. Ne jamais faire confiance a une valeur venant du client.

## Langue

Commentaires et docs en francais. Noms de code en anglais.

# BLACKOUT — Roblox Development Rules

## Project

BLACKOUT is a 1-6 player cooperative survival/extraction horror game.

Core loop:

LOOT → RISK → DECISION → EXTRACTION → REWARD → PROGRESSION

## Technology

- Roblox Studio
- Luau
- Roblox Studio MCP
- Git
- GitHub

## Architecture

Use a server-authoritative architecture.

Server owns:

- inventory
- currency
- XP
- loot generation
- damage
- enemy state
- extraction
- missions
- purchases
- progression
- persistence

Client owns:

- UI
- camera
- input
- visual effects
- local animations
- non-authoritative presentation

## Coding Rules

- Use strict Luau typing whenever practical.
- Prefer small modular services.
- Never put business logic inside UI scripts.
- Never trust client data.
- Validate every RemoteEvent.
- Never duplicate game state between client and server unnecessarily.
- Avoid global mutable state.
- Use clear names.
- Use PascalCase for modules/classes.
- Use camelCase for local variables.
- Document non-obvious systems.

## Performance

Target:

- 60 FPS desktop
- playable mobile performance
- low network traffic
- minimal unnecessary Heartbeat connections

Avoid:

- infinite loops without task.wait()
- expensive per-frame raycasts
- unnecessary RemoteEvent spam
- massive replicated tables
- server-side physics for cosmetic objects

## Security

Never trust:

- client money
- client inventory
- client damage
- client position
- client purchase claims
- client extraction claims

All rewards must be server-authoritative.

## Development Workflow

Before implementing a feature:

1. Inspect existing architecture.
2. Identify affected services.
3. Explain the implementation plan.
4. Implement the smallest clean version.
5. Run Luau/static checks where available.
6. Playtest.
7. Inspect console output.
8. Fix errors.
9. Verify edge cases.
10. Summarize changes.

Do not rewrite unrelated systems.

## MCP

When Roblox Studio MCP is available:

- inspect the DataModel before editing
- read existing scripts before modifying them
- use targeted edits
- run playtests after significant changes
- inspect console output
- never blindly overwrite working systems

## Game Design

BLACKOUT must prioritize:

1. fun
2. retention
3. social interaction
4. readable progression
5. fair monetization

Do not introduce pay-to-win mechanics without explicit approval.

## Current MVP

The first playable build only needs:

- one map
- one extraction zone
- basic inventory
- basic loot
- one enemy
- threat meter
- extraction
- death
- basic credits
- basic progression

Do NOT build seasons, clans, trading, pets, crafting or 20 weapons before the core loop is fun.
