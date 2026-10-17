# Data Card — Réparation interactive

> **Frontière documentaire.** Les règles historiques Zone 0 / Camp ci-dessous
> restent propres à ce jeu. Elles ne deviennent jamais des règles Élevage par
> défaut.

## P’TIPOTE Élevage — V0 mobile

P’TIPOTE Élevage est une expérience Flutter distincte de Zone 0, ouverte depuis
la page d’accueil. Elle vit dans `lib/features/elevage/` et ne lit ni n’écrit
les documents Firestore Zone 0. La V0 TestFlight est locale à l’appareil :
`schemaVersion: 1`, sauvegarde `ptipote:elevage:save`, backup
`ptipote:elevage:save:backup`, configuration séparée
`ptipote:elevage:config` et timestamps epoch milliseconds UTC. Les seeds,
profils générés, sorties et coûts réellement payés sont persistés : aucun reload
ne reroll un individu ou un loot.

Le seul profil instancié est **MINERAL / RESONANCE**. Un seed fixe ROOT ou LEAF
comme préférence, les variations environnementales et la baseline de
personnalité (`initiative`, `contact`, `tempo`). Figurine mockée et Co-élevage
partagent le même individu métier ; le prêt a `startedAt`, `expiresAt`,
`sourcePoolId` et reste temporaire. À expiration, le retour est idempotent,
libère l’Alcôve sans détruire son aménagement et crée une notification persistée
du Sourcier.

Une Alcôve possède quatre slots configurables. LIGHT, TEMPERATURE et HUMIDITY
sont dérivés depuis ses installations, jamais sauvegardés comme seconde source
de vérité. Les instances CRAFTED gardent `paidCost` et `sourceConfigRevision`.
Le placement dev est explicite, gratuit et non remboursable. Déménager détruit
les seules instances CRAFTED posées et rend
`floor(total organic/mineral payé × rate)` ; les composants spéciaux et la
réserve hors Alcôve ne sont jamais remboursés.

Résonance mange ROOT, LEAF, MOSS, ALGAE ou MUSHROOM. ROOT/LEAF est découvert
par preuves UNKNOWN → SUSPECTED → CONFIRMED. La faim dérive de `lastMealAt`,
reste lente et non punitive. IRON apporte 2 unités structurelles, LIMESTONE 1,
QUARTZ 0 : un matériau ne nourrit jamais l’individu. `FIRST_FOOD`,
`FIRST_FAVORITE_FOOD`, `FIRST_TREAT` et `FIRST_AUTONOMOUS_MEAL` sont
idempotents ; une friandise n’est pas un repas.

La Mini-Lisière Élevage est séparée de la Lisière Zone 0 : Forêt, Littoral ou
Colline, durée timestampée configurable, exactement trois pistes persistées et
un seul choix atomique. La Forêt donne Organic et ressources végétales, le
Littoral ALGAE/ALGAE_FRAGMENT/LIMESTONE, la Colline MINERAL/LIMESTONE/QUARTZ/
IRON. Le Bio-fabricateur consomme réellement l’inventaire : BASSIN exige
LIMESTONE + ALGAE_FRAGMENT, MOSS_STONE exige MOSS, et les recettes découvertes
restent connues après consommation du composant.

Les installations productives ont un stock local plafonné dérivé de timestamps
(Bassin ALGAE/MOSS, Culture ROOT/LEAF, Butte FRUIT, Géodes IRON/QUARTZ). Elles
ne remplissent pas l’inventaire passivement. Résonance peut manger localement
et absorber IRON; l’alimentation manuelle reste toujours possible.

Le Sourcier V0 utilise les Bio-piles, affiche au plus trois offres (Fruit
fibreux et Jelly fruité livrés) et rachète seulement Organique/Minéral selon
la config. Les transactions sont atomiques. Le Dashboard mobile local édite
Preset, devMode, faim, découverte, Mini-Lisière, production, Co-élevage,
Sourcier, recettes et métamorphose. Ses overrides versionnés sont séparés de la
sauvegarde joueur et réinitialisables. Le Dashboard web Firestore actuel reste
la configuration Zone 0 : Élevage mobile est volontairement local dans cette
première build, afin de ne pas coupler le prototype aux documents Zone 0.

Le temps n’évolue jamais seul un P’TIPOTE. Bébé demande 24 h en Prototype (48 h
Target), Intermédiaire 72 h supplémentaires (168 h Target), plus repas,
structure, compréhension, aménagement et autonomie. La métamorphose est
volontaire, utilise trois motifs sans pénalité et fait passer BABY à
INTERMEDIATE puis MATURE. BABY reste comportemental, INTERMEDIATE communique
par catégories et MATURE peut préciser ROOT/LEAF/IRON. Mature reste jouable.

### Présentation joueur — Lot 12

L’Alcôve mobile affiche une scène placeholder autonome : fond construit avec
les couleurs Flutter, P’TIPOTE représenté par une silhouette/icône, déplacement
léger gauche/droite et petites icônes pour les installations posées. Cette couche
vit uniquement dans la présentation ; elle est conçue pour être remplacée plus
tard par des sprites, fonds et mini-illustrations sans modifier le domaine.

L’inventaire est la source visuelle des objets du joueur. Il regroupe
**Nourriture**, **Friandises**, **Matériaux** et **Ressources**, puis filtre les
objets réellement proposables à Résonance. Après Mini-Lisière, un résultat
explicite détaille le gain avant le retour à l’Alcôve. Les IDs du domaine
(`ROOT`, `IRON`, etc.) ne sont pas exposés : une couche de présentation fournit
les libellés FR, icônes placeholder et feedbacks émotionnels courts. Les
feedbacks ne modifient pas la vérité métier : ils traduisent seulement les
réactions existantes. Lorsque `devMode` est désactivé, l’ajout d’inventaire dev
et le Dashboard local ne sont plus exposés dans le parcours joueur.

### Carnet d’observation — Lot 13

Chaque individu possède un `observationJournal` persistant, indépendant des
preuves de maturation. Une observation significative est dédoublonnée par
`type + sujet` et conserve `firstObservedAt`, `lastObservedAt`, `count`, le
contexte (objet ou axe environnemental) et son statut. Le Carnet affiche trois
vues : **Observations** (comportements vus), **Hypothèses** (`SUSPECTED`) et
**Découvertes confirmées** (`CONFIRMED`), plus les souvenirs importants déjà
existants. Il ne révèle jamais les valeurs ou préférences UNKNOWN.

Le starter normal attribue seulement ROOT ×1 et LEAF ×1 à l’adoption. Les
stocks de test restent réservés à `devMode`. La satiété est une valeur dérivée
de `lastMealAt` : une jauge 0–100 informe le joueur sans être sauvegardée. Un
repas organique est refusé seulement juste après un repas réussi ; les
friandises restent distinctes. À partir d’INTERMEDIATE, la structure minérale
est affichée séparément de la maturation.

La scène possède toujours une zone ombragée et une zone éclairée. Résonance a
un biais comportemental doux vers l’ombre ; les passages significatifs créent
une observation LIGHT_SHADE, puis une hypothèse/confirmation aux seuils de
configuration. Le HUD représente LIGHT, TEMPERATURE et HUMIDITY sur une échelle
relative 1–5 (`-2 ou moins → 1`, `-1 → 2`, `0 → 3`, `1 → 4`, `2 ou plus → 5`) :
ce ne sont ni des degrés ni des pourcentages physiques.

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

## Construction et Bâtiment Logistique

- Les nouveaux chantiers de construction et d'amélioration utilisent une durée
  de base ×2 ; un chantier déjà lancé conserve son échéance enregistrée.
- Sans P'TIPOTE : matériaux et Données à 100 %, avec un coût Énergie propre à
  chaque définition de chantier. Avec P'TIPOTE : -20 % de matériaux physiques
  (arrondi supérieur), Données inchangées et aucun coût Énergie d'automatisation.
- Constructeur : N0 0 %, N1 -15 %, N2 -20 %, N3 -25 %, N4 -30 %, puis -1 %
  supplémentaire par niveau P'TIPOTE. Artisan reste réservé au Craft.
- Logistique se construit au Cœur du Camp N2. N1/N2/N3/N4 ajoutent
  respectivement +100/+200/+300/+400 stockage, 5/10/20/30 Kits et 1/1/1/2
  postes de maintenance. La file Construction est disponible au N3 (3 ordres
  par défaut) : elle lance 1 chantier Logistique à la fois au N3 et jusqu'à 2
  au N4. Les réparations automatiques traitent d'abord la Viabilité la plus
  basse sous le seuil choisi.

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

## Bâtiments de biome

Les bâtiments territoriaux sont des amplificateurs : leur production de base
reste modeste et les bons P’TIBUG présents dans le biome ajoutent une vraie
synergie. La formule est `base + (P’TIBUG éligibles × 3/j × module principal)`.
Seuls trois P’TIBUG au plus comptent, et le module principal multiplie la
**synergie seulement** : N1 ×1, N2 ×2, N3 ×3.

- **Forêt comestible** : Organique, Trait `pollinisateur`.
- **Réseau mycélien** : Mycélium, Trait mycélien existant (`decomposeur`).
- **Bassin minéral** : Minéral, Trait `mineur`.

Chaque bâtiment territorial possède au plus deux modules secondaires parmi :
**Stabilisation sécuritaire** (plancher 20/35/50), **Veille scientifique**
(plancher de connaissance 20/35/50) et **Protection météorologique**
(-15/-30/-50 % de dégâts physiques météo sur le bâtiment). Les planchers ne
s’ajoutent pas à la valeur dynamique et la protection ne concerne jamais les
afflictions biologiques.

Les modules **Sécurité** et **Veille** suivent des chantiers N1/N2/N3 de
1 h / 2 h / 3 h ; ils demandent respectivement 10/20/25 Minéral et 30/40/45
Organique, avec les Données configurées dans le Dashboard. Le module **Météo**
utilise les mêmes ressources et durées, avec ses Données Énergie, Mycélienne et
Toxique propres. Défaire un module libère son emplacement.

La Lithoculture est retirée : aucune conversion Minéral → Organique ni
substitution Déchets ne reste active. Le **Bassin minéral** du biome Bassin
minéral utilise un substrat minéral fixe, une réserve locale d’Eau et une
réserve locale d’Organique. Eau et Organique sont consommés, jamais le
substrat ; l’absence de l’un des deux met la production en pause. La pluie
remplit l’Eau locale au maximum. La production de base est 12 / 15 / 18
Minéral par 24 h aux niveaux 1 / 2 / 3 ; ses consommations sont 24 Eau + 18
Organique, puis 18 + 12, puis 12 + 6 par 24 h. Le calcul est offline et
déterministe.
L’Eau n’est pas une ressource globale du Camp.

## P’TIPOTES Protocoles — Noyaux et Enveloppes

- Un **Vestige** reste un P’TIPOTE sans Noyau ni Enveloppe. Un **Protocole**
  porte un Noyau concret : Végétal (Photosynthèse, Poison, Croissance),
  Mycélien (Filtration, Décomposition, Contrôle) ou Minéral (Protection,
  Résonance, Calcification). Les bonus mobiles restent liés au **Type** ; une
  Nature ne crée pas de bonus caché.
- Les huit Enveloppes source sont Guerrier Standard, Explorateur Standard,
  Analyste Partage, Analyste Bio-piratage, Producteur Porteur, Solaire,
  Colline et Montagne. Scientifique est affiché **Analyste**. Toutes sont
  compatibles avec tous les Noyaux dans cette version ; leur famille donne
  Défense, Exploration, Analyste ou Production.
- Un Protocole est à 50 % avec Noyau seul, puis passe par 75 / 100 / 125 %
  selon sa Symbiose d’Enveloppe. L’Enveloppe se débloque toujours au niveau 3
  et reste temporaire en Co-élevage : elle part avec le P’TIPOTE au départ.
- Les pools public et DEV des Protocoles/Enveloppes sont activables dans le
  Dashboard. Tous les Noyaux et toutes les Enveloppes y ont le même poids :
  il n’existe ni rareté ni bonus par variante.

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

## Marché N1 à N4

- Le Marché possède **5 / 6 / 7 / 8** emplacements de magasins aux niveaux
  N1 à N4. Chaque magasin possède trois emplacements de produit, un vendeur
  P’TIPOTE permanent et, lorsqu’il est installé, son propre Distributeur.
  Le vendeur dédié traite les demandes de son magasin après 3 minutes.
- La **Zone centrale** est disponible au N2. Elle couvre les magasins non
  couverts après 6 min, puis 4 min avec Optimisation logistique et 3 min avec
  Bio-logiciel technique. Travail d’équipe ouvre un second poste au N4.
- Ses améliorations sont des capacités d’une même infrastructure :
  Distributeur, Réparation, Recharge (N2), Logistique, Optimisation et Local
  technique (N3), puis Assistant commerçant, Travail d’équipe, Bio-logiciel
  et Merchandiser (N4). Réparation/Recharge nécessitent Vendeur N2 ;
  Logistique Vendeur N3 ; Merchandising Vendeur N4.
- La Logistique respecte une réserve minimale définie par produit. Les
  Distributeurs sont réparés en 20 min, 10 min avec Local technique et 5 min
  avec Bio-logiciel : les réductions ne se cumulent pas. Merchandiser ajoute
  aux seules ventes de Distributeur 10 % + 1 % par niveau P’TIPOTE ; avec deux
  employés centraux, seul le meilleur bonus est retenu.
- Avec **Assistant commerçant** installé et un P’TIPOTE présent à la Zone
  centrale, les offres non achetées du Sourcier sont sauvegardées à son départ.
  Elles restent dans un panneau déroulant sous sa carte : le joueur choisit
  lui-même de les acheter ou de les laisser en attente.

## Météo — afflictions et protections

- La météo utilise un état commun persistant pour les **P’TIPOTES**, les
  **P’TIBUG** et les habitants : Chaleur → Insolation/Surrégime, Pluie →
  Infection/Humidifié, Nuage toxique → Intoxiqué. Une affliction dure 8 h par
  défaut, puis immunise uniquement contre le même type pendant 24 h à partir
  de la contraction. Plusieurs types peuvent coexister sans prolonger une
  affliction déjà active ; une tentative refusée n’entraîne aucun coût ni
  dégât supplémentaire. Les états se résolvent par timestamps, y compris
  après fermeture de l’application.
- Les P’TIPOTES affligés travaillent à 70 % de productivité (un seul
  multiplicateur global) ; les habitants reçoivent -10 Bonheur par affliction
  active. Les P’TIBUG gardent leur malus météo de production existant, piloté
  désormais par l’affliction afin d’éviter tout double malus.
- Les protections personnelles P’TIPOTE se fabriquent à l’Atelier et occupent
  l’un des trois slots génériques : thermique, pluie/humidité, filtrante/
  toxique. Elles ne créent ni portage ni inventaire de cargaison. Protection
  thermique : 10 Organique, 5 Minéral, 5 Réflecteurs thermiques (30 min) ;
  protection pluie/humidité : 15 Organique, 5 Couches imperméabilisantes
  (30 min) ; protection filtrante/toxique : 8 Organique, 7 Minéral,
  10 Filtres (30 min).
- Les soins ont un cooldown commun de 4 h par entité : Anti-poison (lot de 4)
  -4 h toxique pour 2 Organique et 1 Minéral ; Gelée anti-poison (lot de 3)
  -3 h toxique **ou** chaleur pour 2 Organique et 1 Minéral ; Gelée hydratante
  (lot de 3) -4 h chaleur pour 2 Organique ; Antibiotique (lot de 3) -4 h
  pluie pour 2 Organique. Chaque Craft de soin dure 10 min.
- Les installations réduisent la durée sans descendre sous 2 h : Ventilation
  Termite -2 h chaleur ; Chloro-canaux -2 h pluie ; Installation filtrante
  -2 h toxique ; Bassin thermal -1 h pluie et toxique.
- Tout module démonté avec remboursement rend 50 % de ses **matériaux
  physiques réellement payés**, arrondis à l’inférieur ; aucune Donnée n’est
  rendue (`refundData = false` dans le Dashboard). Ce remboursement est soumis
  à un cooldown global de 72 h. Le retrait
  ou remplacement gratuit sans remboursement reste possible selon les règles
  du module concerné.

## PTIPOTE V2 — Lisière, exploration et patrouille

- Une Lisière V2 génère de façon déterministe **6 à 9 parcelles** par biome,
  reliées par des arêtes facile / moyenne / difficile. Les temps de trajet par
  classe, la capacité d’équipe (2 de base, +1 Gestion d’équipe, +1 par module
  d’optimisation dans la limite de deux), les seuils de métiers et la réserve
  de retour sont réglables depuis le Dashboard, section **Lisière V2**.
- Les cinq biomes de la Région et leurs passerelles sont réglables dans le
  Dashboard, section **Régions V2 et passerelles**. Une passerelle est
  utilisable dès que la connexion existe : elle n’a ni bâtiment, ni recherche,
  ni autre prérequis. Les missions calculent leur trajet inter-biomes depuis
  ce graphe régional persistant.
- Les nœuds Organiques sont désormais pilotés par l’écologie partagée : 10
  Vitalité de base, régénération physique et destruction possible. Les filons
  minéraux ont des couches finies et ne réapparaissent jamais. Les Déchets
  sont des nœuds finis distincts. Les rendements conservent leur fraction persistante entre deux
  actions. Puissance de récolte, fréquence d’action et modificateur de
  rendement sont trois caractéristiques distinctes.
- Le joueur tient un nœud de ressource pour utiliser son outil de base :
  **1 dégât par seconde**. Avec le mode Entraîner actif, le P’TIPOTE frappe
  en même temps, gagne **1 XP Récolteur par coup**, et devient Récolteur N1 à
  **100 XP**. Récolteur N1 peut être envoyé en autonomie. Les durées 30 min, 1 h, 2 h,
  4 h et 8 h incluent toujours l’aller et le retour ; la résolution est basée
  sur les timestamps et vise les parcelles en round-robin.
- Patrouilleur est un métier d’exploration distinct de l’Enveloppe Protecteur.
  Chaque rencontre vaut **5 XP** et chaque QTE réussi **15 XP** ; N1 est atteint
  à **50 XP**. En Lisière V2 comme en simulation, le QTE se joue avec les
  flèches haut, droite, bas et gauche du clavier.
- Les stocks Camp, avant-poste, équipe P’TIPOTE et P’TIBUG restent séparés.
  Une rotation transporte réellement sa cargaison, avec priorité aux
  transporteurs P’TIBUG — le porteur désigné passe en premier — puis ne dépose
  qu’à destination ; aucune ressource ne se téléporte. Une cargaison pleine
  affiche une balance rouge et ne reçoit plus de récolte.
- Le stockage Camp est l’inventaire physique `camp-storage-v2` : l’écran Camp,
  les rotations, la première mission et les contributions aux chantiers lisent
  cette même pile. Il n’existe aucun second stock miroir dans les fondations.
- Tous les P’TIBUG récoltent en autonomie : Scarabé privilégie le Minéral,
  Hyme l’Organique, Arac les Déchets puis l’Organique. Les traits Mineur,
  Pollinisateur et Récupérateur appliquent +10 % au rendement de leur
  ressource correspondante.
- La première mission de test demande de rapporter au Camp **5 Organique** et
  **3 Minéral**. Elle reste active tant que les matériaux ne sont pas déposés
  physiquement au Camp. La cargaison va d’abord dans les inventaires P’TIBUG
  de l’équipe, selon leur ordre de priorité ; sans place disponible, elle va
  dans les inventaires P’TIPOTE, limités à deux piles de ressources chacun.
- L’écran Lisière lit la Région et les biomes issus du questionnaire V2, et
  non la simulation locale. Les P’TIPOTES reliés récupèrent au premier lien
  les statistiques de leur figurine physique, puis leur vitalité d’expédition
  et leurs métiers sont sauvegardés dans l’état V2. Plusieurs parcelles sont
  sélectionnables pour une mission autonome.
- Un avant-poste actif peut être construit par biome ; il possède son stock
  propre. Les P’TIBUG issus de la collection V1 peuvent être reliés par leur
  identité seulement, sans déplacer ni modifier les stocks V1 : leur réserve
  d’autonomie, repos et capacité de transport deviennent alors des données de
  Lisière V2 persistantes. Un ravitaillement utilise les coûts horaires V1
  pendant huit heures : Hyme 3 Organique / 1 Minéral, Scarabé 1 / 3, Arak 2 / 2.
  L’énergie demeure dans son système domestique V1 existant, sans créer de
  seconde ressource énergétique dans le stock physique V2.
- Le danger de biome augmente de 1 toutes les deux heures, est réduit de 5
  lors d’une exploitation, puis est atténué par la sécurité de groupe. Une
  visite ne peut déclencher qu’une rencontre : nuage toxique (-10 % cargaison
  et le même état **Intoxiqué** persistant que la météo V1), drone (-25 % et
  -15 % vitalité max) ou chute (-10 % et -20 %). Les pertes ne peuvent jamais
  descendre sous la réserve de retour.
- L’état de danger, les visites déjà résolues, le Drone chef et son dernier
  résultat sont persistants. Les missions, rotations et maintenances se
  résolvent par timestamp à la réouverture, sans dépendre d’un écran resté
  ouvert.
- Une entrée accompagnée sur une parcelle lance automatiquement le QTE du
  Drone chef s’il est présent ; le boss est traité avant une rencontre normale.
- La durée choisie d’une mission comprend réellement son aller, son parcours
  Easy / Medium / Hard, son temps de travail et son retour. Les rotations
  automatiques mettent un porteur plein en transit, déposent dans un
  avant-poste pertinent ou au Camp, puis le rendent à l’équipe.
- Le joueur possède un slot Outil et un slot Équipement. Le Multi-outils de
  base est le seul outil initial : 1 action et 1 dégât de récolte par seconde.

## PTIPOTE V2 — Onboarding, Région et Camp

- Le premier P’TIPOTE peut provenir d’une **adoption numérique** ou d’une
  **figurine scannée en NFC**. Ces deux voies créent le même `PtipoteV2Profile`
  persistant : il n’existe pas de modèle de P’TIPOTE numérique parallèle. Le
  scan conserve son identité NFC et ne modifie pas les documents V1.
- La Couveuse V2 est persistée étape par étape : œuf, activation, éclosion,
  nommage, puis questionnaire. Une reprise après fermeture restaure le même
  P’TIPOTE et la même étape, sans doubler l’éclosion ni créer un second Camp.
- Le questionnaire comporte exactement trois choix : mer/montagne,
  neige/soleil et graine de champ/coquillages. Son résultat sélectionne l’un
  des quatre presets régionaux par le calcul V2 existant, avec son départage
  déterministe lié à la troisième réponse.
- La création du monde installe une Région, ses cinq biomes, le Camp, son
  Cœur, la Maison, le Kernel et un stock de Camp dans le document V2 dédié.
  La création est transactionnelle et idempotente. Les graphes de Lisière
  sont ensuite initialisés depuis les seeds de ces biomes.
- Le Camp V2 est accessible depuis l’accueil, sans passer par le Refuge V1.
  Il présente les écrans Camp, Maison et Kernel, le premier P’TIPOTE, les
  biomes initiaux, le stockage et le crochet persistant du premier habitant.
- Trois habitants bâtisseurs sont présents dès l’arrivée. Chaque bâtiment
  dispose de trois places et démarre un chantier de 24 h : une aide joueur
  est disponible toutes les 3 h et retire 3 h ; chaque ressource remise au
  chantier retire également 3 h. Leurs noms et envies de métier sont tirés à
  la création du Camp et leurs interventions passent par une boîte de dialogue
  RPG. Les recherches restent volontairement hors de ce premier cycle de test
  Lisière.

## PTIPOTE V2 — Worldcraft 0, monde partagé asynchrone

- Le territoire V2 est structuré en **World → WorldMap → Région → Biome →
  Parcelle**. Une Région n’appartient pas à un joueur : elle est lue depuis le
  World partagé. Les profils prototype sont Haut Refuge, Littoral, Sec, Mixte
  et Transition ; Transition et Mixte ne sont pas des Biomes.
- Le World de test contient une carte stable de **5 × 5**, soit 25 Régions,
  avec des liaisons orthogonales. C3 héberge le Hub Haut Refuge. Toute Région
  contient exactement cinq Biomes, y compris lorsqu’elle ne possède aucun
  Camp.
- Un Camp est une implantation mondiale unique par Région. Sa création passe
  par une opération serveur idempotente et transactionnelle : la Région reçoit
  son `campId` au même moment que le Camp est créé. Les clients ne peuvent pas
  écrire directement les collections Worldcraft.
- Le stockage mondial du Camp et la Réserve de passage sont des entités
  séparées. Les piles physiques arrivées dans `camp-storage-v2` sont
  transférées atomiquement vers le stockage mondial lors de l’ouverture du
  Camp ; les chantiers prélèvent ce stockage partagé. Cette pile locale reste
  uniquement la projection de transport de Prompt 1 et n’autorise aucun
  retrait voyageur.
- Le questionnaire V2 reste personnel et indicatif. En attendant le Walker,
  un sélecteur explicitement **DEV / PROTOTYPE** permet d’implanter le Camp
  dans une Région libre ; aucun déplacement artificiel n’est simulé.
- Les états macro Région, Biome et Camp sont horodatés et résolus à la demande.
  Le Biome porte désormais aussi l’état écologique physique V0 ; un Camp garde
  le même identifiant en mode Active ou Autonome.
- Les opérations d’extraction minérale agrégée, création de Camp, traces et
  réserves de passage portent un `operationId`. Une répétition renvoie le même
  résultat sans double effet. La Réserve de passage est séparée de tout stock
  personnel ou privé du Camp.
- Une WeatherCell peut couvrir plusieurs Régions : le résolveur régional lazy
  enregistre les cellules actives à partir de leurs timestamps. Les
  PlayerTrace expirent selon une durée configurable dans le Dashboard (24 h
  par défaut) et sont nettoyées paresseusement à la consultation d’une Région.
  Les formules météorologiques et écologiques restent réservées aux prochains
  lots.
- À la réouverture d’un Camp autonome, le résolveur conserve la même
  implantation et produit un message narratif de reprise ; aucune simulation
  détaillée d’habitant n’est exécutée pendant l’absence.

## PTIPOTE V2 — Worldbuilding 0, première carte jouable

- Worldbuilding 0 enrichit Worldcraft sans changer l’autorité du territoire :
  la même carte 5 × 5 et les mêmes coordonnées sont conservées. Chaque Région
  reçoit exactement cinq Biomes dans les positions internes **B1, A1, A2, A3,
  B3** ; B1, A2 et B3 sont proches du centre territorial, A1 et A3 sont plus
  éloignées.
- Les types disponibles sont : Littoral, Mangrove, Marais, Savane humide,
  Savane sèche, Semi-désert, Colline, Forêt sèche, Forêt humide et Haut
  Refuge. Les profils géographiques Haut Refuge, Littoral, Sec, Mixte et
  Transition choisissent des palettes de Biomes avec influences des Régions
  voisines. Mixte et Transition restent des profils, jamais des Biomes.
- La composition dépend exclusivement de la seed du World, de la coordonnée,
  du profil, de l’offset de génération et de la version Worldbuilding. Elle
  est donc déterministe, persistée dans les documents Région/Biome et ne se
  relance pas au chargement d’un joueur.
- Le Dashboard contient la configuration versionnée `worldbuildingV2` :
  matrice 5 × 5, palettes, positions, offsets, tags environnementaux, profils
  visuels, réponses météo déclaratives et tables de découvertes possibles.
  Après publication, l’action DEV « Appliquer Worldbuilding » met à jour les
  25 Régions par une opération idempotente sans modifier Camp, macro-états ou
  stocks.
- L’audit Worldbuilding avertit lorsque moins de trois types de Biomes sont
  présents dans une Région ou lorsqu’un même type représente plus de 50 % des
  125 Biomes de la carte. Il signale sans bloquer la génération les continuités
  géographiques à revoir.
- Chaque Région conserve également un résumé léger de ses cinq Biomes (type,
  position interne, seed, tags, sol et profil de génération). La carte DEV
  charge ces 25 résumés, tandis que la Lisière ne charge les cinq états
  détaillés que pour la Région visitée. L’inspecteur DEV affiche influences,
  tags, seeds, offsets et voisins.
- Les poids de composition (profil local, proximité et influences voisines),
  compatibilités et profils de génération de Parcelles sont externalisés dans
  `worldbuildingV2`. Le questionnaire peut classer des Régions recommandées
  sans jamais modifier la géographie mondiale.
- Chaque définition de Biome expose aussi des identifiants stables
  `visualProfileId` et `parcelGenerationProfileId`, ainsi qu’une compatibilité
  de voisinage déclarative. Ces références sont persistées avec les tags,
  seeds et positions : le client ne déduit donc pas l’identité d’un décor à
  partir de son sol. Les contrôles automatisés démontrent séparément l’effet
  de l’offset de coordonnée et celui des profils voisins.
- Les mappings `visualProfileIds`, `parcelGenerationProfiles` et
  `neighborCompatibility` sont éditables depuis la configuration
  `worldbuildingV2` du Dashboard. La Function les projette ensuite dans les
  Biomes partagés persistés ; aucune table locale concurrente n’est créée.
- Une fixture Flutter mobile 390 × 844 vérifie la scène Lisière 2D 3/4 :
  P’TIPOTE, nœuds, obstacle, destination et porteur P’TIBUG restent lisibles.
  Les nœuds visibles peuvent être maintenus directement dans cette projection
  pour déclencher la récolte existante ; les cartes de Parcelles restent une
  commande complémentaire de prototype, pas une seconde géographie.
- La scène rend maintenant le graphe réel des 6–9 Parcelles : les liaisons
  sont des chemins et chaque pastille est cliquable pour utiliser le
  déplacement accompagné existant. Une géométrie locale garde les points dans
  les limites et détourne les chemins d’un obstacle bloquant. Cela reste une
  collision 2D légère de présentation : la validation de trajet et la
  persistance continuent à appartenir au graphe de Parcelles.
  nœuds organiques, minéraux et déchets varient selon le profil visuel du
  Biome ; les emojis restent la banque d’art provisoire.
- La Lisière utilise la seed persistante de chaque Biome pour ses graphes de
  Parcelles. Son aperçu est un rendu local 2D à profondeur 3/4 : sol,
  accessoires, nœuds et êtres sont une projection lisible, non un terrain
  mondial synchronisé. Les hooks météo et trouvailles restent des données
  préparatoires ; l’écologie physique V0 ajoute les formules définies pour
  l’eau, le vivant et les Déchets.

## PTIPOTE V2 — Écologie physique 0

- **Source de vérité.** `biomeSharedStates/{biomeId}` porte l’état partagé
  `ECOLOGY_0_1` : Biomasse dérivée, socle biologique, Humidité,
  Contamination, amas de Déchets, Minéral de surface, Réserve minérale
  profonde, Mine et pression d’exploitation. Les Parcelles de la Lisière
  restent une projection 2D détaillée : elles ne synchronisent ni sprites ni
  décor individuel. Les mutations critiques passent exclusivement par les
  Cloud Functions ; les règles Firestore refusent l’écriture directe.
- **Biomasse et Organique.** La Biomasse n’a pas de timer propre et n’est pas
  plafonnée à 100. Elle est recalculée comme socle biologique (`10 ×
  (1 - Contamination / 100)`) plus la contribution de vitalité des nœuds
  Organiques. Un nœud standard a 10 Vitalité : une unité de dégât réussie
  donne une unité d’Organique. À conditions de référence, 0→10 prend 12 h.
  Les multiplicateurs Biomasse, Humidité, Contamination, météo et
  Putréfaction se multiplient. Trois épuisements dans 48 h détruisent le
  nœud ; une recréation naturelle est seulement proposée à Biomasse ≥90, au
  maximum une fois par Biome et par cinq jours.
- **Eau.** L’Humidité est mondiale et évolue heure par heure à partir des
  `WeatherCell` existantes, de l’évaporation et du drainage distincts. Une
  session météo dure quatre heures ; Pluie, Pluie forte et Torrentielle
  apportent respectivement +9, +15 et +20/h avant la réponse géographique du
  Biome. Le seuil d’inondation dépend du Biome et de son futur état écologique
  (Semi-désert : 50/70/100 instable/stable/résilient). Une inondation enlève
  5 Vitalité à chaque nœud Organique une seule fois par session ; au-dessus du
  seuil, la Putréfaction applique ×0,90 à la régénération.
- **Déchets et Contamination.** Les Déchets sont des amas physiques finis :
  une Vitalité vaut un Déchet, zéro les supprime. Ils ont trois heures de
  grâce ; ensuite dix Déchets ajoutent une Contamination par résolution de
  quatre heures, avec reste décimal persisté. La Contamination est bornée
  0–100, réduit le socle et ralentit l’Organique. Une décontamination naturelle
  de −1/h ne fonctionne que si Biomasse >80 et Contamination <60 ; elle peut
  coexister avec des Déchets contaminants. Les déchets du Camp restent dans le
  stock du Camp et ne deviennent jamais des amas territoriaux par défaut.
  Un Arac, ou tout P’TIBUG portant le trait **Récupérateur**, résout son travail
  depuis les timestamps persistés : il nettoie d’abord les amas partagés, puis
  réduit la même Contamination lorsqu’il n’y a plus de Déchet exploitable. Son
  débit et sa fenêtre offline sont dans `ecologyV2.cleaners`; aucune jauge de
  toxicité parallèle n’est créée.
- **Nœuds et météo sévère.** Les nœuds organiques connus sont réhydratés dans
  la Lisière depuis `BiomeSharedState` après chaque résolution hors ligne. Une
  météo sévère peut détruire un nœud déjà épuisé suivant une probabilité
  Dashboard déterministe (hash de nœud/session, jamais hasard client). Après
  cinq jours à Biomasse suffisante, une recréation réutilise un emplacement
  organique détruit connu : elle ne peut donc pas apparaître au milieu d’un
  chemin. Les amas nettoyés gardent un tombstone à zéro afin de ne pas revenir
  lors de l’ouverture d’une autre projection locale.
- **Minéral et Mine.** Le Minéral de surface est fini, ne contamine pas
  directement et produit un Déchet tous les dix Minéraux extraits. Il ne crée
  plus de pression d’exploitation. La Mine utilise une réserve profonde finie,
  avec cadences Douce/Normale/Intensive : dix Minéraux profonds ajoutent un
  Déchet et une Contamination directe, ainsi que de la pression. Cette pression
  ne décroît pas seule et ne bloque aucun état écologique ; elle fournit un
  hook de tolérance au futur puzzle. L’API Mine accepte déjà un acteur manuel,
  P’TIBUG ou habitant et un marqueur d’automatisation, sans inventer de
  bâtiment ni de règle de déblocage.
- **Offline et affichage.** `resolveWorldcraftRegionUntil` résout maintenant
  les cinq Biomes avec le même état initial, la même météo horodatée et la
  même cible temporelle. Les effets irréversibles sont persistés dans la même
  transaction ou opération idempotente. L’interface joueur affiche des états
  qualitatifs ; le panneau extensible **DEV** de la Lisière montre les valeurs
  exactes. La scène 2D 3/4 varie déjà son voile visuel pour contamination,
  Biomasse faible et saturation d’eau.
  Toute extraction ou action de nettoyage résout aussi l’écologie avant sa
  transaction : une action tardive ne contourne jamais une météo, une
  contamination ou une régénération en attente.
- **Configuration.** `ecologyV2` est une section Dashboard séparée de la
  Biomasse V1 : courbes, seuils, plages d’Humidité, pluie, inondation,
  Déchets, Contamination, Minéral et Mine y sont versionnés et publiables.
  Le Dashboard affiche en haut à droite son repère de livraison
  `Dashboard V2.1.2 · Écologie physique 0.1` afin de vérifier visuellement
  que la version Hosting contient bien ce lot. Le repère est une version de
  l’interface, indépendante des valeurs publiées dans Firestore.
  Les assets CSS et JavaScript portent aussi ce numéro dans leur URL pour
  empêcher Safari de conserver une ancienne interface sans carte écologique.
  Le puzzle écologique, les espèces, Blocs stables, Recherche, Data, Tour et
  Walker restent explicitement hors périmètre.

## P’TIPOTE Élevage — Lot 14 : objets posés et expérimentation spatiale

- **Objet posé.** Les aliments, friandises et matériaux compatibles ne sont
  plus donnés directement. Le joueur les retire de `inventory.special` pour
  créer une instance persistée dans `sceneItemsByAlcoveId` : `instanceId`,
  `itemId`, `zoneId`, `placedAt`, `source: PLAYER` et compteur d’interactions.
  Un même objet ne peut donc jamais être à la fois dans l’inventaire et dans la
  scène. Tant qu’il n’a pas été consommé, il peut être récupéré sans perte.
- **Zones.** Chaque Alcôve possède quatre zones V0 : abri ombragé, nid
  central, coin humide et bord éclairé. Leurs valeurs relatives modifient
  localement Lumière / Température / Humidité sans inventer de degrés ou de
  pourcentages physiques. Les règles de zone sont définies dans
  `ElevageConfig.sceneZones`; elles complètent l’environnement global calculé
  à partir des installations.
- **Lecture différée.** À la première interaction, seule une icône de
  comportement est affichée. Les messages d’observation n’apparaissent qu’à
  partir du seuil `suspectedThreshold`; le Carnet conserve les observations
  dédoublonnées et leurs états UNKNOWN / SUSPECTED / CONFIRMED. Le Carnet
  reflète toujours le domaine, sans révéler une préférence inconnue.
- **Contexte.** Une racine favorite dans un coin très humide peut être
  déplacée vers une zone plus sèche (`MOVE_ITEM`) plutôt que consommée. Cette
  expérience produit une observation d’évitement d’humidité progressivement,
  sans transformer la position en préférence automatiquement confirmée.
- **Fiches d’installation.** `ElevageInstallationDefinition` porte désormais
  nom, description française, effets et production. Les fiches lisent aussi
  `ElevageRecipe` afin d’afficher coût réel de configuration, production et
  aperçu environnemental avant/après. Elles ne dévoilent aucune préférence
  d’un P’TIPOTE.

## P’TIPOTE Élevage — Lot 15 : boucle QA, micro-environnement et lecture différée

- **Reset QA isolé.** Les outils de développement peuvent réinitialiser la
  partie Élevage entière (état, Alcôves, individus, objets posés, productions,
  observations, sorties et notifications) ou les seules Alcôves. Ils ne lisent
  ni ne modifient jamais Zone 0. Une nouvelle partie repart avec les Alcôves
  configurées, aucun individu et le starter normal `ROOT ×1`, `LEAF ×1` ; les
  gros stocks restent réservés à `devMode`.
- **Inventaire V1.** L’inventaire joueur est une grille unique mobile de
  piles : nourriture, friandises, matériaux, ressources et composants y
  partagent la même présentation. La taille maximale d’une pile est
  configurable (`inventoryStackSize`, V0 : 12) : `ROOT ×28` devient donc
  `×12`, `×12`, `×4`. Poser un objet le retire de cette grille ; récupérer un
  objet le remet dans une pile disponible. Tous les loots de Mini-Lisière ont
  un libellé français, une icône provisoire et une catégorie ; « Objet inconnu »
  demeure seulement un garde-fou de données corrompues.
- **Placement mobile.** L’appui long fournit un aperçu d’objet et active le
  mode de pose : la feuille d’inventaire se ferme, puis un tap sur Z1–Z4 place
  l’objet. C’est le repli tactile robuste du prototype en attendant les sprites
  définitifs ; les zones mettent en évidence la pose sélectionnée et le flux
  conserve l’intention de glisser-déposer.
- **Cycle et zones.** Le cycle persistant est dérivé de l’heure réelle :
  `dayDurationHours + nightDurationHours` (V0 : 3 h + 3 h). Le jour, Z1 reste
  ombragée et Z4 lumineuse ; la nuit toutes les zones s’assombrissent, Z4
  restant la moins sombre. Chaque décision spatiale utilise le micro-
  environnement local `light`, `temperature`, `humidity` de la zone, pas le
  seul résumé global. Une installation affecte sa zone de pose (avec repli
  stable sur son slot pour les sauvegardes antérieures) ; elle ne diffuse pas
  encore vers les zones voisines.
- **Actions visibles.** Le placeholder du P’TIPOTE est volontairement petit
  afin de laisser lire les quatre bandes Z1–Z4. Son icône temporaire exprime
  `IDLE`, `EAT`, `STRUCTURAL_ABSORB`, `DISCOMFORT`, `SLEEP`, `CURIOUS`,
  `FOLLOW`, `CUDDLE`, `MOVE_ITEM` ou `METAMORPHOSIS`. Taper une zone vide le
  fait suivre (`FOLLOW`) ; taper le P’TIPOTE déclenche une caresse (`CUDDLE`).
  Ces interactions ne donnent que de faibles tendances de personnalité,
  limitées par les caps existants.
- **Observations réellement progressives.** Une entrée persistée sépare
  `rawBehaviorCount` de `meaningfulEvidenceCount`. Les preuves sont plafonnées
  par une fenêtre configurable (`observationEvidenceCooldownMinutes`, V0 :
  10 min) ou par un changement de contexte et n’augmentent plus une fois
  confirmées. L’ordre est strict : `OBSERVED` → `SUSPECTED` → `CONFIRMED`; une
  hypothèse est donc visible avant une découverte confirmée. Le texte joueur
  n’apparaît qu’après `observationTextThreshold` répétitions (V0 : 2) : le
  comportement/icône vient toujours avant son interprétation dans le Carnet.
- **Nourriture contextuelle.** Un objet favori placé dans une zone trop humide
  peut être observé, évité ou déplacé vers une zone plus sèche avant d’être
  consommé. `MOVE_ITEM` produit d’abord un comportement, puis une observation
  d’évitement de l’humidité à répétition. Le joueur conserve la récolte et la
  pose au stade Bébé ; les étapes ultérieures d’autonomie restent inchangées.

## P’TIPOTE Élevage — Lot 16 : comportement autonome et lecture de scène

- **Cycle autonome d’objet.** Un objet posé ne demande plus au joueur de
  cliquer « Observer ». La scène sélectionne une décision pure puis rend, dans
  cet ordre, `NOTICE_ITEM`, `APPROACH_ITEM`, `INSPECT_ITEM`, `THINK` et la
  décision (`EAT`, `STRUCTURAL_ABSORB`, `MOVE_ITEM`, `REJECT` ou `IGNORE`).
  Seule la décision finale mute le domaine ; les étapes intermédiaires restent
  une présentation temporaire. L’ancien déclencheur est conservé uniquement
  comme outil QA quand `devMode` est actif.
- **Cadence et variété.** Une réaction autonome est limitée par
  `autonomousReactionIntervalSeconds` (V0 : 60 s). Une réaction identique ne
  peut pas être choisie deux fois de suite lorsqu’une alternative existe. Les
  actions directes du joueur restent immédiates. Les P’TIPOTE font des pauses
  décoratives de `idlePauseSeconds` (V0 : 45 s) ; ils ne parcourent donc plus
  l’Alcôve toutes les quelques secondes.
- **Mouvement et actions.** Les positions sont les centres exacts de Z1 à Z4,
  permettant d’atteindre les objets aux extrêmes. Le mouvement normal est
  volontairement lent (`normalMoveDurationMs`, V0 : 1600 ms) ; fuite et
  déplacement urgent utilisent `runMoveDurationMs` (V0 : 400 ms). Les pictos
  provisoires rendent notamment marche, approche, inspection, réflexion,
  repas, absorption, refus, inconfort, fuite, suivi, câlin, repos et
  métamorphose sans introduire de sprites définitifs.
- **État et habitudes.** Les préférences confirmées restent visibles dans les
  habitudes du P’TIPOTE, mais ne produisent plus de notification autonome
  répétitive. Les observations textuelles continuent de prioriser les faits
  non résolus. Satiété, tempérament et, à partir d’Intermédiaire, structure
  ferrique sont regroupés dans le bloc **État**.
- **Faim de playtest.** Dans le preset `PROTOTYPE`, la satiété d’un Bébé se
  vide cinq fois plus vite que la cadence historique ; Intermédiaire est moins
  rapide et Mature reste lent. Le preset `TARGET` n’applique pas ce facteur de
  playtest. Cette vitesse modifie uniquement l’évaluation dérivée des
  timestamps, jamais les données de repas elles-mêmes.
- **Jour/nuit QA.** Le cycle reste de six heures (3 h Jour, 3 h Nuit) et la
  scène affiche l’état ainsi que le temps restant. En `devMode`, Forcer Jour,
  Forcer Nuit et Cycle réel sont des overrides de session : ils ne modifient
  pas la configuration ni les règles TARGET persistées. Une installation est
  toujours attachée à sa zone Z1–Z4 et n’a aucune diffusion V0 vers les autres
  zones. La palette des quatre bandes emploie désormais une teinte commune,
  déclinée uniquement par niveau de lumière.

## P’TIPOTE Élevage — Lot 17 : lecture spatiale et séquence comportementale

- **Migration QA d’inventaire.** `qaInventoryResetV17` est une migration locale
  et one-shot de la sauvegarde Élevage : les anciennes réserves de playtest
  sont remplacées une seule fois par le starter normal `ROOT ×1`, `LEAF ×1`.
  Aucun inventaire, profil ou état Zone 0 n’est lu ou modifié. Les resets QA
  existants créent déjà ce même starter minimal ; les outils dev restent
  volontaires et ne sont jamais injectés par la migration.
- **Lumière discrète et micro-zones.** Le jour est défini dans la configuration
  par Z1–Z4 : **2/5, 3/5, 3/5, 4/5**. La nuit applique des offsets centralisés :
  Z1–Z3 deviennent sombres et Z4 conserve une lumière résiduelle. Les quatre
  bandes partagent une teinte de base ; seule leur luminosité varie. Chaque
  slot d’installation est rendu dans sa propre zone Z1–Z4 et les effets restent
  strictement locaux, sans diffusion V0.
- **HUD environnemental.** Le HUD supérieur est la moyenne arithmétique des
  quatre zones, jamais la zone courante. Il ouvre le détail compact de Z1 à Z4.
  Le bloc **État** affiche séparément les valeurs de la zone actuellement
  occupée par le P’TIPOTE ; les décisions biologiques restent locales.
- **Confort Résonance.** Les seuils configurés V0 sont : lumière 1–2
  confortable, 3 neutre, 4 inconfortable, 5 fortement inconfortable. Ils
  produisent une lecture visuelle locale (sans fuir systématiquement une zone
  simplement imparfaite) et préparent les observations répétées. Une hypothèse
  de lumière peut proposer la piste « Essayez de lui proposer davantage
  d’ombre » ; une découverte confirmée expose alors la plage lisible
  1–2/5, neutre 3/5, inconfort 4–5/5.
- **File d’actions de scène.** Les événements `NEW_ITEM`, `FOLLOW` et `CUDDLE`
  sont mis en file. Une action atomique en cours termine avant la suivante :
  approche, inspection et réflexion se déroulent dans la zone de l’objet, puis
  finissent obligatoirement par un état lisible (`EAT`, `STRUCTURAL_ABSORB`,
  `MOVE_ITEM`, `REJECT` ou `IGNORE`). `THINK` n’est jamais un résultat final.
  Le Fer conclut notamment par l’icône d’absorption structurelle et la jauge
  ferrique garde sa source de vérité métier existante.

## P’TIPOTE Élevage — Lot 18 : confort local strict et ciblage

- **Lumière canonique.** Les valeurs locales sont configurées et discrètes :
  Nuit Z1–Z4 = **1 / 2 / 2 / 3** ; Jour = Nuit +1, soit **2 / 3 / 3 / 4**.
  La couleur de fond est indexée exclusivement sur Light 1–5 et une teinte
  commune : deux zones de même valeur sont donc toujours visuellement
  identiques. Le HUD conserve une moyenne arithmétique, arrondie au plus
  proche.
- **Confort local.** Résonance classe séparément lumière, température et
  humidité en `IDEAL`, `GOOD`, `NEUTRAL`, `BAD`, `EXTREME`. Le pire axe domine
  le résultat local ; une humidité 5/5 ne peut jamais être masquée par deux
  axes favorables. Le bloc État présente une jauge informative de confort
  global, tandis que la scène décide exclusivement avec la zone courante.
  `BAD` déclenche une fuite lisible à vitesse ×2 et `EXTREME` une fuite ×3.
- **Installations et recettes.** L’Abri minéral profond conserve ombre et
  fraîcheur mais augmente désormais l’humidité de **+1** seulement. Les slots
  restent Z1↔slot1 à Z4↔slot4. Le Bio-fabricateur contraint
  ses libellés sur mobile et affiche une phrase italique dérivée des impacts
  configurés, en plus des valeurs numériques de la fiche.
- **FOLLOW et actions ciblées.** Maintenir une zone trois secondes lance un
  FOLLOW en file ; relâcher avant annule. Une fois arrivé, le confort local est
  évalué comme pour toute autre arrivée. Les événements de nouvel objet
  conservent l’`instanceId` exact de l’objet posé jusqu’à la décision ; un item
  récupéré annule son propre événement, sans substitution par un autre objet
  présent dans l’Alcôve.
- **Câlin.** Si le doigt est encore maintenu à l’arrivée après un FOLLOW, le
  câlin démarre automatiquement. Sa durée est bornée à 1–5 secondes et reste
  enregistrée comme contexte de l’interaction (`lastCuddleDurationMs`) ; elle
  n’ajoute aucune sanction et utilise toujours l’axe Contact existant.

## P’TIPOTE Élevage — Lot 19 : personnalité, demandes et sommeil

- **Personnalité comportementale.** Les axes `initiative`, `contact` et
  `tempo` restent déterministes à l’adoption, puis guident initiative,
  proximité sociale et cadence d’action. La répartition V0 est provisoire :
  **50 %** baseline, **25 %** expériences Bébé, **15 %** expériences
  Intermédiaire et **10 %** plasticité adulte. **Point à arbitrer :** chaque
  axe pourra recevoir une pondération propre — initiative davantage façonnée
  par l’expérience, contact plus inné, tempo intermédiaire. Cette répartition
  n’est donc pas une règle canonique définitive.
- **Bulle et wellbeing.** Le placeholder principal du P’TIPOTE reste visible :
  les intentions temporaires (`?`, nourriture, absorption, inconfort,
  affection, sommeil…) sont rendues par une petite bulle au-dessus de lui.
  `wellbeing` est un état interne borné, sans jauge joueur ; il reflète la
  cohérence entre besoin, confort, repos, proximité et tempérament sans jamais
  modifier les apports nutritifs ou structurels. L’expression positive varie
  avec Contact : chaleureuse et démonstrative, ou réservée et discrète.
- **Câlins.** Un cooldown social persistant protège de l’insistance. Sa durée
  est plus courte pour un tempérament chaleureux et plus longue pour un profil
  réservé. Une première tentative trop tôt est neutre ; l’insistance immédiate
  produit une irritation et une baisse temporaire de wellbeing, jamais une
  pénalité ou une modification permanente de personnalité. Les câlins restent
  classés court (1–2 s), normal (2–3 s) et prolongé (4–5 s).
- **Need ≠ Request.** Un besoin reste une donnée interne. Une `activeRequest`
  temporaire n’est créée que lorsque le P’TIPOTE choisit de solliciter le
  joueur ; une seule est visible, expire, est résolue ou est abandonnée. Bébé
  utilise le signal non précis configurable « Pti ? », Intermédiaire une
  catégorie (nourriture, structure, contact, sommeil…), Mature peut préciser
  un objet connu. Un individu autonome tente d’abord les stocks locaux, là où
  un profil accompagné sollicite plus volontiers le joueur.
- **Sommeil extensible.** Les rythmes utilisent une liste de `sleepWindows`,
  donc acceptent plusieurs repos par cycle. Végétal est diurne ; Minéral
  (Résonance) est `SHIFTED_DIURNAL`, endormi de fin de nuit jusqu’au début du
  jour ; Champignon est biphasique/polyphasique. Le cycle V0 est de six heures
  (Jour 4 h, Nuit 2 h). Durant `SLEEP`, le P’TIPOTE reste immobile et choisit
  la meilleure zone locale selon son confort. Le hook `PLAYER_PROXY_OBJECT`
  est réservé à la future Poupée familière ; attachement/fidélité demeure un
  système distinct, hors scope.
- **Production locale.** Les installations productives produisent une unité
  toutes les **3 h** (`productionIntervalSeconds`) et chaque sortie locale est
  plafonnée à **6** (`productionMaxStock`). Une récolte transfère une seule
  unité à la fois du stock local vers l’inventaire ; le joueur peut donc laisser
  des ressources à l’individu. Bébé dépend de cette aide manuelle ;
  Intermédiaire et Mature utilisent progressivement ces stocks selon leur
  initiative.

## P’TIPOTE Élevage — Lot 19.5 : environnement et préhension

- **Audit humidité et modèle explicite.** La cause des anciens 5/5 inattendus
  était un reliquat de décor dans la configuration des zones : `ZONE_3`
  portait `humidity: +2` même sans installation. Les bases sont désormais
  explicites et configurables (`baseHumidity`), les zones décoratives ne les
  modifient plus, et le domaine peut exposer un diagnostic dev par zone
  (base, contribution locale, diffusion, température jour/nuit et final).
  Aucun clamp intermédiaire ne masque une contribution ; l’échelle 1–5 est
  appliquée seulement à la présentation après la somme complète.
- **Diffusion locale.** Humidité et température suivent la même règle : un
  effet de magnitude 1 reste dans sa zone ; une magnitude 2 conserve son
  effet principal et transmet ±1 à chaque voisine immédiate. Ainsi le Bassin
  `+2` humidifie localement et `+1` les voisines ; Ventilation vaut maintenant
  humidité `-2`, le Trou géothermique chaud `-1`, et l’Abri minéral profond
  reste à `+1`.
- **Température.** La base est 2/5 partout ; le Jour ajoute +1 et la Nuit
  revient à la base. Une forte ombre retire localement un niveau, dans le
  domaine et non dans la vue. Les installations thermiques de magnitude 2
  diffusent donc également ±1 aux zones adjacentes.
- **Fuite intelligente et préhension.** `findBestSafeZone()` score toutes les
  zones accessibles par confort local (lumière, température, humidité et
  profil de Nature), exclut la zone problématique quand possible et tranche
  de façon déterministe. Le P’TIPOTE ne revient donc pas mécaniquement à sa
  zone précédente. Bébé ne transporte rien ; Intermédiaire peut porter les
  ressources libres simples et structurelles ; Mature peut porter tous les
  objets libres compatibles. Installations, mobilier ancré et structures sont
  exclus de cette préhension.
- **Séquence atomique.** Pour une ressource intéressante située dans une zone
  `BAD` ou `EXTREME`, la file conserve l’`instanceId` : approche, `PICKUP`,
  sélection de zone sûre, `FLEE_WITH_ITEM`, puis consommation/absorption ou
  conclusion. Une zone extrême raccourcit l’inspection, mais n’abandonne plus
  automatiquement le Fer, la Racine ou une autre ressource portable.
- **Carte État.** L’ordre joueur est désormais faim/satiété, tempérament,
  structure ferrique, puis un seul bloc réunissant confort global informatif
  et ressenti de la zone actuelle. Le comportement reste toujours fondé sur le
  confort local, jamais sur la moyenne. **Point à arbitrer futur :** passer de
  une à deux installations par zone afin d’enrichir le contrôle local.

## P’TIPOTE Élevage — Lot 19.6 : communication et réveil

- **Trois lectures simultanées.** Le placeholder/sprite principal ne change
  jamais pour devenir une émotion : mouvement et position décrivent l’action,
  une bulle compacte affiche son picto, et une vocalisation exprime la
  réaction. Les onomatopées configurables V0 sont notamment `Pti ?` (curiosité),
  `Mm !` (absorption), `Prr !` (contentement), `Nnh…` (inconfort), `Ptik !`
  (surprise), `Nh !` (refus) et `Pti !` (appel). Une réaction usuelle reste
  visible au plus 7 s ; une absorption structurelle jusqu’à 20 s, avec l’icône
  de la ressource concernée.
- **Réglage Dashboard.** La section « Voix et onomatopées » du Dashboard
  Élevage permet de modifier localement chaque famille (curiosité, absorption,
  contentement, inconfort, surprise, refus, appel). Les valeurs sont validées,
  persistées avec les overrides de configuration et ne peuvent pas être vides.
- **Langage par stade.** Bébé demeure non verbal : picto d’action et
  onomatopée uniquement. Intermédiaire apprend catégorie par catégorie : un
  profil réservé utilise une onomatopée aux trois premières occurrences puis
  un mot à la quatrième ; un profil chaleureux aux cinq premières puis à la
  sixième. Mature peut employer immédiatement un mot précis déjà connu (par
  exemple « Fer » ou « Racine »), tout en gardant parfois une vocalisation.
- **Interruption naturelle.** Les événements n’annulent pas une action en
  cours : ils réduisent sa durée restante, puis attendent la file. Pour un
  nouvel objet, Bébé Posé retire 4 s et Bébé Spontané 6 s ; Intermédiaire et
  Mature retirent respectivement 2 s et 3 s. Pour une sollicitation de câlin,
  Bébé Autonome retire 4 s et Accompagné 6 s ; les stades suivants retirent
  2 s ou 3 s. `PICKUP`, `FLEE_FAST` et les transitions critiques restent
  atomiques.
- **Réveil consenti.** `LongPressProgressInteraction` est commun à FOLLOW et
  WAKE : un appui maintenu configurable (3 s par défaut) sur un P’TIPOTE
  endormi crée une demande de réveil ; un tap bref ne le réveille jamais.
  Le réveil passe par la file d’actions. Un Posé reprend plus lentement et
  tolère moins les réveils répétés ; un Spontané réagit plus vite. Ces réveils
  affectent seulement le wellbeing temporaire.
- **Humidité de départ.** La baseline globale est désormais **2/5**
  (`baseHumidity: 2` dans l’échelle métier directe). Sans
  installation, l’Alcôve Résonance est viable ; +1 local donne 3/5, +2 donne
  4/5. Le niveau 5/5 nécessite donc une combinaison explicite d’effets et ne
  survient plus dans l’environnement standard.

## P’TIPOTE Élevage — Lot 20 : habitat appropriable

- **Trois catégories.** Une `STRUCTURE` reste dans son slot technique Z1–Z4,
  modifie l’environnement et n’est jamais déplacée par le P’TIPOTE. Un
  `MEUBLE` est une station d’activité libre ; une `DECORATION` est un petit
  objet libre. Meubles et décorations sont conservés dans l’inventaire
  d’habitat puis placés dans une zone, où plusieurs instances peuvent coexister.
  Bébé ne les transporte pas ; Intermédiaire transporte les décorations ;
  Mature peut aussi transporter les meubles explicitement compatibles.
- **Formations de résonance.** Les anciennes géodes structurelles sont
  migrées/affichées comme Formation minérale, métallique ou cristalline. Elles
  ne produisent jamais Fer, Quartz ou Calcaire : elles soutiennent une action
  `RESONATE`, lente, persistante et non destructive. Les ressources libres
  restent absorbables et consommées immédiatement. Les recettes de Formation
  demandent donc leurs composants spécifiques (Fer, Quartz, Calcaire).
- **Mobilier et décor.** Le catalogue V0 contient Hamac, Nid/couchette,
  Potager vertical, Litière fongique, Bac à gravier, Bibliothèque Databug et
  Parcours d’obstacles, ainsi que plantes, mousse, cristal, géode, pierre,
  carillon et conque décoratifs. Le Bio-fabricateur sépare Structures, Meubles
  et Décorations et détaille les composants spécifiques.
- **Stations d’activité.** Un meuble ne produit jamais de ressource : il
  déclenche une activité courte et peut améliorer légèrement le wellbeing.
  Hamac/Nid et Bibliothèque sont davantage sélectionnés par un Posé ; le
  Parcours d’obstacles par un Spontané. Une station libre peut être activée
  par le joueur ou choisie pendant un cycle autonome avec son `instanceId`.
- **Recettes pilotables.** Dans le Dashboard Élevage, chaque recette conserve
  ses coûts séparés Organique et Minéral puis expose une liste de composants
  spécifiques éditable : Racine, Feuille, Mousse, Algues, Champignon, Fruit,
  friandises, Fer, Calcaire, Quartz, Graine, Pousse et Fragment d’algue. Le
  designer choisit un composant par ligne et sa quantité ; plusieurs lignes
  sont possibles. La validation bloque les IDs inconnus et les quantités
  nulles ou négatives, et les overrides restent séparés de la sauvegarde.
- **Effets d’habitat pilotables.** Le Dashboard expose les effets propres à
  chaque objet : une **Structure** peut régler localement Lumière,
  Température et Humidité ; un **Meuble** ou une **Décoration** règle seulement
  son impact de wellbeing lors d’une interaction positive. Les affinités de
  décoration, activités et préférences individuelles restent volontairement
  dans le domaine : elles ne sont ni visibles ni réglables dans le Dashboard.
  Les valeurs sont validées entre -5 et +5, persistées comme overrides de
  configuration, séparés de la sauvegarde de jeu.
- **Affinités.** Au premier contact d’une décoration, un jet déterministe lié
  à l’individu est persisté par instance de décoration. Résonance favorise
  Cristal (80 %)
  et Minéral (70 %), les autres groupes partent à 50 % ; une affinité déjà
  appréciée dans le même groupe ajoute une unique fois +20 points, plafonnée à
  100. Tempo module les catégories musicales douces/énergiques. Une décoration
  aimée donne seulement un léger wellbeing, sans pénalité durable si elle ne
  plaît pas.
- **Séjour et environnement.** Les valeurs finales Lumière, Température et
  Humidité sont désormais des données métier **0–5**, clampées après tous les
  effets : jamais négatives, jamais au-delà de 5. Les baselines sont 2/5.
  Le séjour neutre est configurable : Bébé 30 s, Intermédiaire 20 s, Mature
  25 s ; Posé +5 s, Spontané -5 s, zone idéale +10 s, mauvaise -10 s,
  extrême -20 s, avec un minimum absolu de 3 s. **Point à arbitrer futur :**
  passer de une à deux Structures par zone. `RELATIONAL_OBJECT` reste le hook
  réservé à la future Poupée familière.

## P’TIPOTE Élevage — correctifs cycle, formations et cristallisation

- **Formations de résonance.** Formation minérale, métallique et cristalline
  ne possèdent pas de production locale et ne peuvent donc ni générer ni
  récolter Calcaire, Fer ou Quartz. Les anciens `productionState` de ces
  structures sont retirés à la lecture et au rafraîchissement de l’Alcôve.
  Elles restent des points de connexion : la résonance structurelle augmente
  la jauge du P’TIPOTE sans détruire la Formation. La Culture potagère et la
  Butte d’arbuste restent productives.
- **Horloge et hors-ligne.** Les calculs Élevage (cycle Jour/Nuit, sommeil,
  faim et maturations) utilisent une horloge calibrée sur un horodatage
  Firestore quand un compte est connecté. Son décalage est mis en cache, puis
  l’horloge réelle continue de progresser application fermée. En absence de
  réseau ou d’autorisation Firestore, le dernier décalage calibré est conservé
  et l’horloge locale sert de repli temporaire.
- **Rythme minéral.** Résonance utilise deux fenêtres de sommeil extensibles :
  il dort de la seconde moitié de nuit jusqu’au début du Jour. Avec Jour 3 h
  et Nuit 1 h, son réveil se produit vers 2 h 30 de Jour. Les autres profils
  gardent leurs fenêtres propres.
- **Cristallisation.** Lorsqu’une métamorphose est disponible, le P’TIPOTE
  reste immobile, prend l’icône cristal pulsante et signale régulièrement `…`.
  Le joueur ouvre ensuite la séquence rythmique en le touchant. En mode dev,
  un bouton « Debug · lancer l’évolution » est affiché sous la satiété pour
  lancer exactement cette même séquence. Le pictogramme normal de réflexion
  est désormais `?` ; les ellipses sont réservées à l’attente/cristallisation.
- **Lecture de scène.** Les cartes de confort interpolent toujours le nom de
  l’occupant de l’Alcôve, jamais « Faradet » en dur. Le même anneau d’appui
  long est utilisé pour FOLLOW et WAKE, avec un diamètre de 76 px et un trait
  de 6 px afin de rester visible sous le doigt. Taper une zone sans objet en
  cours de placement ne sélectionne plus de zone ni ne filtre sa couleur.

## P’TIPOTE Élevage — Lot 20.5 : matrice écologique des Natures

- **Échelle environnementale canonique.** Lumière : `0` est l’absence totale
  de lumière et `5` la lumière directe maximale. Humidité : `0` correspond à
  0 % et `5` à 100 %. Température : `0 = -20 °C`, `1 = 0 °C`, `2 = 25 °C`,
  `3 = 35 °C`, `4 = 50 °C`, `5 = 120 °C`. L’interface conserve l’échelle
  ludique 0–5 ; ces équivalences servent à l’équilibrage et aux diagnostics.
- **Matrice générique.** Une `ElevageNatureProfile` configure, pour chaque
  Nature, un optimum (`preferredLight`, `preferredTemperature`,
  `preferredHumidity`) et trois courbes de six valeurs. Chaque valeur renvoie
  `IDEAL`, `GOOD`, `NEUTRAL`, `BAD` ou `EXTREME`. Le pire axe détermine le
  confort local : aucune moyenne ne masque une contrainte extrême.
- **Trois Natures testables.** Résonance (Minéral) a l’optimum `3/4/2` et
  privilégie la chaleur ; Photosynthèse (Végétal), archétype cactus/batterie
  biologique, a l’optimum `5/3/2` et privilégie la lumière ; Décomposition
  (Fongique), archétype champignon forestier, a l’optimum `1/2/4` et
  privilégie l’ombre humide. Ainsi, `2/2/2` n’est pas un optimum universel.
- **Autonomie et sommeil.** `findBestSafeZone`, le choix du spot de sommeil,
  la fuite, le transport d’objet et le confort affiché consultent le profil
  de l’individu actif. Les profils circadiens restent respectivement diurne,
  minéral décalé et fongique biphasique. Les trois Natures sont créables via
  les actions de test du flow Élevage et utilisent des placeholders visuels
  distincts.
- **Habitat.** Les stations gardent leur logique existante, avec une affinité
  écologique supplémentaire : Potager vertical pour Photosynthèse, Litière
  fongique pour Décomposition, Bac à gravier pour Résonance. Les décorations
  végétales/mousse favorisent les deux premiers profils ; cristal/minéral
  favorisent Résonance. Les affinités restent internes au domaine.
- **Dashboard.** La section « Matrice écologique des Natures » rend éditables
  les trois optimums et les 18 points de courbe de chaque profil ; les
  overrides sont validés et persistés avec la configuration Élevage, sans être
  affichés comme une révélation au joueur.
- **Natures futures — archétypes seulement.** `VEGETAL_POISON` : algues ou
  sargasses résistantes / conversion de déchets ; `VEGETAL_GROWTH` : plante
  tropicale de croissance ; `FUNGAL_FILTRATION` : champignon extrêmophile
  marin ou des grands fonds ; `FUNGAL_CONTROL` : champignon associé à des
  insectes ou animaux ; `MINERAL_PROTECTION` : cristallin structurel ;
  `MINERAL_CALCIFICATION` : calcification biologique type coquille.
  **Point à arbitrer :** leurs courbes détaillées ne sont pas canonisées et
  elles ne sont pas encore jouables.

## P’TIPOTE Élevage — portage Lots 20.75 et 20.9

- **Production biologique.** Culture potagère (Racine/Feuille), Butte
  d’arbuste (Fruit) et Support fongique (Champignon) ont des sorties
  indépendantes : quantité, intervalle, plafond local et activation sont
  configurables dans le Dashboard. Le plafond d’une sortie n’interrompt pas
  les autres sorties du même producteur.
- **Résonance par Type.** Les Formations minérales restent non productives.
  Le Bosquet symbiotique permet la résonance végétale, et la Colonie
  mycélienne la résonance fongique ; ces structures restent intactes. Les
  objets minéraux libres conservent l’absorption directe spécifique aux
  Minéraux. `SPORE` est une ressource inventaire et un loot Lisière futur,
  non une production infinie de l’Alcôve. Les recettes exactes des nouvelles
  structures restent un point d’équilibrage à arbitrer.
- **Onboarding écologique.** Une adoption commence avec
  `onboardingAwakeLock`, qui suspend le sommeil jusqu’à la première
  interaction volontaire dans l’Alcôve. Les résidents historiques sont
  considérés comme déjà onboardés. La carte État ne diagnostique plus chaque
  zone : un P’TIPOTE exprime son inconfort dans la scène.
- **Recherche locale.** Un Bébé confronte d’abord une zone adjacente et garde
  une mémoire temporaire des zones rejetées ; il ne reçoit pas de GPS direct
  vers l’optimum. Une zone extrême conserve le repli sûr, avec priorité à une
  zone favorite ou sûre connue lorsqu’elle est disponible. Les signaux
  environnementaux sont dérivés de la courbe réelle de Nature : Résonance à
  `3/3/2` peut ainsi signaler qu’il recherche davantage de chaleur.
# Lot 21.0 — Réserve commune et Recycleur V1

- La **Réserve du Refuge** est l'unique stock économique portable Élevage :
  ressources spécifiques, Organique, Minéral et Bio-piles. Elle est commune à
  toutes les Alcôves.
- Restent locaux : instances d'objets posés (`placedItemInstanceId`), meubles,
  décorations, structures et leurs stocks de production, ainsi que tout objet
  actuellement porté par un P'TIPOTE.
- La migration `sharedReserveMigrationV21` absorbe une fois les éventuels
  inventaires historiques portés par des Alcôves, puis retire ces champs. Les
  objets de scène et stocks producteurs ne sont jamais transférés.
- Les producteurs gardent leurs stocks physiques locaux ; une récolte unitaire
  les transfère vers la Réserve.
- Le Recycleur V1 agit seulement depuis la Réserve. Une ressource spécifique
  recyclable devient une matière terminale : organique ou minérale. Les règles
  par item (`recyclable`, `recycleOutputType`, `recycleOutputQuantity`) vivent
  dans la configuration et sont sérialisées pour une édition Dashboard future.
- V1 : Fruit, Racine, Feuille, Graine, Spore, Mousse, Champignon, Algues,
  Fragment d'algue et Pousse donnent 1 Organique ; Fer, Calcaire et Quartz
  donnent 1 Minéral. Organique et Minéral ne sont pas recyclables.
- Les objets libres posables sont validés par `placeableSceneItems`. Fruit,
  nourriture, friandises et matériaux compatibles créent une instance physique
  cible exacte ; Graine et Spore restent non posables tant qu'elles n'ont pas
  de comportement de scène.
- Limites V1 : pas de recyclage de structure/meuble/décoration, pas de
  démontage à récupération partielle, pas d'énergie ni de Lisière V2.
- Les fenêtres de sommeil sont configurables dans le Dashboard en minutes :
  nuit végétale, début de jour et fin de nuit minéraux, puis deux phases
  fongiques. Elles sont ancrées à leur période biologique et persistent dans
  la configuration ; une durée Jour/Nuit modifiée ne laisse donc plus un
  sommeil exprimé en fractions fixes du cycle.
