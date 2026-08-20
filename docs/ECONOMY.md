# BLACKOUT — Economie

Valeurs vivantes dans `src/ReplicatedStorage/Shared/Config/EconomyConfig.luau`.
Ce document explique **pourquoi** elles valent ca ; le code dit **combien**.

## Sources de credits

| Source | Reglage | Note |
| --- | --- | --- |
| Extraction reussie | `extractionBonus` | Recompense le risque pris |
| Vente de butin | `vendorBuybackRate` | TBD : par item ou par rarete ? |
| Contrats | TBD | Voir `MissionService` |

## Puits de credits

| Puits | Reglage | Note |
| --- | --- | --- |
| Assurance | `insuranceRate` | Le principal amortisseur |
| Achat d'equipement | `vendorSellMarkup` | |
| TBD | | |

## Le point a surveiller

Le rachat vendeur (`vendorBuybackRate = 0.45`) est le robinet qui absorbe
l'inflation du loot. Si les joueurs s'enrichissent trop vite, c'est le
premier chiffre a baisser — avant de toucher aux tables de butin, qui elles
changent la sensation de jeu.

## Courbe d'XP

`xpCurve(level) = 500 * level^1.45`. TBD : valider sur 20 niveaux que le
temps de jeu par palier reste dans la fourchette voulue.
