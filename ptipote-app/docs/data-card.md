# Data Card — Réparation interactive

Un bâtiment endommagé peut être réparé de deux façons : payer le coût normal
ou **réparer soi-même**. Les deux actions restaurent exactement la quantité de
Viabilité sélectionnée. La réparation interactive ne consomme ni ressources,
ni Kit de réparation, et ne donne ni XP, ni monnaie, ni loot.

Le jeu tire une tentative stable entre trois mini-jeux, avec des poids
configurables dans `buildingViability.repairMiniGames` :

- **Correspondance** : niveau 1, une couleur cachée ; niveau 2, cinq couleurs
  et deux cachées ; niveau 3, sept couleurs et trois cachées.
- **Canalisations** : le prototype de tuyaux est réutilisé. Une connexion entre
  l'entrée et la sortie valide la réparation ; les pièces reliées sont bleues.
  La table prévoit 3×3/16 pièces, 4×4/14, puis 5×5/12.
- **Fioles** : quatre couches par couleur et toujours deux fioles de travail.
  La table prévoit 3 couleurs/5 fioles, 4/6 puis 5/7.

Il n'existe ni minuteur, ni vie, ni pénalité. Échec, abandon et recommencement
ne modifient pas la Viabilité. Une tentative réussie est identifiée par un
`repairAttemptId` : elle ne peut appliquer la réparation qu'une seule fois.
Les réparations autonomes des habitants et les Kits de réparation conservent
leur fonctionnement existant.

## Biofermenteur et Bassin de calcium

Le Biofermenteur conserve sa réserve d'Organique verte, récoltée par le
joueur. Sa Lithoculture reçoit jusqu'à `30 + 10 par niveau` Minéraux : chaque
tranche de 10 démarre un cycle d'une heure qui ajoute 3 Organique à la réserve.

Le **Bassin de calcium** est un module du seul biome **Bassin minéral**. Il
ajoute une réserve d'Eau (`30 + 10/niveau`), une réserve d'Organique
(`9 + 3/niveau`) et une réserve de Minéral. La pluie modérée, forte et sévère
apporte respectivement 2, 5 et 10 Eau par heure. Chaque heure productive, le
Bassin conserve ses Minéraux de la cuve, produit 1 Minéral par tranche de 10,
et consomme 1 Organique ainsi que 2 Eau. Un P’TIBUG `mineur` ou
`lithoculture` actif dans le biome ajoute +1 Minéral/h au cycle.
