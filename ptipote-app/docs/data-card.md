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
- Les ressources organiques se régénèrent uniquement par le futur crochet de
  Biomasse ; les filons minéraux ont des couches finies et ne réapparaissent
  jamais. Les Déchets sont des nœuds finis distincts. Les rendements conservent leur fraction persistante entre deux
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
  Worldcraft 0 ne définit volontairement aucune formule de biomasse,
  contamination ou écologie : il prépare leur autorité partagée sans inventer
  leur gameplay. Un Camp garde le même identifiant en mode Active ou Autonome.
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
- La Lisière utilise la seed persistante de chaque Biome pour ses graphes de
  Parcelles. Son aperçu est un rendu local 2D à profondeur 3/4 : sol,
  accessoires, nœuds et êtres sont une projection lisible, non un terrain
  mondial synchronisé. Les hooks météo, écologie et trouvailles sont des
  données sans formules de gameplay à ce stade.
