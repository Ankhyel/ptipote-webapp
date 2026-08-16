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

## P’TIPOTE — vie quotidienne et autonomie

- Niveau 1 : aucune autonomie. Niveau 2 : sommeil autonome à 30 % ou moins,
  si une alcôve est libre. Niveau 3 : alimentation autonome à 20 % ou moins,
  uniquement avec un Frigo fonctionnel et une nourriture réellement stockée.
  Niveau 4 prépare le retour vers l’emploi explicitement assigné (Tour, Craft
  ou Lisière), sans dépasser les besoins vitaux.
- Les capacités sont calculées par niveau, sans soin gratuit : Énergie max
  `+15` et Faim max `+5` par niveau après le niveau 1. Les sauvegardes legacy
  préservent leur proportion de remplissage lors de cette migration.
- Bonheur = Matériel (30) + Vital (20) + Attachement (50). Quatre types de
  meuble installés au plus apportent 2,5 chacun, un autre P’TIPOTE apporte
  10, et le niveau de Maison apporte 2,5 par niveau (max. 10). Faim et Sommeil
  donnent chacun 0/5/10 aux seuils <30 / 30–69 / ≥70.
- L’Attachement est une source horodatée : maximum 50, décroissance -1/h y
  compris hors ligne. Câlin +5, Entraînement réussi +20 et Promenade réussie
  +30 ; le Câlin et la Promenade ne donnent pas d’XP.
- La Salle d’entraînement de la Maison contient Mouvement : quatre flèches,
  fenêtre active d’1 s, trois vies et dix validations. Une réussite donne
  `10 × niveau de jeu` XP ; deux autres emplacements restent réservés.
  Promenade tire Cache-cache ou Attrape-moi sans pénalité d’échec.
- **Jardin bioponique** (6 Organique, 2 Minéral, 2 Mycélium) et **Bassin
  thermal** (6 Minéral, 4 Organique, 2 Mycélium) sont des produits finis de
  mobilier communs : ils utilisent l’inventaire/les emplacements de foyer des
  habitants et peuvent aussi être installés dans la Maison P’TIPOTE.
- Artisan N0 peut Craft et Construire ; N1/N2/N3 réduisent la durée de
  5/10/15 %, plus 1 % par niveau P’TIPOTE. Vendeur N1/N2/N3 ajoute
  5/10/15 %, plus 1 % par niveau. Les durées de Craft/Construction sont
  snapshotées au lancement ; `requiredJobLevel` reste un hook sur les futures
  capacités, pas une liste d’arbres de talents.

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

## FabLab V2 — bâtiment unique et salles

- Le **FabLab** est le seul bâtiment physique : il porte sa Viabilité, ses
  réparations météo/mini-jeux et le stockage commun. Cuisine, Atelier et
  Recycleur sont des salles internes, sans Viabilité, météo ni stock propres.
  Une salle est construite de N0 à N1 puis améliorée, sans jamais dépasser le
  niveau du FabLab.
- Stockage FabLab N1→N4 : **100 / 200 / 300 / 400**. Stockage Maison N1→N4 :
  **100 / 125 / 150 / 200**. La capacité de camp est dérivée de Maison +
  FabLab ; un stock legacy au-dessus du plafond est conservé mais bloque les
  nouveaux dépôts jusqu’au retour sous la capacité.
- Cuisine et Atelier ont un créneau manuel et 1/2/3/4 postes P’TIPOTE aux
  niveaux 1→4. Un P’TIPOTE en poste reste dans sa salle après un ordre et peut
  être retiré explicitement avec **Rentrer**. Les quantités sont 1/5/10, +25
  au N2 et +50 au N3 ; la file visible contient 0/1/2/3 ordres. Le réassort
  Marché est réservé au N4 et doit être autorisé recette par recette.
- Le Recycleur produit seulement **Organique** et **Minéral** : N1 18→10,
  N2 16→10, N3 14→10, N4 12→10. Ses cuves sont 20 ; 40 ; 40+20 ; 60+40. À N3
  la Cuve 1 reçoit un module, à N4 les deux. Un module Organique ou Minéral
  garantit au moins 6 unités ciblées sur 10, les quatre restantes restant
  toujours Organique ou Minéral.
- La migration est versionnée et idempotente : le FabLab devient au minimum le
  maximum des anciennes salles, aucun niveau/craft/stock n’est supprimé. Les
  anciennes Viabilités de salle sont ramenées à une Viabilité FabLab unique de
  façon conservatrice, sans cumuler artificiellement les dégâts.
