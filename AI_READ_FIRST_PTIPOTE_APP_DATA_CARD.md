# AI READ FIRST - PTIPOTE App Data Card

## Recettes Craft - 2026-07-19

- Les recettes sont publiées dans `gameConfigs/zone0.zone0Settings.craft.recipes`. `ingredients` est une liste de un à trois éléments : ressources (`Organique`, `Minéral`, `Débris`, `Eau`) ou objets déjà fabriqués, par exemple `Filtre` ou `Repas simple`.
- Le Dashboard Craft affiche toutes les recettes dans des menus déroulants homogènes. Les choix d'ingrédients incluent les résultats des recettes actuelles, afin de composer des objets plus avancés sans modifier de JSON.
- `FoodType` est supprimé du modèle Flutter et du Dashboard. Le seul état métier de consommation est `isConsumable`; faim et vitalité restent configurables pour les objets consommables.

## Météo et Marché - 2026-07-19

- Les annonces météo sont publiées dans `gameConfigs/zone0.zone0Settings.towerOperations.weatherEvents`. Chaque entrée contient `label`, `description`, `announcement`, durée, préavis et poids de tirage. La Tour est un panneau d'information : elle ne consomme plus aucun objet et son bouton ouvre directement l'onglet **Météo** du Kernel.
- Les modèles de missions météo se règlent dans `gameConfigs/zone0.zone0Settings.kernel.missions` (`type: weather`). Les récompenses, y compris `bioBatteryReward`, sont éditables comme les autres missions. `weatherDemandOptions` est une liste d'objets alternatifs : l'un d'eux est tiré à chaque alerte, puis sauvegardé dans `users/{uid}/game/zone0.weather.alerts` avec sa quantité exacte.
- La quantité demandée est calculée au début de l'alerte : quantité de base + palier de population + niveau du Cœur du Camp + un supplément aléatoire de 0 ou 1. Elle ne varie donc pas pendant l'événement.
- `market.saleIntervalPopulationImpactPercent` est le coefficient de population appliqué à la fréquence d'achat. `100` conserve le comportement normal ; `0` désactive l'effet population. Le niveau du Marché continue de réduire le délai selon `saleIntervalReductionPerLevel`.

## Correctifs Kernel, opérations et production - 2026-07-18

### Notifications Kernel

- `ptipote-app/lib/features/game/zone0_game_state.dart` ajoute `viewedKernelMissionIds`, persisté dans `zone0Runtime.kernel.viewedMissionIds`. `unreadKernelMissionNotificationCount()` compte les missions actives encore non consultées et `markKernelMissionsViewed()` est appelé à l'ouverture du Kernel.
- Une mission Kernel qui devient active envoie une notification Firestore unique de type `kernel_mission`. Les IDs notifiés sont sauvegardés dans `zone0Runtime.kernel.notifiedMissionIds`, ce qui évite les doublons au redémarrage.
- `ptipote-app/lib/features/game/refuge_page.dart` : la pastille du bâtiment Kernel disparaît après consultation ; les notifications `kernel_mission` sont alors marquées comme lues. Les onglets Mission principale, Demandes et Météo gardent une pastille tant que leurs missions sont actives.

### Maison, Couveuse et Tour

- La Maison possède un bouton tableau de bord indiquant l'activité, le bâtiment ou la mission associée et le temps restant de chaque P'TIPOTE.
- La Couveuse utilise trois séquences de pulsations visuelles de 90 ms. Les syllabes `Pa` / `Ta` sont supprimées : le joueur observe puis tape en rythme. Les intervalles acceptent une tolérance de 1,25 s autour du battement attendu; un retour haptique moyen confirme l'éclosion réussie.
- La Tour sépare les opérations actives en trois lignes : ronde dans le camp, ronde dans les biomes et exploration.

### Fablab, Générateur et Recycleur

- Générateur niveau 1 : quatre paliers (20 Organique et 4 Minéral), soit 5 Organique + 1 Minéral par bio-batterie.
- Recycleur : cuve initiale de 50 Déchets et réserve de sortie initiale de 50 unités, transférable vers le stock global.
- Le Fablab affiche un accès inventaire sur tous les onglets, une jauge d'énergie bleue/orange, et le Recycleur utilise une jauge verticale de déchets avec les sélecteurs `+1`, `+5`, `+10` et `Max`.

### Composant commun de production

- `ptipote-app/lib/features/game/refuge_page.dart` centralise l'affichage des recettes dans `_ProductionRecipeCard`. Cuisine, Atelier et Nurserie P'TIBUG partagent maintenant les mêmes éléments : coûts, stocks Maison, prérequis, durée, nombre maximal de productions disponibles et actions.
- Les besoins sont affichés sous la forme `requis / stock Maison`. Le résumé `Créations possibles avec le stock` est calculé à partir de la ressource limitante.
- Le résultat reste volontairement spécifique au domaine : Cuisine et Atelier créent des objets d'inventaire via leurs ordres de craft ; la Nurserie appelle `Zone0GameState.startPTibugCreation`, qui fabrique désormais une Armature avant la Cultivation. Aucun P'TIBUG n'est converti en item de stock.

### Préparé / limites V1

- La fabrication d'Armature emploie le moteur sauvegardé (`startPTibugCreation`) et les coûts configurables Organique / Minéral / Bio-batterie de l'ancienne recette ; la Cultivation gère ensuite ses réserves locales continues. `futureMyceliumCost` reste éditable dans le Dashboard pour les futures espèces, mais n'est pas consommé par les créations V1.
- Les pulsations d'éclosion sont une aide visuelle de prototype, sans piste audio native.
- Les notifications Kernel sont in-app. Les notifications système iOS/Android restent hors périmètre Zone 0 V1.
- `HomePage(enableFirebaseServices: false)` est le mode de test isolé : les flux de profil et notification renvoient des valeurs vides sans initialiser Firebase. Le widget test couvre ce fallback.

Derniere mise a jour: 2026-07-18

Ce document est la carte de navigation rapide pour les IA qui travaillent sur l'application Flutter PTIPOTE. Lis ce fichier avant d'ouvrir le code: il indique ou vivent les fonctions, les flux importants, les collections Firestore et les fichiers a modifier selon la demande.

## Regle De Contexte

- Repo de travail a utiliser: `/Users/kevinjeanne/Dev/ptipote-webapp-1`
- App Flutter: `ptipote-app/`
- Webapp publique NFC: `ptipote-webapp/`
- Dashboard interne: `ptipote-dashboard/`
- Prototype web Zone 0 local: `ptipote-app/ptipote-game/`
- Handoff produit Zone 0 V1: `PTIPOTE_Zone0_Codex_Handoff_Prototype_V1_Local_v3.docx` dans la documentation locale.
- Ne pas utiliser l'ancien dossier cloud `Documents/Documents - MacBook Air (2)/...` comme source de verite.
- Ne pas toucher aux fichiers sales non lies a la demande. Les logs Flutter peuvent exister sans etre a committer.

## Architecture App

| Zone | Fichier principal | Role |
| --- | --- | --- |
| Demarrage Flutter | `ptipote-app/lib/main.dart` | Initialise Firebase, notifications push, theme controller, lance `PtipoteApp`. |
| Routes et app shell | `ptipote-app/lib/app.dart` | Declare les routes Flutter et les themes clair/sombre. |
| Theme UI | `ptipote-app/lib/core/theme/app_theme.dart` | Couleurs, typo, boutons, cartes, AppBar. Modifier ici pour les changements globaux de style. |
| Mode clair/sombre | `ptipote-app/lib/core/theme/theme_controller.dart` | Stocke et expose `ptipoteThemeMode`. |
| Auth gate | `ptipote-app/lib/features/auth/auth_gate.dart` | Bascule entre login et home selon Firebase Auth. |
| Connexion/creation compte | `ptipote-app/lib/features/auth/sign_in_page.dart` | Login Google, email/password, creation compte. |
| Accueil | `ptipote-app/lib/features/home/home_page.dart` | Boutons Mes PTIPOTES, scan figurine, shop, chat, menu profil, badges de notifications. |
| Mes PTIPOTES | `ptipote-app/lib/features/figurines/figurines_page.dart` | Liste inventaire, drag/reorder, renommage, transfert, demandes entrantes, refresh. |
| Modele figurine | `ptipote-app/lib/features/figurines/ptipote_figurine.dart` | Structure Dart d'une figurine, champs calcules, locks/cooldowns. |
| Config stats PTIPOTE | `ptipote-app/lib/features/figurines/ptipote_stats_config.dart` | Valeurs V1 centralisees: vitalite, bonheur, XP, EVG, modificateurs type/enveloppe, etats. |
| Image figurine | `ptipote-app/lib/features/figurines/ptipote_image.dart` | Resolution et affichage des images PTIPOTE. |
| Scan NFC | `ptipote-app/lib/features/nfc/nfc_page.dart` | UI scan, decodage NDEF, adoption, confirmation transfert, carte debug/dev. |
| Profil et roles | `ptipote-app/lib/features/profile/profile_page.dart` | Profil eleveur, panneau admin pour assigner le role dev. |
| Amis | `ptipote-app/lib/features/friends/friends_page.dart` | Recherche profils, invitations, accept/refuse/cancel. |
| Liste chats | `ptipote-app/lib/features/chat/chats_page.dart` | Liste des conversations et badges messages. |
| Conversation chat | `ptipote-app/lib/features/chat/chat_page.dart` | Messages entre deux amis. |
| Jeu / refuge Flutter | `ptipote-app/lib/features/game/refuge_page.dart` | Ecran dev du refuge joueur, accessible par bouton Jeu sur Home si `canSeeDiagnostics`. |
| Config Cœur du Camp | `ptipote-app/lib/features/game/camp_heart_config.dart` | Stades Camp/Refuge/Bourgade/Village/Petite ville, XP, population, confort P'TIPOTES, bonheur refuge, deblocages. |
| Assets jeu Flutter | `ptipote-app/ptipote-game/image_game/` | Images d'ecran du jeu, resolues par nom sans dependance a l'extension. |
| Prototype web Zone 0 | `ptipote-app/ptipote-game/` | Vertical slice HTML/CSS/JS mobile-first du refuge: Ilot, P'TIPOTES, Journal, Lisiere, Atelier, Tour, Marche, Maison. |
| Config dashboard stats PTIPOTE | `ptipote-dashboard/ptipote-stats-config.json` | Miroir JSON editable/exportable depuis le panneau dashboard `Stat Ptipote`. |
| Config dashboard Cœur du Camp | `ptipote-dashboard/camp-heart-config.json` | Miroir JSON des paliers du Cœur du Camp, visible/exportable dans le dashboard. |

## Services App

| Service | Fichier | Responsabilite |
| --- | --- | --- |
| Figurines et transferts | `ptipote-app/lib/services/figurine_service.dart` | Source principale pour lire/ecrire inventaire, publicFigurines, adoption, rename, transfert, confirmation transfert. |
| NFC physique | `ptipote-app/lib/services/nfc_service.dart` | Lecture NFC native via `nfc_manager`, diagnostic brut, UID, payload. |
| Profil utilisateur | `ptipote-app/lib/services/user_profile_service.dart` | Cree/synchronise profil, publie `publicProfiles`, roles `user/dev/admin`. |
| Amis | `ptipote-app/lib/services/friend_service.dart` | Recherche utilisateurs, invitations, liste amis. |
| Notifications Firestore | `ptipote-app/lib/services/notification_service.dart` | Cree/lit/clear les notifications in-app par type. |
| Push FCM | `ptipote-app/lib/services/push_notification_service.dart` | Permission iOS, token FCM, stockage `users/{uid}/fcmTokens`. |
| Chat | `ptipote-app/lib/services/chat_service.dart` | Conversations et messages Firestore. |

## Backend Et Securite

| Zone | Fichier | Role |
| --- | --- | --- |
| Rules Firestore | `firestore.rules` | Autorisations Firestore. Toute nouvelle collection ou ecriture sensible doit y etre ajoutee. |
| Firebase config | `firebase.json` | Config deploy Firebase. Ne pas modifier sans raison. |
| Cloud Functions | `functions/index.js` | Envoie les push FCM quand un document est cree dans `users/{uid}/notifications`. |
| Functions deps | `functions/package.json` | Dependances Cloud Functions. |
| iOS config | `ptipote-app/ios/Runner/GoogleService-Info.plist` | Config Firebase iOS. |
| Xcode Cloud scripts | `ptipote-app/ios/ci_scripts/` | Scripts de build cloud. |

## Routes Flutter

| Route | Fichier |
| --- | --- |
| `/` | `ptipote-app/lib/features/home/home_page.dart` |
| `/figurines` | `ptipote-app/lib/features/figurines/figurines_page.dart` |
| `/nfc` | `ptipote-app/lib/features/nfc/nfc_page.dart` |
| `/profile` | `ptipote-app/lib/features/profile/profile_page.dart` |
| `/friends` | `ptipote-app/lib/features/friends/friends_page.dart` |
| `/chats` | `ptipote-app/lib/features/chat/chats_page.dart` |
| `/game` | `ptipote-app/lib/features/game/refuge_page.dart` |

Les routes sont branchees dans `ptipote-app/lib/app.dart`.

## Collections Firestore

| Collection | Utilisation | Code principal |
| --- | --- | --- |
| `users/{uid}` | Profil prive, role, infos eleveur. | `UserProfileService`, `ProfilePage` |
| `publicProfiles/{uid}` | Profil public searchable par pseudo/displayName. | `UserProfileService`, `FriendService` |
| `users/{uid}/figurines/{figurineId}` | Inventaire prive PTIPOTE. | `FigurineService`, `FigurinesPage` |
| `publicFigurines/{publicKey}` | Fiche publique visible par webapp/NFC. | `FigurineService`, webapp |
| `friendInvites/{inviteId}` | Demandes d'amis. | `FriendService`, `FriendsPage` |
| `users/{uid}/friends/{friendUid}` | Liste d'amis privee. | `FriendService`, `ChatService` |
| `transferRequests/{requestId}` | Demandes de transfert globales. | `FigurineService` |
| `users/{uid}/incomingTransfers/{figurineId}` | Demandes de transfert recues. | `FigurineService`, `FigurinesPage` |
| `users/{uid}/notifications/{notificationId}` | Notifications in-app et source des push FCM. | `NotificationService`, `functions/index.js` |
| `users/{uid}/fcmTokens/{tokenId}` | Tokens push par device. | `PushNotificationService`, `functions/index.js` |
| `chats/{chatId}` | Metadata conversation. | `ChatService`, `ChatsPage` |
| `chats/{chatId}/messages/{messageId}` | Messages chat. | `ChatService`, `ChatPage` |

## Zone 0 V1 Et Prototype Local

- Source produit a respecter: navigation principale `Ilot | P'TIPOTES | Journal`.
- Le scan figurine reste important mais contextuel: Ilot, Kernel, P'TIPOTES, adoption ou transfert. Il ne doit pas devenir un onglet principal.
- Si aucun P'TIPOTE n'existe: afficher un etat vide centre sur le scan. Si au moins un P'TIPOTE existe: ouvrir sur l'Ilot.
- `ptipote-app/ptipote-game/` contient le prototype HTML/CSS/JS local pour tester vite la boucle refuge sans Flutter.
- `ptipote-app/ptipote-game/image_game/` contient les fonds et assets visuels embarques dans l'app Flutter. Convention: le nom de fichier doit correspondre au nom de l'ecran, par exemple `Camp.jpg`, `Kernel.jpg`, `Maison.jpg`, `Lisiere_1.jpg`.
- `GameAssetResolver` lit `ptipote-game/image_game/` et resout les images par nom (`Camp`, `Kernel`, `Maison`) quelle que soit l'extension (`.jpg`, `.PNG`, etc.).
- Bouton Flutter `Jeu`: ajoute sur Home au-dessus de `Mes ptipotes`, visible seulement si `UserProfile.canSeeDiagnostics` est vrai (`dev/admin`). Ne pas creer de second toggle.
- Dans `RefugePage`, chaque case de batiment ouvre une vraie page Flutter placeholder: Maison, Kernel, Lisiere, Tour de securite, FabLab. La FabLab contient deux onglets: Atelier et Cuisine.
- Dans la page Maison ouverte depuis `RefugePage`, les P'TIPOTES de `FigurineService.watchMyFigurines()` sont affiches comme sprites sur le tiers bas. `PtipoteFigurine.vitality` vaut `100/100` par defaut, et une vitalite a 20 ou moins place le P'TIPOTE dans une des trois alcoves descendues vers le milieu-haut de l'ecran.
- Clic sur un sprite dans la Maison: ouvre/ferme une bulle avec espece, type, enveloppe, surnom, niveau, XP, vitalite, bonheur, etat et preference automatique. En alcove, la bulle s'ouvre sous le P'TIPOTE, contient `Reveiller`, et peut etre deplacee par appui long/glisse.
- Test dev Maison: l'emoji haltere permet de choisir un P'TIPOTE puis `Entrainer` retire 25 vitalite localement; a 20 ou moins il va dans une alcove.
- Test recuperation Maison: la vitalite perdue est conservee localement pendant la session. En alcove, elle remonte de 1 toutes les 30 secondes (`+2/min` configurable); une barre sous le sprite indique le temps restant avant retour operationnel. Hors alcove, recuperation lente de 1 par minute. Les sprites cherchent `png/webp` avant `jpg/jpeg` pour privilegier les images transparentes.
- Fichiers du prototype: `index.html`, `styles.css`, `data.js`, `state.js`, `tasks.js`, `ui-island.js`, `ui-panels.js`, `main.js`.
- L'ecran Ilot du prototype affiche maintenant le refuge du joueur avec fond illustre, cases batiment a opacite 20%, P'TIPOTE visible et Kernel pour scanner.
- Boucle coeur prototype: choisir un P'TIPOTE -> assigner a la Lisiere -> attendre -> recuperer -> crafter un Repas -> soigner a la Maison -> progresser.
- Handoff V1 mobile: creer progressivement Ilot, Kernel, Lisiere proche/lointaine, Atelier et Cuisine a slots, sans simulation complete.
- Lisiere V1: exactement deux onglets, `Lisiere proche` et `Lisiere lointaine`. Pas d'onglet PTIBUG separe.
- Refuge PTIBUG est un batiment dans le biome Plaine PTIBUG. Plaine PTIBUG = biome, Refuge PTIBUG = batiment.
- Atelier et Cuisine V1 utilisent des slots de salle et des elements contextuels gratuits, pas une main globale de cartes.
- Ne pas casser amis, chat entre amis, transfert, adoption NFC et rules Firestore existantes.
- Si une nouvelle fonction est ajoutee, mettre a jour cette data card avec son fichier source de verite, son flux et ses contraintes.

## PTIPOTE V1 - Stats Et Comportements

### 1. Fichiers crees ou modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/figurines/ptipote_stats_config.dart` | Source Flutter des stats V1: valeurs de base, enums, modificateurs type/enveloppe, formule XP. |
| `ptipote-app/lib/features/figurines/ptipote_figurine.dart` | Getters calcules: vitalite 100, bonheur, EVG, niveau/XP, etat, preference automatique, modificateurs, chemin image cache. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Maison: deplacement, alcoves, recuperation automatique, fiche P'TIPOTE, preference Maison/Tour/Marche. |
| `ptipote-app/lib/services/figurine_service.dart` | Lecture/ecriture Firestore des figurines, cache du chemin image resolu. |
| `ptipote-dashboard/ptipote-stats-config.json` | Miroir JSON des stats de base pour edition/export depuis le dashboard. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js`, `ptipote-dashboard/styles.css` | Onglet dashboard `Stat Ptipote` qui charge, modifie localement et exporte le JSON. |

### 2. Modeles / classes modifies

- `PtipoteFigurine`: conserve les donnees Firestore existantes et ajoute des champs calcules sans migration obligatoire.
- Enums ajoutes dans `ptipote_stats_config.dart`: `PtipoteElementType`, `PtipoteEnvelopeType`, `PtipoteBehaviorState`, `PtipoteAutoAssignmentPreference`.
- Types V1 reconnus: `vegetal`, `mineral`, `fungal`; variantes francaises/anglais courantes normalisees.
- Enveloppes V1 reconnues: `standard`, `explorateur`, `producteur`, `scientifique`, `protecteur`; inconnue ou absente => `standard`.

### 3. Stats configurables

| Stat | Defaut | Emplacement |
| --- | --- | --- |
| `maxVitality` | `100` | `ptipote_stats_config.dart` + `ptipote-stats-config.json` |
| `vitalityRecoveryPerMinute` | `1` | idem |
| `alcoveVitalityRecoveryPerMinute` | `2` | idem |
| `minVitalityBeforeAutoRest` | `20` | idem |
| `baseHappiness` | `70` | idem |
| `maxHappiness` | `100` | idem |
| `happinessDecayPerHour` | `1` | idem |
| `xpRequiredBase` | `100` | idem |
| `xpRequiredMultiplier` | `1.25` | idem |
| `baseEVG` | `50` | idem |
| `baseForageEfficiency` | `1.0` | idem |
| `baseSafetyContribution` | `1.0` | idem |
| `baseMarketContribution` | `1.0` | idem |

- Formule XP: `xpRequiredBase * pow(xpRequiredMultiplier, currentLevel - 1)`, arrondie a l'entier.
- EVG est preparee comme stat configurable et affichee/calculable, mais pas encore exploitee par une mecanique.

### 4. Dashboard

- Le dashboard possede maintenant un onglet visible `Stat Ptipote`.
- Il charge `ptipote-dashboard/ptipote-stats-config.json`, permet une edition locale via `localStorage`, et exporte un JSON.
- Non branche en runtime a Flutter/Firebase pour cette V1. Reste a faire: choisir une source partagee (par exemple `gameConfig/ptipoteStats` Firestore ou generation d'asset) et synchroniser l'app avec cette source.
- Les modificateurs type/enveloppe, couts mission, contribution Tour et contribution Marche sont prepares cote Dart mais pas encore editables dans le dashboard.

### 5. Etats P'TIPOTE

| Etat | Comportement V1 |
| --- | --- |
| `idle` | Disponible, reserve pour les futurs flux. |
| `wanderingHome` | Se balade dans la Maison. Utilise par defaut si Vitalite > 20. |
| `resting` | Dans une alcove et recupere. Active si Vitalite <= 20. |
| `onMission` | Prepare pour Lisiere/missions, pas encore branche. |
| `helpingTower` | Prepare pour aide Tour, pas encore actif. |
| `helpingMarket` | Prepare pour aide Marche, pas encore actif. |
| `exhausted` | Vitalite a 0, repos obligatoire. |

### 6. Vitalite

- Vitalite remplace l'ancienne notion d'energie P'TIPOTE. L'energie reste une ressource/monnaie joueur.
- Max V1: `100`.
- Seuils: `80-100` en forme, `50-79` disponible, `21-49` fatigue, `0-20` repos necessaire.
- A `20` ou moins, la Maison place le P'TIPOTE dans une alcove et bloque le deplacement.
- Recuperation V1 Maison: hors alcove `+1/min`, en alcove `+2/min` configurable via `alcoveVitalityRecoveryPerMinute` et applique par tick de 30s.
- Reveil manuel: bouton `Reveiller` dans la fiche d'un P'TIPOTE en alcove; il le sort du repos avec une Vitalite juste au-dessus du seuil de repos.
- Ne depasse jamais `maxVitality`; a `100`, l'override local est retire et le P'TIPOTE revient a `wanderingHome`.

### 7. Affectation automatique

- Champ prepare: `autoAssignmentPreference` avec valeurs `home`, `tower`, `market`.
- UI Maison: controle `[Maison] [Tour] [Marche]` dans la fiche P'TIPOTE.
- Si Vitalite <= 20: force `resting`.
- Si preference `home`: retour Maison / balade.
- Si preference `tower`: fallback Maison pour cette V1, car la Tour n'est pas branchee.
- Si preference `market`: fallback Maison pour cette V1, car le Marche n'est pas branche.

### 8. Attentes / systemes non encore branches

- Tour non branchee: `helpingTower` et `safetyContribution` prepares mais pas actifs.
- Marche non branche: `helpingMarket` et `marketContribution` prepares mais pas actifs.
- Missions Lisiere branchees en runtime avec sauvegarde Firebase V1: un P'TIPOTE en mission est masque de la Maison; un P'TIPOTE en mission ou en repos est considere `occupe` et n'est pas selectionnable en Lisiere. Les missions actives et `vitalityOverrides` sont stockes dans `users/{uid}/game/zone0` pour survivre aux reloads/builds. L'etat Firestore `behaviorState` reste a brancher plus tard.
- Bio-batterie / Energie joueur non branchee dans cette V1 stats.
- Bonheur existe (`baseHappiness`, bornes, helpers `addHappiness`/`reduceHappiness`) mais ses effets restent a integrer: calin, nourriture, repos, mission reussie, accident en Lisiere.
- Enveloppes non finalisees cote cartes: modificateurs prepares avec fallback `standard`.
- Dashboard `Stat Ptipote` visible comme onglet separe, non synchronise automatiquement avec Flutter/Firebase: edition locale et export JSON seulement.
- Cache image: `fields.imagePath` / `fields.img` et champ top-level `imagePath` peuvent stocker l'URL resolue pour eviter de retester les extensions a chaque affichage.

## Coeur Du Camp V1 - Progression Du Refuge

### 1. Fichiers crees ou modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/camp_heart_config.dart` | Source Flutter des stades, XP requis, population, limite P'TIPOTES confort, bonheur refuge, activite locale et deblocages. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Hotspot `Cœur du Camp` sur le refuge, ecran detail, jauge, depot Organique placeholder, passage de niveau. |
| `ptipote-dashboard/camp-heart-config.json` | Miroir JSON des paliers du Cœur du Camp pour consultation/export dashboard. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js`, `ptipote-dashboard/styles.css` | Onglet dashboard `Cœur du Camp` en lecture/export; edition avancee a brancher plus tard. |

### 2. Donnees ajoutees

- `campHeartLevel`: niveau courant du Cœur, de 1 a 5.
- `campStage`: enum `CampStage` avec `camp`, `refuge`, `bourgade`, `village`, `petiteVille`.
- `vegetalizationXp`: XP de vegetalisation du niveau courant.
- `vegetalizationXpRequired`: seuil du prochain niveau; `null` au niveau max V1.
- `totalVegetalizationInvested`: total Organique investi.
- `activePtipoteComfortLimit`: nombre de P'TIPOTES actifs confortables par stade.
- `populationMin` / `populationMax`: fourchette preparee quand connue.
- `refugeHappinessBonus`: bonus doux de bonheur refuge par stade.
- `localActivityModifier`: donnees preparees pour le futur Marche.

### 3. Configuration

- Fichier source Flutter: `ptipote-app/lib/features/game/camp_heart_config.dart`.
- Miroir dashboard: `ptipote-dashboard/camp-heart-config.json`.
- XP requis V1: niveau 1 -> 2 = `100`, 2 -> 3 = `250`, 3 -> 4 = `500`, 4 -> 5 = `900`, niveau 5 = max V1.
- Pour modifier les valeurs dans l'app, changer `camp_heart_config.dart`; le JSON dashboard est un miroir manuel tant qu'aucune synchro config n'existe.

### 4. UI

- Dans `RefugePage`, le `Cœur du Camp` est un hotspot cliquable proche du centre-bas du decor.
- Le `Kernel` reste un hotspot distinct, proche du Cœur mais separe, legerement centre/droite.
- L'ecran `CampHeartPage` affiche: stade, niveau, jauge de vegetalisation, stock Organique placeholder, depot +1/+5/+10/Max, prochain palier, population, P'TIPOTES confort, bonheur refuge, activite locale et placeholders.

### 5. Deblocages par stade

- Camp: Maison, Kernel, Cuisine simple, Lisiere proche, 1 P'TIPOTE actif confortable, visiteurs, Colline, Plaine riche.
- Refuge: Atelier simple, Tour, Bassin mineral, Sous-bois, Refuge PTIBUG, 2 P'TIPOTES actifs confortables, habitants permanents.
- Bourgade: Serre, Schemas PTIBUG via Atelier, evolutions PTIBUG, premiere Lisiere lointaine simple, 3 P'TIPOTES actifs confortables.
- Village: systemes sociaux avances plus tard, Relais commun plus tard, Lisiere lointaine plus complete, routes commerciales plus tard, 4 P'TIPOTES actifs confortables.
- Petite ville: placeholders futurs, mairie plus tard, organisation avancee, systemes de groupe plus tard, Zone 1 avancee plus tard.
- Ordre important: Cuisine simple disponible au stade Camp; Atelier simple seulement au stade Refuge.

### 6. Systemes branches

- Jauge de vegetalisation branchee dans `CampHeartState` et sauvegardee dans `users/{uid}/game/zone0.campHeart`.
- Depot Organique branche sur le stock global Maison via `Zone0GameState.inventory`; consomme les stacks `Organique`. Le statut Firebase est visible dans l'inventaire pour diagnostiquer les refus de rules/reseau.
- Passage de niveau/stade branche localement avec message SnackBar.
- Population, bonheur refuge, limite P'TIPOTES confort et activite locale sont affiches/prepares mais pas encore appliques aux autres systemes.

### 7. Attentes / placeholders

- Persistance Firestore du Cœur branchee sur `users/{uid}/game/zone0`; pas encore de synchro multi-device temps reel.
- Atelier affiche comme deblocage Refuge mais gameplay complet non branche.
- Tour affichee comme deblocage Refuge mais aide/securite non branchee.
- Marche non branche: population et `localActivityModifier` seulement prepares.
- Lisiere lointaine non developpee: deblocage affiche mais non actif.
- Limite P'TIPOTES actifs confortables preparee mais ne bloque pas encore missions/actions.
- Bonheur refuge prepare et affiche mais pas encore relie au bonheur P'TIPOTE ou aux evenements.
- Dashboard Cœur du Camp en lecture/export seulement; edition et synchro runtime restent a brancher.

## LISIERE V1 - Missions, Inventaire Et Rapports

### 1. Fichiers crees ou modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/lisiere_forage_config.dart` | Source Flutter des biomes, durees, intensites, gains, couts Vitalite, risques, limites inventaire. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Etat Zone 0: Vitalite override, missions persistantes, resolution centralisee, inventaire global, rapports/messages, securite fallback, persistance Firestore V1 et statut de synchro Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Ecran Lisiere proche, lancement mission, tick de resolution, Maison avec inventaire, boite aux lettres et pastilles. |
| `ptipote-dashboard/lisiere-forage-config.json` | Miroir JSON des temps/gains/couts/risques Lisiere pour consultation/export dashboard. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Onglet dashboard `Lisiere / Fourrage` en lecture/export. |

### 2. Configuration

- `forageTimeScale`: `6`, donc 1h theorique = 10 min test, 2h = 20 min, 6h = 60 min, 10h = 100 min.
- Intensites: `doux` x0.75 gains / x0.75 Vitalite / -5% risque; `normal` x1; `intensif` x1.35 gains / x1.25 Vitalite / +10% risque.
- Couts Vitalite par duree: 1h `15`, 2h `25`, 6h `55`, 10h `80` avant multiplicateur intensite.
- Gains XP mission: 1h `10`, 2h `18`, 6h `45`, 10h `75`, multiplies par intensite (`doux` x0.85, `normal` x1, `intensif` x1.2) et bonus XP enveloppe.
- Risques biome : Hauts-Refuges `10%`, Savane tropicale `8%`, Semi-désert / Garrigue tropicale `14%`, Forêt humide relictuelle `12%`.
- Inventaire V1: `10` slots, stack max `10`.

### 3. Dashboard

- Onglet visible: `Lisiere / Fourrage`.
- Champs affiches depuis `ptipote-dashboard/lisiere-forage-config.json`: multiplicateur temps, durees reelles, intensites, risques, gains de base par biome, gains XP mission.
- Onglet `Stat Ptipote`: affiche `xpRequiredBase`, `xpRequiredMultiplier` et une preview des XP requis par niveau.
- Non synchronise automatiquement avec Flutter/Firebase pour cette V1; modifier aussi `lisiere_forage_config.dart` pour changer l'app.

### 4. Biomes V1

- Colline: mixte, 1h normal = `2 Organique` + `2 Mineral`.
- Plaine riche: Organique, 1h normal = `4 Organique` + `1 Mineral`.
- Bassin mineral: Mineral, 1h normal = `1 Organique` + `4 Mineral`.
- Sous-bois: Organique/transformation, 1h normal = `3 Organique` + `1 Mineral`.
- Batiments lies aux biomes non branches: aucun bouton casse, mention `Batiment lie : a venir` dans l'estimation.

### 5. Mission model

- Modele `ForageMission`: id, champs solo compatibles (`figurineId`, `figurineName`), champs equipe (`memberIds`, `memberNames`), biome, duree, intensite, startTime, endTime, expectedRewards, cout Vitalite total et par membre, risque, XP total et par membre, status. Serialize/deserialise vers Firebase.
- Etats mission: `active`, `completed`.
- Lancement: si plusieurs P'TIPOTES sont selectionnes ensemble, ils forment une seule equipe dans une seule mission. Ils partagent le meme biome, risque, incident et rapport; couts Vitalite/XP restent stockes par membre.
- Resolution: centralisee dans `Zone0GameState.resolveDueForageMissions()`, appelee par un tick depuis `RefugePage` et a l'ouverture de la Lisiere. Elle applique max 1 incident doux commun, tente d'ajouter les gains a l'inventaire, ajoute l'XP a chaque membre, gere le level-up, sauvegarde `fields.x/xp/l/level` dans Firestore, cree un rapport non lu par equipe.
- Retour d'urgence: bouton sur mission active dans `LisierePage`; confirmation obligatoire, retour immediat, butin au prorata du temps ecoule et +5% de risque evenement.
- Etat `onMission` determine via mission active sauvegardee et `memberIds`; les champs Firestore P'TIPOTE `behaviorState` restent a brancher. Un P'TIPOTE en mission est masque de la Maison pendant la mission.

### 6. Risques

- Formule V1: `baseBiomeRisk + intensityRiskModifier - campSecurity * 0.4 - bonus type`, minimum `5%`.
- Securite refuge fallback: `50` tant que la Tour n'est pas branchee.
- Labels UI: `Tres sur`, `Sur`, `Incertain`, `Risque`.
- Incidents doux V1: Pollution (-20% Organique), Drone errant (-25% gains), Climat difficile (-15% gains).
- Bonus types prepares: vegetal aide Plaine riche, mineral aide Bassin mineral, fongique aide Sous-bois.

### 7. Inventaire global

- Emplacement code: `Zone0GameState.inventory` et `Zone0InventorySheet` dans `refuge_page.dart`.
- Accessible depuis la Maison via icone caisse en bas a droite.
- Limite: 10 slots, stack max 10, ressources supportees `Organique`, `Mineral`, et Bio-batterie preparee par convention mais pas encore generee.
- UI: grille mobile 3 colonnes, 9 slots + 1 slot bonus, cases arrondies, icone ressource au centre et quantite en haut a droite.
- Inventaire plein: la Lisiere affiche un avertissement rouge avant depart si les gains potentiels depassent la capacite; le rapport marque le surplus perdu.
- Le Cœur du Camp consomme maintenant le stock `Organique` de cet inventaire global via `Zone0GameState.removeResource`.
- Inventaire sauvegarde dans `users/{uid}/game/zone0.inventory`.
- Diagnostic Firebase: la feuille inventaire affiche le dernier etat de synchro (`Synchronise`, `Erreur Firebase`, utilisateur non pret) et le dernier message d'erreur.

### 8. Rapports / messages P'TIPOTE

- Emplacement code: `Zone0GameState.reports`, `PtipoteMissionReport`, `MissionReportsSheet`.
- Creation automatique a la fin de mission avec P'TIPOTE, biome, duree, intensite, gains, XP gagnee, level-up local, incident, Vitalite restante, date.
- Pastille Maison sur le refuge et pastille boite aux lettres dans la Maison lisent `unreadReportCount`; `Zone0GameState` notifie l'UI quand un rapport arrive.
- Ouverture de la boite aux lettres marque les rapports comme lus.

### 9. Attentes / placeholders

- Tour non branchee: Securite refuge par defaut `50`.
- Marche non branche: autoAssignment `market` fallback Maison existant.
- Stock Atelier non branche: transfert Maison <-> Atelier et drag and drop prevus plus tard.
- Persistance missions/rapports non branchee; inventaire, Cœur et XP/niveau P'TIPOTE sont sauvegardes Firestore.
- Lisiere lointaine, batiments de biomes, Refuge PTIBUG, puzzle tokens et auto-battler non developpes.

## Flux Principaux

### Auth Et Profil

1. `main.dart` initialise Firebase.
2. `AuthGate` verifie `FirebaseAuth.instance.authStateChanges()`.
3. `SignInPage` connecte ou cree le compte.
4. `UserProfileService.getOrCreateMyProfile()` cree/synchronise `users/{uid}` et `publicProfiles/{uid}`.
5. `ProfilePage` modifie `username` et `displayName`.

### Roles Admin Et Dev

- Roles stockes dans `users/{uid}.role`.
- Roles valides: `user`, `dev`, `admin`.
- UID bootstrap admin: `taNxWXLMh2gJx5CHgmBB8Phl4c93`.
- Seul un admin peut donner ou retirer le role `dev` depuis `ProfilePage`.
- Le role `admin` ne doit pas etre donne depuis l'app sauf bootstrap explicite.
- Le role `dev` ou `admin` debloque le toggle debug dans `NfcPage`.
- Autorisations correspondantes: `firestore.rules`.

### Scan NFC

1. Accueil: `HomePage._scanFigurine()` ouvre la modale NFC.
2. Lecture physique: `NfcManagerService.readTag()` dans `nfc_service.dart`.
3. Resultat envoye vers `NfcPage(initialUid, initialPayload)`.
4. Decodage NDEF et parsing: `NfcPage._processRawScan()`.
5. Verification Firebase: `FigurineService.getMyFigurineByTagUid`, `getMyFigurineByPublicKey`, `getPublicFigurine`.
6. Adoption si non enregistre: `FigurineService.saveScannedFigurine()` puis `publishPublicFigurine()`.
7. Confirmation transfert si scan attendu: `FigurineService.confirmIncomingTransfer()`.

### Mes PTIPOTES

- UI carte principale: `FigurinesPage` et widgets prives du meme fichier.
- Modele et champs: `PtipoteFigurine`.
- Images: `PtipoteImage`.
- Donnees: `FigurineService.watchMyFigurines()`.
- Refresh dur serveur: `FigurineService.refreshMyFigurinesFromServer()`.
- Ordre manuel: `FigurineService.updateFigurineOrder()`.
- Renommage: `FigurinesPage._renameFigurine()` puis `FigurineService.renameMyFigurine()`.

### Transfert PTIPOTE

Source de verite: `FigurineService`.

1. Demandeur active le mode transfert dans `FigurinesPage`.
2. Selection d'une carte PTIPOTE.
3. Choix d'un ami via `_chooseFriend()`.
4. Confirmation UI via `_confirmTransferRequest()`.
5. Ecriture Firestore via `FigurineService.requestTransfer()`:
   - `transferRequests/{fromUid_figId_toUid}`
   - `users/{toUid}/incomingTransfers/{figurineId}`
   - update `users/{fromUid}/figurines/{figurineId}`
   - notification `transfer_request`
6. Receveur voit la demande dans `FigurinesPage.watchIncomingTransfers()`.
7. Acceptation: `FigurineService.acceptTransferRequest()`.
8. Refus: `FigurineService.rejectTransferRequest()`.
9. Apres acceptation, receveur doit scanner la figurine.
10. Scan valide: `NfcPage` detecte `_pendingTransfer`.
11. Bouton confirmer: `FigurineService.confirmIncomingTransfer()`.

Points sensibles:
- Ne pas dupliquer une figurine sans comprendre `transferRequests` et `incomingTransfers`.
- Le proprietaire public doit etre coherent entre `users/{uid}/figurines` et `publicFigurines`.
- Si le transfert echoue avec `permission-denied`, verifier `firestore.rules` avant de bricoler l'UI.
- Les cooldowns de rename/transfer vivent dans le modele `PtipoteFigurine` et les champs Firestore ecrits par `FigurineService`.

### Amis

1. Page: `FriendsPage`.
2. Recherche dynamique: `FriendService.searchUsers()` sur `publicProfiles` puis fallback `users`.
3. Invitation: `FriendService.sendInvite()`.
4. Accept/refuse/cancel: `FriendService.acceptInvite()`, `rejectInvite()`, `cancelInvite()`.
5. Badges: `NotificationService.watchUnreadCountFor({'friend_invite'})` dans `HomePage`.
6. Clear notifications quand on entre dans la page: `FriendsPage` ou service associe.

### Chat

1. Liste: `ChatsPage`.
2. Conversation: `ChatPage`.
3. Service: `ChatService`.
4. Messages stockes dans `chats/{chatId}/messages`.
5. Notifications chat: `NotificationService.sendToUser(type: 'chat_message')`.
6. Clear notification chat: `NotificationService.markChatAsRead(friendUid)`.

### Notifications

Deux couches:

- In-app: documents Firestore `users/{uid}/notifications`.
- Push telephone: Cloud Function `sendPushForNotification` dans `functions/index.js`.

Flux:
1. Un service cree une notification via `NotificationService.sendToUser()`.
2. `functions/index.js` detecte le nouveau document.
3. La function lit `users/{uid}/fcmTokens`.
4. Firebase Messaging envoie le push.
5. La function ecrit `pushStatus`, `pushSuccessCount`, `pushFailureCount`, `pushErrors`.

Pour debugger les push:
- Verifier que le token existe dans `users/{uid}/fcmTokens`.
- Verifier le document notification et ses champs `pushStatus/pushErrors`.
- Verifier les logs Cloud Functions.
- Verifier APNs/Firebase Messaging cote Firebase Console.

## FABLAB V1 - Construction Et Cuisine

### 1. Fichiers crees ou modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/fablab_config.dart` | Configuration Fablab V1: cout, capacite de stock, niveaux, recette Cuisine. |
| `ptipote-app/lib/features/game/craft_config.dart` | Configuration Craft V1: recettes, ingredients, resultats, effet consommable faim/vitalite. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Etat persistant du Fablab, construction, capacite globale, recette Repas simple. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Hotspot Fablab constructible, modale construction, page Fablab, Cuisine, inventaire dynamique. |
| `ptipote-dashboard/fablab-config.json` | Miroir JSON dashboard pour consultation/export. |
| `ptipote-dashboard/craft-config.json` | Miroir JSON dashboard des recettes Craft. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Onglet dashboard `Fablab`. |

### 2. Construction generique preparee

- Etat utilise: `constructible` si `fablabLevel == 0`, `built` si `fablabLevel >= 1`.
- Donnees sauvegardees dans `users/{uid}/game/zone0.buildings.fablab`.
- Le modele stocke `buildingId`, `buildingType`, `displayName`, `state`, `currentLevel`, `maxLevel`, `requiredCampHeartLevel`, `stockCapacityBonusPerLevel`, `isVisible`.
- La logique `constructFablabLevel1()` sert de base pour les prochains batiments constructibles.

### 3. Fablab

- Visible des le refuge comme emplacement `Fablab a batir`.
- Cout niveau 1: `8 Organique`, `4 Mineral`.
- Construction immediate, sans timer ni assignation P'TIPOTE.
- Apres construction: `fablabLevel = 1`, etat `built`, message boite aux lettres systeme.
- Clic apres construction: ouvre la page Fablab.

### 4. Stock global

- Capacite de base: `100` unites.
- Formule: `baseGlobalStockCapacity + fablabLevel * stockCapacityBonusPerFablabLevel`.
- Stack max actuel: `10`, donc niveau 0 = 10 slots, niveau 1 = 20 slots.
- UI inventaire: grille scrollable 3 colonnes, conserve les stacks existants.

### 5. Cuisine

- Cuisine active au Fablab niveau 1.
- Interface: 2 slots visuels, Eau gratuite contextuelle, stock Organique, resultat.
- Recette test temporaire: `2 Organique + Eau => 1 Repas simple`, definie dans `craft_config.dart`.
- `Repas simple` est ajoute a l'inventaire global et stacke comme les autres ressources.
- `Repas simple` est consommable depuis la fiche P'TIPOTE dans la Maison: `+20 faim`, `+15 vitalite`.

### 6. Dashboard

- Onglet `Fablab` charge `ptipote-dashboard/fablab-config.json`.
- Variables visibles/exportables: cout Organique, cout Mineral, capacite de base, bonus de stock, niveau max, niveau Cuisine, prerequis Atelier/Recycleur.
- Onglet `Craft` charge `ptipote-dashboard/craft-config.json`; permet de creer une recette locale avec materiaux, quantites, objet resultat, statut consommable, faim restauree et vitalite restauree, puis exporter le JSON.
- Synchronisation automatique Dashboard -> Flutter non branchee; modifier aussi `fablab_config.dart` pour changer l'app.

### 7. Sections futures

- Atelier visible mais verrouille: `Debloque au Cœur du Camp niveau 1.`
- Recycleur visible mais verrouille: `Debloque au Cœur du Camp niveau 2.`
- Aucun gameplay Atelier, Recycleur, schemas PTIBUG, amelioration PTIBUG ou drag and drop stock n'est actif.

## PTIPOTE V1 - Repos, Faim Et Consommables

### 1. Fichiers crees ou modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/figurines/ptipote_stats_config.dart` | Stats V1 ajoutees: recuperation naturelle/heureuse/repos, faim, seuils bonheur, cooldown calin. |
| `ptipote-app/lib/features/game/craft_config.dart` | Recette `Repas simple` et effets consommables configurables cote app. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Persistance Firebase faim/repos manuel/dernier calin, regeneration, faim de mission, consommation. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Fiche P'TIPOTE: faim, heureux, dormir, caliner avec cooldown, nourrir, jauge de repos. |
| `ptipote-dashboard/ptipote-stats-config.json` | Miroir JSON des nouvelles stats faim/repos/calin. |
| `ptipote-dashboard/craft-config.json` | Miroir JSON des recettes et consommables. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Onglets `Stat Ptipote` enrichi et `Craft`. |

### 2. Recuperation de vitalite

- Regeneration naturelle: `+1 vitalite` toutes les `2 minutes`.
- Si heureux: `+1 vitalite/minute` prepare via `happyVitalityRecoveryPerMinute`.
- En repos/alcove: `+2 vitalite/minute`.
- Le repos manuel est stocke dans `users/{uid}/game/zone0.manualRestingIds`.
- A vitalite max, le P'TIPOTE quitte le repos manuel.

### 3. Bonheur operationnel

Un P'TIPOTE est heureux si:
- il est au repos;
- sa vitalite est strictement superieure a `30`;
- sa faim est strictement superieure a `30`;
- il a ete caline dans les `3 heures`.

Le bouton `Caliner` a un cooldown par P'TIPOTE de `3 heures`; pendant le cooldown il est grise et affiche une jauge de recharge.

### 4. Faim

- Faim max/base V1: `100`.
- Decroissance passive: `-1 faim` toutes les `30 minutes`.
- Une mission retire aussi de la faim egale a `50%` de la vitalite consommee.
- Donnee persistante: `users/{uid}/game/zone0.hungerOverrides`.

### 5. Consommable Repas simple

- `Repas simple` est fabrique en Cuisine.
- Consommation depuis la fiche P'TIPOTE Maison.
- Effet V1: `+20 faim`, `+15 vitalite`.
- Les ressources ne sont retirees qu'au moment de la consommation.

### 6. Dashboard

- `Stat Ptipote` expose les seuils et vitesses: regeneration naturelle, repos, faim, ratio mission, seuils bonheur, cooldown calin.
- `Craft` permet d'ajouter localement une recette, selectionner deux materiaux maximum, definir un objet resultat et ses effets consommables, puis exporter `craft-config.json`.
- La synchro automatique Dashboard -> Flutter/Firebase reste a brancher; le JSON exporte sert de source de reprise.

## PTIPOTE V1 - Bonheur, Faim Et Repos

### 1. Fichiers modifies

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/figurines/ptipote_stats_config.dart` | Source des seuils V1: vitalite, faim, mission min, cooldown/soin calin, bulles, besoins requis. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Calcul humeur, faim/vitalite, rapports persistants, suppression rapport, retour mission en repos. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Maison: bulles de besoins, fiche statut, temps restant; Lisiere: seuil mission/avertissements; rapports swipe. |
| `ptipote-dashboard/ptipote-stats-config.json` | Miroir dashboard des nouvelles valeurs de tuning. |
| `ptipote-dashboard/app.js` | Onglet Stat Ptipote expose les champs ajoutes. |

### 2. Vitalite

- Recuperations exclusives, par priorite:
  - repos alcove: `+2 Vitalite/min`;
  - heureux et eveille: `+1 Vitalite/min`;
  - eveille non heureux: `+1 Vitalite/2 min`.
- La Vitalite reste bornee entre `0` et `100`.
- `Envoyer au lit` ajoute le P'TIPOTE a `manualRestingIds`.
- `Reveil` retire le repos manuel et garde au moins le seuil de reveil existant.

### 3. Faim

- Faim bornee entre `0` et `100`.
- Baisse naturelle: `-1` toutes les `30 min` hors mission.
- Pendant une mission, la baisse passive est suspendue par le moteur Maison (`isOnMission` ignore le tick faim).
- Perte de faim mission: `vitaliteConsommee * missionHungerCostRatio`, V1 = `0.5`.
- Craft: aucun cout specifique en V1; les couts pourront etre ajoutes plus tard.

### 4. Bonheur

- Bonheur calcule depuis 3 besoins:
  - nourri: `faim > 30`;
  - repose: `Vitalite > 30` ou actuellement en repos;
  - caline: dernier calin dans `cuddleCareDurationMinutes`.
- Etats:
  - `Heureux`: 3 besoins satisfaits;
  - `Bien`: 2 besoins satisfaits;
  - `Mal`: 0 ou 1 besoin satisfait.
- Pas de jauge bonheur independante sauvegardee pour la logique Zone 0.

### 5. Calin

- Cooldown bouton: `cuddleCooldownMinutes = 180`.
- Duree de soin affectif: `cuddleCareDurationMinutes = 240`.
- Le bouton reste avec jauge de recharge, par P'TIPOTE.

### 6. Bulles de besoins

- Affichees dans la Maison au-dessus des P'TIPOTES, avec `IgnorePointer`.
- Icones:
  - lit pour Vitalite basse;
  - repas pour faim basse;
  - coeur pour besoin affectif.
- Priorite: Vitalite critique, faim critique, calin, puis seuils non critiques.
- Frequence configurable: min/max intervalle et duree d'affichage.

### 7. Missions

- Seuil minimum selection: `minimumMissionVitality = 10`.
- Les P'TIPOTES occupes ou au repos restent non selectionnables.
- Si Vitalite finale estimee `<= 20`, avertissement non bloquant.
- Au retour avec Vitalite `<= 20`, le P'TIPOTE est ajoute a `manualRestingIds` et revient en repos.

### 8. Rapports

- Les rapports sont sauvegardes dans `users/{uid}/game/zone0.reports`.
- La lecture marque `read = true` mais ne supprime plus.
- Suppression manuelle: swipe gauche sur un rapport.
- Le compteur Maison compte uniquement les rapports non lus.
- Le rapport affiche Vitalite restante, faim restante, humeur finale et phrase de retour.

### 9. Temps de recuperation

- Fiche P'TIPOTE > Details affiche:
  - `Vitalite maximale`, ou
  - `Repos complet dans X min`.
- Formule:
  - alcove: points manquants / `2 par min`;
  - heureux eveille: points manquants / `1 par min`;
  - normal: points manquants * `2 min`.

### 10. Dashboard

- Champs exposes: mission minimum, seuils faim/vitalite, cooldown/duree calin, seuils bulles, intervalles bulles, besoins requis.
- Les champs `Stat Ptipote` sont publies dans Firestore (`gameConfigs/zone0.ptipoteStats`) avec le bouton **Publier dans l'app**. Flutter charge ces valeurs au demarrage et ecoute les mises a jour du document pendant que l'application est ouverte.
- Les valeurs embarquees de `ptipote_stats_config.dart` restent le fallback hors ligne ou tant qu'aucune configuration n'est publiee. Les modificateurs de type et d'enveloppe restent versionnes dans l'application pour cette V1.
- Mise a jour hors-ligne fine non finalisee: la simulation applique les ticks en Maison et persiste les valeurs, mais la chronologie hors-ligne mission/repos/craft devra etre raffinee quand les activites longues seront toutes modelisees.

## CONFIGURATION DISTANTE V1 — DASHBOARD VERS FLUTTER

### Fichiers

- `ptipote-dashboard/app.js` : charge et publie les champs P'TIPOTE dans Firestore, sans export de fichier.
- `ptipote-dashboard/index.html` : action **Publier dans l'app** dans l'onglet Stat Ptipote.
- `ptipote-app/lib/features/figurines/ptipote_stats_config.dart` : valeurs V1 par defaut, serialisation des champs Dashboard et configuration active a l'execution.
- `ptipote-app/lib/features/game/remote_game_config_service.dart` : ecoute le document global de reglages et applique les valeurs publiees.
- `ptipote-app/lib/features/game/zone0_game_state.dart` : demarre la synchronisation avant le chargement de l'etat Zone 0 et redessine l'interface apres une mise a jour.
- `firestore.rules` : lecture authentifiee de `gameConfigs/*`, ecriture reservee aux roles admin/dev du Dashboard.

### Flux

1. Un admin/dev modifie les champs dans **Stat Ptipote**.
2. **Publier dans l'app** enregistre `gameConfigs/zone0.ptipoteStats`, avec la version et les metadonnees de publication.

### Configuration distante Zone 0

- Les reglages de gameplay globaux sont regroupes dans le document `gameConfigs/zone0`, champ `zone0Settings` (schemaVersion 2). Les sections publiees sont `campHeart`, `lisiere`, `tower`, `towerOperations`, `fablab`, `workshop`, `market` et `housing`.
- Le Dashboard charge d'abord les JSON versionnes de `ptipote-dashboard/` puis les valeurs publiees. Il edite des champs structures (nombres, durees, couts, niveaux et recettes) et publie directement dans Firestore: aucun export ou upload JSON n'est necessaire.
- Flutter applique la configuration initiale et les mises a jour temps reel dans `RemoteGameConfigService`, via `remote_zone0_settings.dart`. En cas de document absent, de champ invalide ou hors ligne, les constantes Dart `default*Config` restent actives.
- La progression joueur n'est jamais migree dans `gameConfigs`: inventaire, chantiers, missions, niveaux et etat du refuge restent dans `users/{uid}/game/zone0`.
- `firestore.rules` autorise la lecture authentifiee de `gameConfigs/*` et reserve create/update/delete aux roles `admin` et `dev` existants. Les roles ne reposent pas sur des custom claims.
- Limite V1: les textes descriptifs et les anciens champs JSON qui ne correspondent a aucun calcul Flutter restent versionnes comme documentation et ne sont pas exposes a la publication distante.
3. Flutter charge ces valeurs a l'ouverture puis ecoute les changements en direct.
4. Sans reseau ou sans document publie, Flutter conserve les valeurs integrees au build.

### Limites V1

- Cette premiere connexion reelle couvre les statistiques P'TIPOTE a champs numeriques.
- Les onglets Coeur, Lisiere, Tour, Fablab et Architecture restent actuellement des miroirs JSON versionnes : ils doivent etre migres section par section vers le meme document Firestore pour devenir editables en direct.
- Aucun reglages de type/enveloppe n'est encore edite depuis le Dashboard afin de ne pas exposer une structure de modificateurs incomplete.

## TOUR DE SECURITE ET LISIERE V1

### 1. Fichiers crees ou modifies

- `ptipote-app/lib/features/game/security_tower_config.dart`: configuration V1 de la Tour, cout, slots, gain/decroissance de securite et ticks.
- `ptipote-app/lib/features/game/lisiere_forage_config.dart`: valeurs V1 des biomes, formule de risque minimum, coefficient de reduction securite, dangers possibles et champs futurs de restauration de la Savane tropicale.
- `ptipote-app/lib/features/game/zone0_game_state.dart`: etat de construction Tour, affectation P'TIPOTE, securite du camp, persistence Firebase, rapports enrichis.
- `ptipote-app/lib/features/game/refuge_page.dart`: hotspot Tour, construction, page d'affectation, estimation Lisiere et rapport de mission enrichis.
- `ptipote-dashboard/lisiere-forage-config.json`: valeurs dashboard des biomes et formule de risque.
- `ptipote-dashboard/security-tower-config.json`: valeurs dashboard de la Tour.
- `ptipote-dashboard/index.html` et `ptipote-dashboard/app.js`: onglet Tour et affichage/export de la configuration.

### 2. Tour

- Batiment visible dans l'Ilot.
- Avant Coeur du Camp niveau 1: affiche verrouillage "Coeur requis".
- A partir du niveau requis: mini-menu de construction.
- Cout V1: `6 Organique`, `8 Mineral`.
- Construction immediate, sans timer ni ouvrier.
- Niveau 1: `1` slot P'TIPOTE; niveaux 2/3 prepares dans la config.
- La surveillance de Tour utilise maintenant un modele de mission (`TowerMission`) proche de la Lisiere: P'TIPOTE, plan, debut, fin, cout Vitalite, gain Securite et statut.
- Plans V1: `1h`, `3h`, `6h`, `10h`, et `Jusqu'a 25% puis dodo`; ce dernier calcule les ticks possibles puis renvoie le P'TIPOTE en alcove.
- Un P'TIPOTE en mission Tour disparait de la Maison et devient indisponible pour les missions Lisiere/craft.
- Les preferences auto Maison/Tour/Marche choisies dans la Maison sont sauvegardees dans `autoPreferenceOverrides` sur Firebase (`users/{uid}/game/zone0`).
- Au lancement d'une mission Lisiere, la preference auto de chaque membre est capturee dans `ForageMission.autoPreferenceByMember`; au retour, un P'TIPOTE avec preference `tower` lance une mission Tour courte si elle est construite, s'il reste un slot et si sa Vitalite est au-dessus du seuil de repos.

### 3. Securite

- Stockage runtime: `refugeSafety`, sauvegarde Firebase `users/{uid}/game/zone0.campSecurity`.
- Missions Tour sauvegardees dans `users/{uid}/game/zone0.towerMissions`.
- Minimum `0`, maximum `100`.
- Gain V1: `+5` securite par tick de `10 min` avec P'TIPOTE affecte.
- Cout V1: `-5 Vitalite` par tick pour le P'TIPOTE affecte.
- Decroissance V1: `-1` securite par tick sans P'TIPOTE affecte.
- Si Vitalite du P'TIPOTE atteint le seuil de repos, il est retire de la Tour et envoye en alcove via `manualRestingIds`.

### 4. Lisiere

- Nouvelles valeurs de biomes:
  - Plaine: danger `30%`, `2 Organique`, `1 Mineral`.
  - Colline: danger `45%`, `4 Organique`, `3 Mineral`.
  - Sous-bois: danger `40%`, `5 Organique`, `1 Mineral`.
  - Bassin mineral: danger `35%`, `1 Organique`, `5 Mineral`.
- Formule V1: `danger biome + modificateur intensite - securite * 0.4 - petits bonus type`.
- Danger minimum: `5%`.
- Labels: Tres sur, Sur, Incertain, Risque, Tres risque.
- Plaine: champs futurs `restorationLevel`, `restorationStage`, modifiers et bonus PTIBUG prepares, non actifs.

### 5. Missions

- La securite est memorisee au lancement: `securityAtLaunch`.
- Le rapport garde aussi `baseRiskPercent`, `securityReduction`, `realRiskPercent`.
- Les missions d'equipe gardent une seule mission et un seul rapport; chaque membre conserve ses couts, XP et preference de retour.
- Maximum un evenement impactant par mission.
- Dangers V1:
  - Pollution: `-20% Organique`.
  - Drone errant: `-25% gains totaux`.
  - Climat difficile: `-15% gains totaux`.
  - Terrain instable: `-20% Mineral`.

### 6. Dashboard

- Onglet `Lisiere / Fourrage`: temps, intensites, XP, formule de danger, biomes, gains et dangers.
- Onglet `Tour`: couts, niveau requis, securite max/initiale, gain, tick, cout vitalite, decroissance, risque minimum, coefficient de reduction, slots et labels.
- Les valeurs sont versionnees/exportables en JSON; synchro automatique dashboard -> app runtime non branchee.

### 7. Extensions futures

- Bonus type/enveloppe/modules sur les dangers.
- Restauration active de la Plaine.
- Corridors securises.
- Niveaux superieurs de Tour avec plusieurs slots.
- Refuge PTIBUG non branche.
- Lisiere lointaine non active.

### 8. Attentes

- Le comportement sommeil/alcove n'est pas redefini par cette feature.
- Le Marche ne lit pas encore population/securite.
- Les valeurs dashboard doivent encore etre reliees a une edition runtime distante si besoin.

## REPOS ET RECUPERATION V1

### 1. Fichiers crees ou modifies

- `ptipote-app/lib/features/figurines/ptipote_stats_config.dart`: ajoute `PtipoteRestState`, les seuils de Repos, bonus/malus XP/rendement, faim max suralimentee et malus d'indigestion.
- `ptipote-app/lib/features/game/craft_config.dart`: ajoute `FoodType` (`meal`, `drink`) et transforme `Repas simple` en repas: `+35 faim`, `+5 Vitalite`.
- `ptipote-app/lib/features/game/zone0_game_state.dart`: ajoute `restOverrides`, persistence Firebase, recuperation sommeil, perte naturelle de Repos, perte de Repos en mission, faim jusqu'a 120 et humeur basee sur Repos.
- `ptipote-app/lib/features/game/refuge_page.dart`: affiche l'etat de Repos, l'indigestion, les bulles sommeil/indigestion et applique les bonus/malus Repos aux estimations Lisiere.
- `ptipote-dashboard/ptipote-stats-config.json`: expose les parametres Repos/Nourriture.
- `ptipote-dashboard/craft-config.json`, `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js`: expose `FoodType` et les nouvelles valeurs Repas/Boisson.

### 2. Nouvelle statistique Repos

- Valeur: `0` a `100`.
- Valeur par defaut: `100` si aucune sauvegarde Firebase n'existe.
- Sauvegarde: `users/{uid}/game/zone0.restOverrides`.
- Simulation hors ligne: `lastSimulationAt` sauvegarde le dernier calcul; au retour dans l'app, les minutes ecoulees appliquent faim, Repos, recuperation Vitalite, contribution Tour et decroissance securite.
- Seul le sommeil restaure le Repos.
- Le Confort n'est pas developpe dans cette etape; il deviendra plus tard un multiplicateur de recuperation du Repos selon qualite de couchage, decoration, niveau des alcoves, etc.

### 3. Etats de Repos

- `Bien repose`: `80-100`, bonus `+10% XP`, `+10% rendement`.
- `Repose`: `50-79`, etat normal.
- `Fatigue`: `20-49`, malus `-10% XP`, `-5% rendement`.
- `Extenue`: `0-19`, refuse les longues missions, conserve les malus et rentre dormir via la logique de repos existante si fatigue.
- Les seuils sont configurables dans `ptipote_stats_config.dart` et le JSON dashboard.

### 4. Sommeil et Vitalite

- Sommeil:
  - Repos: `+2 par minute`.
  - Vitalite: `+1 par minute`.
- Vitalite reste le carburant des missions, crafts, Tour et futures activites.
- Nourriture ne restaure jamais le Repos.
- La barre sous les P'TIPOTES endormis est remplacee par un cartouche de temps restant avant Repos complet.

### 5. Faim et suralimentation

- Faim normale: `0-100`.
- Suralimentation autorisee jusqu'a `120`.
- Si Faim `80-100`: bonus passif de recuperation naturelle de Vitalite `+25%`.
- Si Faim `>100`: etat Indigestion, icone dediee, `-25% recuperation Vitalite`, `-10% XP`.
- La faim redescend par son rythme normal; aucun reset instantane.

### 6. Categories de nourriture

- `FoodType.meal`: repas, restaure surtout la Faim.
- `FoodType.drink`: boisson, restaure surtout la Vitalite.
- `Repas simple` V1: `meal`, `+35 faim`, `+5 Vitalite`.
- `Boisson tonique` V1: `drink`, `3 Organique + 4 Eau`, produit `2`, `+5 faim`, `+15 Vitalite`.
- Les futures recettes Craft doivent definir `foodType`.

### 7. Bonheur et besoins

- Le bonheur garde les trois besoins:
  - Nourri: `faim > 30`.
  - Repose: etat `Repose` ou `Bien repose`.
  - Caline: dernier calin encore valide.
- Les bulles possibles utilisent maintenant:
  - repas/faim;
  - sommeil si Repos faible;
  - coeur si calin manquant;
  - indigestion si Faim > 100.

### 8. Dashboard

- Section Stat Ptipote expose:
  - `maxRest`, recuperation sommeil, perte naturelle, perte mission;
  - seuils Bien repose/Repose/Fatigue/Extenue;
  - bonus faim bien nourrie, seuil indigestion, malus indigestion, faim maximale.
- Section Craft expose `FoodType` sur les nouvelles recettes locales.
- Synchro automatique dashboard -> runtime non branchee; exporter JSON puis reporter dans les configs Dart si necessaire.

## Kernel V1 — Progression, Population Et HUD

### 1. Fichiers

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/kernel_config.dart` | Source Dart V1: population de depart, capacites par niveau du Cœur, bien-etre, missions Kernel, plans. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Stocke `currentPopulation`, `bioBatteries`, `campWellbeing`, compteurs de missions, missions Kernel terminees et persistance Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | HUD principal et ecran Kernel a 4 onglets: Mission principale, Demandes, Plans, Progression. |
| `ptipote-dashboard/kernel-config.json` | Miroir JSON modifiable: Camp, HUD, recompenses population, missions et plans Kernel. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Onglet dashboard `Camp / Kernel`. |

### 2. HUD

- Affiche uniquement les stats camp principales:
  - Population `currentPopulation / populationCapacity`.
  - Bio-batteries.
  - Bien-etre `campWellbeing %` avec couleur rouge/orange/verte.
- Ne pas afficher Securite ni Vegetalisation dans le HUD: elles restent sur Tour et Cœur du Camp.

### 3. Population

- `populationCapacity` depend uniquement du niveau du Cœur via `kernelConfig.populationCapacityForCampHeartLevel`.
- Le Cœur augmente la capacite, mais n'ajoute pas d'habitants.
- Les habitants arrivent via les missions Kernel seulement.
- Population de depart V1: `4`, pour permettre a la premiere mission `+1 habitant` d'etre testable avec une capacite Camp de `5`.

### 4. Kernel

- Onglet Mission principale: mission active principale, actuellement `Construire le Fablab`.
- Onglet Demandes: maximum 3 demandes secondaires.
- Onglet Plans: bibliotheque de batiments, verrouilles en gris si le niveau du Cœur est insuffisant.
- Onglet Progression: stade actuel, niveau du Cœur, population, bien-etre, prochain objectif majeur.

### 5. Missions Et Boite Aux Lettres

- Missions generiques: `id`, type, titre, description, condition, recompenses, message consequence.
- Conditions V1:
  - Fablab construit.
  - Tour construite.
  - 5 repas prepares.
  - 3 missions en Plaine terminees.
- Les recompenses ajoutent la population sans depasser la capacite.
- Les missions terminees et les recompenses de population versees sont persistees separement. Une recompense bloquee par la capacite est conservee puis versee automatiquement quand le Cœur augmente la capacite. Les anciennes sauvegardes sont reconciliees une seule fois a partir de leur population deja creditee.
- La Boite aux lettres recoit uniquement le message consequence via `PtipoteMissionReport.system`.
- Le Kernel affiche les objectifs, la Boite raconte les resultats.

### 6. Attentes

- Commerce, routes commerciales, social, co-training, Refuge PTIBUG, Lisiere lointaine, evolution enveloppes et Mairie non branches.
- Bio-batteries sont affichees et persistantes, mais pas encore generees par une boucle dediee.
- Dashboard lit/exporte le JSON; synchro runtime automatique non branchee.

## Ou Modifier Selon La Demande

| Demande | Modifier en premier | Verifier aussi |
| --- | --- | --- |
| Changer style global app | `app_theme.dart` | `HomePage`, `FigurinesPage`, `NfcPage` pour tailles specifiques. |
| Changer carte PTIPOTE app | `figurines_page.dart` | `nfc_page.dart` pour garder scan et inventaire coherents. |
| Changer carte scan PTIPOTE | `nfc_page.dart` | `figurines_page.dart` pour garder la meme UI. |
| Changer image figurine | `ptipote_image.dart` | Assets et mapping espece/type. |
| Modifier adoption | `nfc_page.dart` | `FigurineService.saveScannedFigurine`, `firestore.rules`. |
| Modifier transfert | `figurine_service.dart` | `figurines_page.dart`, `nfc_page.dart`, `firestore.rules`, notifications. |
| Modifier confirmation scan transfert | `nfc_page.dart` | `FigurineService.confirmIncomingTransfer`, `firestore.rules`. |
| Modifier amis | `friend_service.dart` | `friends_page.dart`, `firestore.rules`, notifications. |
| Modifier chat | `chat_service.dart` | `chats_page.dart`, `chat_page.dart`, notifications/rules. |
| Modifier badges notification | `home_page.dart` | `notification_service.dart`, clear/read logic dans pages cibles. |
| Modifier push telephone | `push_notification_service.dart` | `functions/index.js`, Firebase Messaging, APNs. |
| Modifier roles | `user_profile_service.dart` | `profile_page.dart`, `firestore.rules`, `NfcPage` debug. |
| Modifier webapp publique | `ptipote-webapp/` | `publicFigurines` dans `FigurineService`. |
| Modifier dashboard interne | `ptipote-dashboard/` | `firestore.rules` admin/dev. |
| Modifier prototype Zone 0 local | `ptipote-app/ptipote-game/` | Garder HTML/CSS/JS sans framework, tester via serveur statique. |
| Ajouter une fonction V1 mobile | Data card puis fichier source de verite Flutter | Verifier handoff Zone 0, navigation Ilot/P'TIPOTES/Journal, scan contextuel. |

## Conventions Importantes

- UI publique: ne pas afficher UID, trace Firebase, champs transfert, infos debug sauf role `dev/admin`.
- Debug NFC: visible uniquement avec `canSeeDiagnostics`.
- Donnees publiques webapp: passer par `publicFigurines`, pas par `users/{uid}/figurines`.
- Profil searchable: passer par `publicProfiles`.
- Les rules Firestore sont une partie du code. Si une ecriture change, mettre a jour `firestore.rules`.
- Quand une page ouvre des notifications, penser a les marquer comme lues pour eviter les badges persistants.
- Eviter les lectures cachees pour les donnees de scan/adoption/transfert: preferer les lectures serveur quand la fraicheur est critique.
- Ne pas hardcoder de logique de propriete dans l'UI si elle existe deja dans `FigurineService`.

## Commandes De Verification

Depuis `/Users/kevinjeanne/Dev/ptipote-webapp-1`:

```sh
flutter analyze
```

Si les rules changent:

```sh
firebase deploy --only firestore:rules --project ptipote-13508
```

Si les functions changent:

```sh
firebase deploy --only functions --project ptipote-13508
```

Pour formater Dart:

```sh
/Users/kevinjeanne/development/flutter/bin/dart format ptipote-app/lib
```

## Checklist IA Avant Commit

1. Lire ce fichier.
2. Identifier la feature et le fichier source de verite dans les tables ci-dessus.
3. Modifier le moins de fichiers possible.
4. Si Firestore write/read change, verifier `firestore.rules`.
5. Si notification push change, verifier `functions/index.js` et `push_notification_service.dart`.
6. Garder l'UI scan et Mes PTIPOTES visuellement coherente.
7. Lancer au minimum `flutter analyze` si du Dart a change.
8. Stager seulement les fichiers lies a la demande.
9. Si une fonction, un ecran, une route ou une collection est ajoutee: mettre a jour cette data card avant commit.
10. Commit puis push sur `main` si Kevin demande ou si le workflow courant le prevoit.
## Kernel Progression V1 — Confiance, Axes Et Plans

### Fichiers

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/kernel_progress_config.dart` | Source Dart des seuils XP, recompenses `ProgressEvent`, axes et Plans technologiques. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Moteur d'evenements, niveaux/XPs, decouvertes, activation, historique et persistance Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Onglets Kernel Plans et Progression, categories, activation et cartes de progression. |
| `ptipote-dashboard/kernel-progress-config.json` | Miroir Dashboard modifiable/exportable de la configuration Kernel Progression. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Editeur JSON additionnel dans l'onglet Camp / Kernel. |

### Confiance Et Axes

- La Confiance du Kernel est independante des axes et stocke niveau, XP et historique.
- Axes V1: `breeder` (Eleveur), `builder` (Batisseur) et `restorer` (Restaurateur). Ils ne sont pas des classes de P'TIPOTES.
- Les niveaux utilisent `trustXpRequiredBase`, `axisXpRequiredBase` et `xpRequiredMultiplier` dans `kernel_progress_config.dart`.
- L'historique est limite aux 50 dernieres entrees dans `users/{uid}/game/zone0.kernel.progressHistory`.

### Progress Events

- Types prepares: `buildingConstructed`, `buildingUpgraded`, `craftCompleted`, `missionCompleted`, `pollutionObserved`, `ecosystemLevelUp`.
- Branches V1: construction Fablab/Tour/Marche, craft Cuisine/Atelier termine, mission Lisiere terminee et incident Pollution.
- Chaque gain vient de `kernelProgressConfig.eventRewards`, jamais des widgets.
- `buildingUpgraded` et `ecosystemLevelUp` sont prepares pour les futures actions correspondantes.

### Plans Et Decouvertes

- Etats: `unknown`, `discovered`, `ready`, `active`.
- Plans V1: Meuble simple actif apres construction du Fablab, Filtre, Cartouche de filtration, Tenue ombragee, Ventilation Termite et Lumiere solaire.
- Une observation passe le plan a `discovered`; lorsque Confiance et axe requis sont atteints, il devient `ready`; le joueur utilise `Activer le Plan` pour le rendre `active`.
- Les recettes Atelier sont filtrees par plan actif et le moteur refuse egalement un lancement non actif.
- L'origine et le texte Kernel sont affiches dans la fiche de Plan; les observations et activations sont envoyees dans les rapports.

### Attentes

- Les detections exactes de biomes chauds, des batiments souterrains, des upgrades et des paliers ecologiques seront branchees lorsque ces donnees auront leur propre modele.
- Les categories Cuisine, Batiments et PTIBUG sont preparees dans le filtre Plans; les premiers Plans V1 actifs ciblent l'Atelier et les Installations.
- Le Dashboard exporte les valeurs. Comme les autres configs versionnees, il ne modifie pas le build mobile en direct.

# ARCHITECTURE DES BATIMENTS V1 - GENERATEUR, ATELIER ET MARCHE

## P'TIBUG V1 - Nurserie De Plaine (socle)

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/ptibug_config.dart` | Especes, couts, energie, durees, styles, slots et capacite de transport V1. |
| `ptipote-app/lib/features/game/building_construction_config.dart` | Projet `plaineNursery`, 20 Organique et 35 Mineral. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Etats Nurserie, Patterns actifs, ordre de creation, premier P'TIBUG et paquet de Donnee de trait. |

- Especes V1: Scarabe (Mineral), Hyme (Organique), Arac (opportuniste prepare). Le premier Pattern garanti a la fin du chantier est Scarabe; les autres restent prepares pour Kernel/Sourcier.
- Une creation consomme ses ressources et `energyUnits`, reste temporisee hors ligne, puis genere un style aleatoire et une Donnee de trait commune. Les P'TIBUG restent des entites distinctes des figurines P'TIPOTE.
- Firebase: `users/{uid}/game/zone0.ptibug` contient niveau de Nurserie, Patterns actifs, ordre de creation, P'TIBUG et Donnees. La production de biome, les slots UI, traits/modules equipables, fusion, Sourcier et Dashboard sont les prochaines integrations de cette fonctionnalite.

## Refonte Batiments - Projets De Construction V1

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/building_construction_config.dart` | Definitions V1 des projets, durees et coefficient Mineral `1.30`. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | `ConstructionProject`, etats generiques, depot/retrait, lancement, resolution hors ligne, application du niveau et sauvegarde Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Feuille de chantier reutilisable; Fablab, Tour et Marche migres vers le depot progressif. |

- Etats communs: `locked`, `available`, `collectingMaterials`, `readyToBuild`, `underConstruction`, `built`, `upgradeAvailable`, `upgrading`, `maxLevel`.
- Un projet garde ses exigences, apports reserves, niveau courant/cible, debut, fin et fin effective. Les materiaux peuvent etre recuperes avant le demarrage; ils sont bloques apres. `endsAt` est persiste dans `users/{uid}/game/zone0.buildings.projects`, donc le chantier est resolu une seule fois apres une absence.
- Le Fablab, la Tour et le Marche utilisent les memes controles: +1, +5, Max, recuperation par ressource puis `Commencer les travaux`. La Tour controle le niveau du Coeur et le Marche controle niveau du Coeur et Population avant de permettre les depots. Ces preconditions sont aussi verifiees par le moteur au lancement.
- La construction Fablab applique `atelierLevel`, conserve `fablabLevel` en compatibilite, initialise Cuisine niveau 1 et maintient le bonus de stock sur l'Atelier. Les chantiers Tour et Marche conservent leurs effets existants seulement lorsque le timer est termine.
- Migration de sauvegarde: un ancien `fablabLevel` initialise `atelierLevel`; Cuisine est initialisee au niveau 1 quand l'ancien Fablab etait construit. Les niveaux existants Tour, Marche et Recycleur ne sont pas supprimes.
- Maison et logements sont maintenant branches au projet commun: amelioration Maison, capacite d'alcoves persistante, logements agreges, habitants non loges, malus de Bien-etre et remerciement communautaire temporaire. Les boutons historiques de construction Tour/Marche sont conserves en compatibilite interne mais ne sont plus utilises par l'UI.

### Fablab - Unites Independantes

- `Cuisine`, `Atelier` et `Recycleur` possedent des niveaux independants dans `Zone0GameState`.
- L'ecran parent `Fablab` suit maintenant la navigation commune : les onglets Cuisine, Atelier et Recycleur restent les fonctions; `Amelioration` centralise les projets des trois unites; `Infos` explique leur independance. Aucun niveau moyen de Fablab n'est calcule ni affiche.
- Les projets `cuisine`, `atelier` et `recycler` reutilisent `ConstructionProject`: depots, retraits, timer et resolution hors ligne sont communs aux autres batiments.
- La Cuisine lit `cuisineLevel` pour les recettes et ses emplacements P'TIPOTE. L'Atelier lit `atelierLevel` pour ses emplacements et la capacite du stock global. Le Recycleur conserve `recyclerLevel` pour ses cycles et rendements.
- `fablabLevel` est conserve temporairement pour compatibilite de sauvegarde et est aligne sur `atelierLevel`; aucun niveau moyen n'est affiche dans l'interface.
- `building_construction_config.dart` contient les couts/durees prototypes des ameliorations. `ptipote-dashboard/fablab-config.json` et l'onglet Fablab exposent leurs limites et valeurs miroir; la synchronisation automatique Dashboard -> Flutter reste a brancher.

### Tour Et Marche - Ameliorations

- Les niveaux de Tour et Marche sont deja persistants dans `buildings.tower.currentLevel` et `buildings.market.currentLevel`. Leurs projets `securityTower` et `market` utilisent maintenant la feuille commune de depot et de travaux aussi pour les niveaux suivants.
- Tour: niveaux 1 a 3, avec respectivement 1, 2 et 3 slots de surveillance. Les rondes existantes restent actives pendant une amelioration; le nombre de slots ne change qu'a la fin du chantier.
- Marche: le niveau conserve le fonctionnement des ventes, et `marketSlotLimit` applique `saleSlotsPerLevel` (+3 au niveau 1) au niveau effectif apres fin de chantier. Les stocks et demandes existants ne sont pas retires pendant les travaux.
- `SecurityTowerPage` expose `Surveillance`, `Exploration`, `Meteo`, `Amelioration` et `Infos`. L'ecran Marche conserve ses fonctions actuelles et donne acces a `Amelioration` et `Infos` depuis sa carte principale.
- Les reglages de niveaux existants sont exposes par `security-tower-config.json` et `market-config.json` dans le Dashboard. Les couts/durees communs de chantier restent centralises dans `building_construction_config.dart` en attendant une edition Dashboard dediee.

### Dashboard - Architecture Et Logements

- `ptipote-dashboard/building-architecture-config.json` est le miroir editable/exportable des projets communs: coefficient Mineral, depots recuperables, comportement pendant une amelioration, couts et durees V1.
- `ptipote-dashboard/housing-config.json` expose les niveaux de Maison, alcoves, logements agreges, malus de Bien-etre et remerciement communautaire.
- L'onglet Dashboard `Batiments actifs` charge ces deux fichiers et peut les exporter. Comme les configurations Dart restent la source executee par Flutter en V1, un JSON exporte doit etre reporte dans le fichier Dart correspondant avant livraison; aucune modification directe de donnees Firebase n'est faite par le Dashboard.

### Notifications De Chantier

- La fin d'un `ConstructionProject` cree un unique rapport systeme persiste, marque par `notificationCreated` pour ne jamais etre duplique apres un retour hors ligne.
- Les rapports de chantier ont maintenant `sourceBuildingId`. La Maison conserve sa pastille globale de messages; les hotspots Fablab, Tour et Marche affichent aussi leur propre pastille tant que le rapport de chantier correspondant est non lu.
- L'ouverture de la boite aux lettres conserve son comportement existant: les messages sont marques lus, les pastilles disparaissent, et la suppression manuelle ne modifie ni niveaux ni gains.

### Maison Et Logements

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/housing_config.dart` | Niveaux de Maison, alcoves, cout/duree des logements, malus et bonus communautaire. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Capacites persistantes, chantier `housing`, calcul des habitants non loges et effet temporaire de remerciement. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Action Maison, fiche Amelioration/Logements et alcoves affichees selon la capacite. |

- La Maison part de la capacite visuelle existante de trois alcoves pour ne retirer aucune alcove aux anciennes sauvegardes. Les nouveaux paliers configures restent 2, 3, 4, 6 et 8; la migration conserve toujours la valeur la plus favorable deja possedee.
- Un logement ajoute trois places. `unhousedPopulation = max(0, currentPopulation - housingCapacity)` et applique `-3 Bien-etre` par habitant, plafonne a `-30`.
- La capacite initiale de logement est migree a la Population actuelle: aucun joueur existant ne recoit un malus brutal a la premiere ouverture. Les logements n'ajoutent jamais d'habitants.
- Apres un logement termine, le joueur peut depenser 2 Bio-batteries pour un bonus temporaire de Bien-etre de +3 pendant 48 h. Cet effet est sauvegarde avec ses timestamps et expire hors ligne.
- L'ecran Maison suit maintenant la structure commune : `P'TIPOTES` pour la scene active, les messages et l'inventaire; `Amelioration` pour Maison et Logements; `Infos` pour son role et ses limites.
- Si toutes les alcoves sont occupees, `waitingForBedIds` est persiste dans Firebase. Le P'TIPOTE reste indisponible, affiche une bulle sommeil et ne reçoit pas la recuperation d'alcove tant qu'une place ne se libere pas. Il conserve sa recuperation naturelle normale. La synchronisation des lits est rejouee pendant les ticks et au retour hors ligne.
- Attentes: le Dashboard HTML doit encore exposer `housing_config.dart`; une Pépiniere active reste preparee pour une prochaine iteration.

## Dechets Et Recycleur V1

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/waste_recycler_config.dart` | Configuration centralisee des Dechets, de l'Energie et des cycles du Recycleur. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Generation passive hors ligne, gains Lisiere, cuve, sortie, cycles, Energie et sauvegarde Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | Icone inventaire et onglet Recycleur du Fablab. |
| `ptipote-dashboard/waste-recycler-config.json` | Miroir editable/exportable de la configuration V1. |
| `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js` | Onglet Dashboard `Dechets / Recycleur`. |

- `Dechets` est une ressource de l'inventaire global, avec les memes stacks de 10 que les autres ressources. La Lisiere en rapporte un pourcentage aleatoire de 15 a 30 % des gains Organique + Mineral effectivement obtenus, apres les incidents.
- Le refuge produit des Dechets toutes les 120 minutes: `base + population / 5 + batiments construits / 3`. Le calcul est applique a partir du temps ecoule, est persiste et les excedents sont conserves dans `pendingWaste` (capacite configurable) lorsque l'inventaire est plein; ils sont re-injectes automatiquement des qu'une place se libere.
- Recycleur: actif seulement lorsque Fablab construit et Coeur niveau 2. Niveau initial 1, cuve 34, rendement `17 Dechets -> 10 ressources`, puis le cout diminue jusqu'a 13 aux niveaux futurs. Les repartitions sont bornees entre 7/3 et 3/7 Organique/Mineral.
- Energie: `1 Bio-batterie = 10 energyUnits`. Le bouton d'ouverture convertit volontairement une Bio-batterie; le Recycleur consomme une unite au demarrage de chaque cycle, jamais une Bio-batterie entiere.
- Les cycles sont automatiques, resolus hors ligne et gardent leur production dans un stock de sortie avant recuperation. Les cycles termines durant une meme resolution sont regroupes dans un seul rapport. L'UI distingue attente de Dechets, attente d'Energie, recyclage en cours, production prete et stock de sortie plein.
- Placeholders: bonus P'TIPOTE, upgrades du Recycleur, Mycelium, drag and drop et cout energie applique a tous les crafts ne sont pas encore actifs. `CraftRecipe.energyCost` est prepare avec une valeur par defaut de zero, sans modifier les crafts actuels.

## Tour, Exploration, Meteo Et Marchand V1

| Fichier | Role |
| --- | --- |
| `ptipote-app/lib/features/game/tower_operations_config.dart` | Seuils de bien-etre issus de la Securite, exploration, securite locale, meteo et marchand. |
| `ptipote-app/lib/features/game/zone0_game_state.dart` | Etats des biomes, explorations, securite locale, marchand et persistance Firebase. |
| `ptipote-app/lib/features/game/refuge_page.dart` | HUD cliquable, onglets Tour Surveillance/Exploration/Meteo et carte Marchand du Marche. |
| `ptipote-dashboard/tower-operations-config.json` | Miroir editable/exportable des reglages operationnels Tour. |

- La Securite du camp fournit un modificateur de Bien-etre visible dans le HUD: Vulnerable, Fragile, Stable, Protege ou Serein.
- Etats biome: `discovered`, `exploring`, `unlocked`. Seule la Plaine commence `unlocked`; les autres sont reveles a partir du seuil de securite puis debloques par exploration.
- Chaque biome conserve sa securite locale, derniere mission, derniere ronde et derniere decroissance. L'exploration ne modifie jamais cette securite: seule une ronde terminee l'augmente. L'absence d'activite declenche une decroissance lente.
- La Tour annonce un evenement meteo avec une preparation. `WeatherPreparationType` prepare les trois modes `craft`, `own`, `provide`; V1 affiche et utilise `provide` pour retirer l'objet seulement a validation.
- Le Marchand est volontairement une interaction de prototype: il propose des Plans contre des Bio-batteries, reste 24 h selon config et repart sans malus. La carte du Marche permet de le faire apparaitre pour test.
- Attentes: les effets mecaniques complets de chaque meteo, les rondes locales explicites et la generation aleatoire serveur du Marchand restent a enrichir; aucune boucle existante de mission, sommeil, craft ou vente n'est supprimee.
- Correctif exploration et rondes: l'exploration est une jauge de 100 %, avec sorties de 1 h, 2 h, 4 h ou 8 h (+10 % par heure theorique; echelle de test Lisiere). Les indices ressources apparaissent a 30 %, leur ratio a 50 % et les valeurs a 70 %. Une ronde utilise les memes choix de duree; 8 h remplissent 100 % de securisation et le gain est applique uniquement au retour. Chaque biome affiche son danger potentiel, sa reduction actuelle (maximum -30 % a 100 % de securisation) et sa jauge de securisation.
- Correctif Atelier: un emplacement manuel reste toujours disponible en plus des emplacements P'TIPOTE, qui augmentent avec le niveau de Fablab.
- Correctif Marche: les ressources sont demandees par stack de 10 et les objets par unite; les valeurs V1 sont Filtre 1, module 2, tenue/meuble 2, installation 3 Bio-batteries.

## 1. Architecture commune

- `ptipote-app/lib/features/game/zone0_game_state.dart` centralise les actions manuelles, les ordres temporises, l'occupation des P'TIPOTES, la simulation hors ligne et Firebase.
- Un batiment reste utilisable sans P'TIPOTE. L'affectation apporte un bonus, masque le P'TIPOTE de la Maison via `isBusy`, puis le rend disponible a la fin ou l'envoie au repos si sa Vitalite atteint le seuil configure.
- Etats prepares/reutilises: `helpingWorkshop`, `helpingMarket`, `helpingTower`, `resting`, `wanderingHome`, `onMission`.
- Aucun axe de confiance Kernel et aucune nouvelle enveloppe ne sont utilises comme bonus P'TIPOTE.

## 2. Generateur du Coeur

- Config: `ptipote-app/lib/features/game/camp_generator_config.dart`, miroir dashboard `ptipote-dashboard/camp-generator-config.json`.
- UI: second onglet `Generateur` dans `CampHeartPage`.
- Niveau 1: stock 30 Organique / 6 Mineral; cycle 5 Organique + 1 Mineral vers 1 Bio-batterie en 60 min.
- Les capacites et durees evoluent avec le niveau du Coeur. `generatorCycleStartedAt` permet de resoudre plusieurs cycles hors ligne sans depasser les ressources chargees.
- Firebase: `users/{uid}/game/zone0.campGenerator`.

## 3. Atelier

- Config et six recettes V1: `ptipote-app/lib/features/game/workshop_config.dart`, miroir `ptipote-dashboard/workshop-config.json`.
- Modele `WorkshopCraftOrder`: recette, quantite, progression, prochaine unite, ressources reservees, P'TIPOTE optionnel et statut.
- Les commandes sont limitees par les emplacements de l'Atelier: 1 au niveau 1, puis +1 emplacement par niveau. L'annulation conserve les objets termines et rend les ressources des unites restantes.
- Sans P'TIPOTE: duree normale. Avec P'TIPOTE: bonus vitesse de 1% par niveau plafonne a 15%, cout de 5 Vitalite par unite.
- A la fin, le P'TIPOTE redevient disponible; s'il atteint le seuil de repos, il rentre dans une alcove.
- Le prototype conserve les stacks globaux de 10; `stackLimit` est prepare dans les recettes pour une future gestion par type d'objet.
- Firebase: `users/{uid}/game/zone0.workshopOrders`; l'ancien champ unique `workshopOrder` est migre automatiquement a la lecture.
- Effets reels de Filtre, Cartouche, Tenue, Meuble, Ventilation et Lumiere restent a brancher.

### Convergence Cuisine / Atelier et compteurs

- `WorkshopCraftOrder` porte maintenant `area: workshop | kitchen`. Les commandes Cuisine et Atelier utilisent donc le meme cycle persistant: ressources reservees au lancement, commande manuelle ou P'TIPOTE, temps par unite, annulation avec remboursement des unites restantes, resolution hors ligne et rapport de fin.
- La Cuisine conserve son propre creneau manuel et ses propres emplacements P'TIPOTE; elle n'occupe jamais un creneau de l'Atelier. Les recettes Cuisine ont une `durationMinutes` configurable dans `craft_config.dart`. L'eau reste contextuelle et gratuite.
- `RefugePage` rafraichit les compteurs toutes les cinq secondes. Les missions de Lisiere, les explorations de biome et les rondes de Tour affichent desormais `Temps restant` au lieu d'une simple heure de retour. Les donnees de fin restent les timestamps Firebase existants, donc les compteurs restent justes apres fermeture et retour dans l'application.

## 4. Marche

- Config: `ptipote-app/lib/features/game/market_config.dart`, miroir `ptipote-dashboard/market-config.json`.
- Construction: Coeur niveau 1, population 5, cout 6 Organique + 6 Mineral.
- Trois emplacements dedies au niveau 1, puis +3 par niveau. Les cases vides ouvrent un ajout depuis le stock Maison; une pile contient 10 materiaux/crafts ou 1 equipement. Le stock Maison n'est jamais vendu automatiquement.
- `WorkshopRecipe.isEquipment` identifie les equipements V1: Tenue ombragee, Meuble simple, Ventilation Termite et Lumiere solaire.
- Sans P'TIPOTE: ventes automatiques selon Population et Bien-etre. Conversion V1: 5 points de valeur vers 1 Bio-batterie.
- Avec P'TIPOTE: cadence -10%, cout 5 Vitalite / 20 min, demandes d'habitants et livraison automatique.
- Demandes: maximum 3, retour aleatoire persistant, report sans perte si objet ou P'TIPOTE absent.
- Firebase: `users/{uid}/game/zone0.market` et `buildings.market`.

## 5. Tour

- Action manuelle `Recharger les balises`: +5 Securite, cooldown 10 min.
- Configuration Dart dans `security_tower_config.dart` et miroir dashboard `security-tower-config.json`.
- Les missions temporisees de surveillance existantes restent intactes.
- La feuille de selection par puces de la Lisiere est reutilisee pour l'affectation a la Tour, au Marche et a l'Atelier; elle affiche egalement les indisponibilites (mission, repos, autre batiment, vitalite basse).

## 6. Dashboard

- Onglet `Batiments actifs`: editeurs JSON exportables pour Generateur, Atelier et Marche.
- Les valeurs de recharge manuelle sont exposees dans `security-tower-config.json`.
- Les JSON restent versionnes: l'export Dashboard doit etre reporte dans les configs Dart pour modifier le build mobile.

## 7. Placeholders futurs

- Effets de confort, protections anti-Brume, qualite d'objet, bonus de traits/preferences/modules, lignées et batiments energetiques de biomes ne sont pas actifs.
- Recycleur reste verrouille au Coeur niveau 2.
- Les axes de confiance du joueur ne modifient pas les bonus des P'TIPOTES.
# Finition refonte bâtiments - niveaux, notifications et hors ligne

- `ptipote-app/lib/features/game/workshop_config.dart` : le niveau de Cuisine et d’Atelier ajoute jusqu’à 20 % de vitesse de fabrication et un slot P’TIPOTE par niveau. Le créneau manuel reste indépendant.
- `ptipote-app/lib/features/game/waste_recycler_config.dart` : le Recycleur augmente sa capacité de sortie de 20 ressources par niveau, tout en conservant son rendement Déchets/cycle existant.
- `ptipote-app/lib/features/game/security_tower_config.dart` : la Tour gagne +2 Sécurité par tick et +2 lors de la recharge manuelle à chaque niveau supplémentaire. Les slots restent 1/2/3.
- `ptipote-app/lib/features/game/market_config.dart` : le Marché ajoute trois slots, une demande active et 10 % de cadence de vente par niveau, avec un plafond de cadence à 50 % de l’intervalle de base.
- `ptipote-app/lib/features/game/zone0_game_state.dart` : les badges parent utilisent une table unique (Fablab, Tour, Marché, Maison, Cœur). Les chantiers possèdent `completeAt`, utilisé par le retour hors ligne afin d’empêcher une seconde finalisation et une seconde notification.
- Affectation Marché : un P’TIPOTE reste affecté même lorsque le stock de vente est vide. Il peut ainsi noter et livrer les demandes; son retour ne se produit que sur action manuelle ou lorsque sa Vitalité atteint le seuil de repos.
- Migration : les niveaux indépendants sont bornés à leur configuration, l’ancien `fablabLevel` reste migré vers Atelier, la Cuisine reste au niveau 1 pour un ancien Fablab construit, et la capacité de logement ne descend jamais sous la population existante.
- Tests : `ptipote-app/test/construction_project_test.dart` couvre le dépôt/lancement simulé, le retour après échéance et l’idempotence de fin de chantier, ainsi que les effets de niveau principaux. Le test Firebase réel reste manuel sur un compte existant, car il dépend de son état distant.
# P'TIBUG V1 - NURSERIE ET PRODUCTION

## Cultivation P'TIBUG — Armatures et cuves

- Les nouvelles créations ne produisent plus directement un P'TIBUG : `Zone0GameState.startPTibugCreation` fabrique d'abord une **Armature** avec les coûts historiques de l'espèce, pendant 3 h par défaut. Une Armature terminée est stockée et doit être placée volontairement dans une cuve de la Nurserie.
- Les modèles sauvegardés sont `PTibugArmature`, `PTibugCultivationTank` et `PTibugCultivationOperation`, sous `users/{uid}/game/zone0.ptibug`. Chaque identifiant de cuve, Armature, opération et résultat est unique ; ouvrir une cuve terminée ne peut créer qu'un seul P'TIBUG.
- La Nurserie débloque un emplacement de cuve par niveau, mais les cuves supplémentaires exigent un dépôt progressif puis des travaux. Une seule première cuve est accordée par sauvegarde (`firstCultivationTankGranted`), y compris après migration ; les Refuges ne possèdent pas de cuves.
- Une Cultivation demande 24 h **actives**. Les réserves de cuve sont locales : Organique, Minéral et Énergie. Elles sont calculées hors ligne jusqu'à l'instant exact d'épuisement, puis l'opération passe en pause sans perdre ni Armature ni progression et reprend automatiquement après ravitaillement. Une Bio-batterie verse 10 Énergies avec la conversion commune.
- Les ratios de test sont configurables : Hymé consomme surtout de l'Organique, Scarabé surtout du Minéral et Arac est équilibré. Les capacités correspondent à environ 8 h d'autonomie ; le Dashboard pilote les ratios, capacités indirectes, seuil critique, construction et durées.
- Une séance de tapotement réussie ajoute 1 h active par défaut, sans consommer une heure de nutriments. Les timestamps persistés limitent le bonus à 3 séances sur 24 h et imposent 4 h entre deux séances. La V1 expose l'action métier ; le composant rythmique pourra remplacer son déclenchement sans modifier la sauvegarde.
- Migration : les P'TIBUG existants restent inchangés. Un ancien `PTibugCreationOrder` est volontairement conservé jusqu'à sa résolution unique par le flux historique ; les nouvelles demandes créent uniquement des Armatures.
- Fichiers : `ptibug_config.dart`, `remote_zone0_settings.dart`, `zone0_game_state.dart`, `refuge_page.dart`, `ptibote-dashboard/ptibug-config.json`, `ptipote-dashboard/app.js`.

- `ptipote-app/lib/features/game/ptibug_config.dart` centralise les espèces Scarabé, Hyme et Arac, leurs recettes de création, styles, slots de Nurserie, cycles, capacité et modules V1.
- `ptipote-app/lib/features/game/zone0_game_state.dart` conserve les P'TIBUG dans le document Firebase `ptibug`, termine la création hors ligne et résout les cycles terminés sans les verser automatiquement dans l'inventaire. La collecte est explicite afin de respecter la capacité globale.

### Patterns P'TIBUG - Kernel

- `ptipote-app/lib/features/game/ptibug_config.dart` centralise les trois Patterns V1 et leur lien avec les Plans Kernel : Scarabé, Hymé et Arac.
- `ptipote-app/lib/features/game/kernel_progress_config.dart` définit les Plans de Pattern. Aucun Pattern d'espèce n'est offert par défaut : le premier est sélectionné dans la Nurserie, puis activé explicitement dans les Plans du Kernel. Hymé et Arac restent découvrables via le Kernel ou le Sourcier.
- `ptipote-app/lib/features/game/zone0_game_state.dart` active un Pattern lors de l'activation de son Plan Kernel et persiste la liste dans `users/{uid}/game/zone0.ptibug`. Les créations restent refusées tant que le Pattern concerné n'est pas actif.
- La Nurserie affiche tous les Patterns, avec leur état Kernel. Seuls les Patterns actifs proposent le bouton `Créer`.
- Attente : la vente ou le partage social de Patterns via le Marché/Sourcier reste une étape ultérieure ; aucun Pattern n'est consommé à la création.

### Premier P'TIBUG et Sourcier V1

- À la première ouverture de la Nurserie, une modale de choix unique propose Scarabé, Hymé ou Arac. Les icônes pulsantes gris-bleu, jaune et rouge signalent les trois choix possibles. Aucun Pattern d'espèce n'est attribué automatiquement aux nouvelles sauvegardes.
- Le choix est gratuit et sauvegardé dans `users/{uid}/game/zone0.ptibug.starterChoiceMade`. Il rend le Pattern choisi `ready` dans le Kernel, sans l'activer immédiatement. Une seconde modale explique que les autres Patterns viennent du Kernel ou du Sourcier et propose d'ouvrir les Plans.
- L'activation dans l'onglet Plans rend le Pattern créable dans la Nurserie. La mission principale `Créer ton premier P'TIBUG` apparaît après le choix et explique cette boucle. Les sauvegardes existantes ayant déjà un Pattern actif restent considérées comme ayant effectué ce choix afin d'éviter toute perte de progression.
- Le Marché héberge le `Sourcier du savoir`. Lors de sa présence, il propose les Patterns Hymé et Arac encore inactifs contre des Bio-batteries configurées dans `ptibug_config.dart`. L'achat active directement le Pattern et le Plan Kernel correspondant.
- Les découvertes par événements Kernel restent actives en parallèle : premier P'TIBUG pour Hymé, trois collectes P'TIBUG pour Arac. Les Plans déjà acquis ne sont pas proposés une seconde fois par le Sourcier.
- Le cycle du Sourcier est configuré dans `tower_operations_config.dart`, publié dans `gameConfigs/zone0.zone0Settings.towerOperations` et utilisé hors ligne par `Zone0GameState`: une visite dure deux heures, avec au plus trois passages par jour et quatre a huit heures entre deux arrivées.
- Le Marché conserve un appel manuel du Sourcier : il consomme `1` Bio-batterie, puis programme une arrivée aléatoire entre `5` et `15` minutes. La demande est sauvegardée dans l'état Marché, respecte les trois passages quotidiens et ne peut pas être doublée pendant l'attente.
- Les horaires `merchantAvailableUntil` et `merchantNextArrivalAt`, ainsi que le compteur journalier, sont sauvegardés dans `users/{uid}/game/zone0.market`. Une ancienne visite de vingt-quatre heures est ramenée a une fenetre de deux heures a sa prochaine resolution.
- Le Sourcier part automatiquement lorsque toutes les offres ont ete achetees. Le joueur peut aussi utiliser `Terminer la transaction` pour fermer le passage avant son terme; les offres restantes sont alors abandonnees et la prochaine arrivee est planifiee.

### Nurserie P'TIBUG - UI Données et Modules

- `ptipote-app/lib/features/game/refuge_page.dart` : la Nurserie possède désormais les onglets `Aperçu`, `Créer`, `Collection`, `Données` et `Amélioration`.
- L'Aperçu affiche chaque P'TIBUG affecté à la production avec son icône, sa réserve actuelle sous forme de pastille et le compte à rebours avant le prochain cycle. Un ordre de création conserve également l'icône de l'espèce et son délai restant.
- La `Collection` affiche chaque P'TIBUG comme une carte : espèce, niveau, XP, réserve, état de production, Donnée équipée et emplacements de Modules. Un tap ouvre sa fiche d'équipement.
- La fiche d'équipement permet d'attribuer une Donnée non utilisée par un autre P'TIBUG et d'équiper un Module déverrouillé, dans la limite des emplacements de la Nurserie. Les règles métier existantes restent appliquées par `Zone0GameState`.
- L'onglet `Données` présente le type, la rareté, le bonus de production et le propriétaire éventuel de chaque Donnée. Il propose une fusion lorsqu'une paire identique non équipée est disponible.
- Le même onglet présente les Modules Ailes, Pinces et Réservoir, avec leur bonus réel et leur état verrouillé/déverrouillé.
- Attente : l'origine détaillée des Données, les probabilités, les images dédiées et les réglages Firestore/Dashboard des traits et Modules seront ajoutés pendant les étapes Dashboard et UI visuelle enrichie.
- Production : Scarabé produit du Minéral, Hyme de l'Organique et Arac une combinaison aléatoire d'Organique, Minéral ou Déchets. La capacité individuelle bloque les cycles pleins. XP : +1 par cycle.
- Mycélium : la ressource est produite exclusivement par une Donnée Décomposeur. Elle n'est ajoutée à aucune recette existante dans cette étape.
- `ptipote-app/lib/features/game/refuge_page.dart` expose une Nurserie P'TIBUG dans la Plaine/refuge : construction commune, Aperçu, Création, Collection et Amélioration. Les P'TIBUG peuvent être installés ou retirés des slots actifs et leur production récupérée.
- État préparé : les champs trait, modules, XP, style et prochaine production sont sauvegardés. L'UI détaillée des Données, de la fusion et de l'équipement de Modules reste à terminer avec les offres Sourcier/Dashboard correspondantes.
- Complément : les Données peuvent désormais être attribuées à un P'TIBUG et deux Données non équipées de même trait et grade se fusionnent de façon garantie. Les Modules déverrouillés respectent le nombre de slots de la Nurserie; Réservoir est offert à la première création. Les événements Kernel dédiés alimentent Confiance et axe Éleveur lors de création, équipement, fusion et collecte.

## Dashboard Interne Et Configuration Distante Zone 0 (2026-07-17)

### Organisation Kernel et Craft

Les prérequis d'axes des recettes sont désormais lus depuis le Plan Kernel dont `workshopRecipeId` correspond à la recette. Les anciens champs de recette restent un fallback pour les sauvegardes et configurations antérieures. Les récompenses d'axes sont entièrement configurables dans `kernelProgress.eventRewards`; les événements distincts couvrent les missions Lisière, les missions Tour, les crafts réalisés par un Ptipote, l'alimentation et le passage à l'état Heureux.

Le passage à l'état `Bien reposé` est dédupliqué par P'TIPOTE et par cycle de repos dans `wellRestedRewardedIds`, sauvegardé dans `users/{uid}/game/zone0`. Le marqueur est retiré lorsque le repos redescend sous le seuil configuré, ce qui autorise une nouvelle récompense au cycle suivant.

Les définitions globales de traits P'TIBUG vivent dans `gameConfigs/zone0.ptibug.traitDefinitions`. Elles contiennent un identifiant stable, un nom, une description, des effets par ressource et des multiplicateurs par grade. Les instances joueur conservent `type` et `grade` historiques et peuvent porter `definitionId`; Flutter résout d'abord `definitionId`, puis le type historique. Les définitions Dart restent le fallback hors ligne.

### Migration Traits P'TIBUG Extensibles

`PTibugTraitData.definitionId` est la référence de runtime. À la lecture d'une ancienne sauvegarde, Flutter récupère automatiquement `type` comme identifiant de définition; à l'écriture, il conserve également `type` pour les anciennes versions de l'app. Les nouveaux traits sont tirés uniquement parmi les définitions `isActive: true`. Les traits désactivés restent interprétés pour ne jamais dégrader une sauvegarde joueur. La production, l'équipement, la fusion, les libellés, descriptions et couleurs passent par la définition distante; les anciennes définitions Dart restent disponibles hors ligne.

Le Dashboard P'TIBUG permet de créer une définition avec un identifiant stable, un nom, une description, un effet de ressource, les multiplicateurs de grade et une couleur. L'identifiant n'est pas modifiable après création. Pour retirer un trait du tirage sans casser les traits acquis, régler `isActive` sur `false`; ne pas supprimer une définition déjà publiée.

### Dashboard Maison Et Habitations

Dans l'onglet `Atelier & Maison`, la configuration `housing` est présentée en deux cartes sans changer le format Firestore: `Maison · alcôves Ptipotes` contient `houseMaxLevel` et `alcovesByHouseLevel`; `Habitations · habitants` contient la capacité résidentielle, les coûts, durées et modificateurs de bien-être. Les valeurs négatives de `towerOperations.wellbeingBands.*.wellbeingModifier` sont valides: elles représentent les pénalités de sécurité basse et sont explicitement acceptées par la validation avant publication.

La validation accepte aussi les booléens tels que `lisiere.upcomingBiomes.*.availableSoon`, affichés comme cases à cocher dans le Dashboard. Seules les valeurs numériques non finies ou négatives hors champs de pénalité autorisés bloquent une publication.

Les coûts d'habitation sont progressifs mais entièrement configurables dans `housing`: `initialHousingOrganicCost` et `initialHousingMineralCost` définissent le premier logement; `housingOrganicCostIncreasePerUnit` et `housingMineralCostIncreasePerUnit` définissent l'augmentation par logement déjà construit. Mettre les deux augmentations à `0` conserve un coût fixe. Le multiplicateur minéral global de construction reste appliqué ensuite par `buildingConstructionConfig.mineralCostMultiplier`.

### Cycle Météo De La Tour

`towerOperations` contient `maxWeatherEventsPerDay`, `minimumWeatherIntervalMinutes` et, pour chaque entrée de `weatherEvents`, un `occurrenceWeight`. Les poids sont relatifs: `2 / 3 / 1` signifie 2 chances sur 6 pour la première météo, 3 sur 6 pour la deuxième et 1 sur 6 pour la troisième. Le calendrier joueur est sauvegardé dans `users/{uid}/game/zone0.weather` avec le jour, le compteur quotidien, la prochaine date éligible, les alertes actives et les déclenchements manuels déjà consommés.

Une alerte active instancie une mission Kernel à partir du template météo correspondant; son identifiant porte l'identifiant de l'alerte, ce qui la rend répétable à chaque événement. À la fin de l'intempérie, la Maison reçoit un rapport précisant si la préparation a été validée. Le Dashboard Tour propose un déclenchement manuel de test: il publie un identifiant de commande global dans `towerOperations`; chaque joueur connecté avec une Tour construite peut consommer cette commande une seule fois.

- L'onglet Dashboard est nommé `Kernel`. Il est rangé en accordéons : `Bâtiments` (missions de construction), `Missions`, `Éditeur de mission`, `Confiance, axes et récompenses`, puis `Plans & Patterns`.
- Les prérequis d'un craft ne doivent plus être édités dans la carte Craft : `patternRequired` est activé par défaut. Lorsqu'une recette est créée avec ce réglage, le Dashboard ajoute son Plan Kernel `craft-{recipeId}` si nécessaire.
- Les prérequis de Plan configurables sont : Confiance du Kernel, Éleveur, Bâtisseur, Restaurateur et niveaux de bâtiments. Les Plans générés portent `workshopRecipeId` afin de relier la recette au Plan.
- Le bouton `Aller aux prérequis` du formulaire Craft ouvre l'onglet Kernel, section `Plans & Patterns`.
- L'onglet P'TIBUG existant reste la source Dashboard de la Nurserie, espèces et Patterns. Les données de traits sont actuellement des entités joueur générées dans `users/{uid}/game/zone0.ptibug.traitData`; ne pas les confondre avec les Patterns de configuration.

### Source, droits et publication

- Dashboard déployé : `https://ptipote-13508.web.app` ; sources : `ptipote-dashboard/index.html`, `ptipote-dashboard/app.js`, `ptipote-dashboard/styles.css`.
- Document de configuration : `gameConfigs/zone0`. Les valeurs de jeu sont sous `zone0Settings`; les statistiques P'TIPOTE restent sous `ptipoteStats`.
- Seuls les rôles existants `admin` et `dev` peuvent écrire `gameConfigs/{configId}`. Les rôles viennent de `users/{uid}.role`; pas de custom claims. Voir `firestore.rules`.
- Le Dashboard charge d'abord les JSON versionnés de `ptipote-dashboard/*.json`, fusionne la publication Firestore puis écrit l'ensemble de `zone0Settings` avec `setDoc(..., { merge: true })` après validation.
- Flutter lit et écoute `gameConfigs/zone0` via `ptipote-app/lib/features/game/remote_game_config_service.dart`. Le mapping/fallback se trouve dans `remote_zone0_settings.dart`. Aucune progression joueur n'est écrite dans `gameConfigs` : elle reste dans `users/{uid}/game/zone0`.

### Sections Zone 0 publiees

- `zone0Settings` : `kernel`, `kernelProgress`, `campHeart`, `lisiere`, `tower`, `towerOperations`, `fablab`, `workshop`, `craft`, `market`, `housing`, `ptibug`.
- Les valeurs Dart `default...Config` restent le fallback hors ligne ou lors d'une configuration distante invalide/incomplète.
- Le Dashboard publie depuis les onglets Cœur du Camp, Lisière, Tour, Fablab, Craft, Marché, Atelier/Maison et Camp/Kernel. Les règles Firestore n'exposent aucun droit admin côté client.

### Cœur du Camp et Camp

- `CampHeartStageConfig.organicRequiredForNextLevel` est le coût d'Organique à investir pour le niveau suivant, et non une XP. Les anciennes données `xpRequiredForNextLevel` sont encore lues en compatibilité, mais les nouvelles publications utilisent `organicRequiredForNextLevel`.
- `CampHeartState` dans `refuge_page.dart` conserve `vegetalizationXp` comme compteur de progression sauvegardé, alimenté uniquement par les dépôts d'Organique.
- Les réglages Camp/capacité (population de départ, capacité par niveau de Cœur, bien-être et demandes d'accueil) sont stockés dans `zone0Settings.kernel`, mais édités dans l'onglet Dashboard `Cœur du Camp` pour refléter leur rôle produit.

### Craft unifie Cuisine et Atelier

- Source Flutter : `craft_config.dart`; réglages généraux Atelier : `workshop_config.dart`.
- Toutes les recettes sont dans `zone0Settings.craft.recipes`, y compris Filtre, Cartouche de filtration, Tenue ombragée, Meuble simple, Ventilation Termite et Lumière solaire. Elles ne doivent pas réapparaître dans l'éditeur Atelier/Maison/Logements.
- `CraftRecipe` porte `craftSection` (`cuisine` ou `atelier`), coûts, durée, résultat, pile, consommable, prérequis Cuisine/Atelier et prérequis Kernel (Confiance, Éleveur, Bâtisseur, Restaurateur).
- Le Dashboard permet ajout, édition, suppression et publication des recettes. `simpleMeal` est protégé comme recette de départ afin de conserver un fallback de jeu valide.
- Les ordres Cuisine et Atelier partagent `WorkshopCraftOrder`; les recettes sont filtrées par section dans `RefugePage` et les prérequis sont validés dans `Zone0GameState`.

### Kernel, Patterns et missions configurables

- Configurations : `kernel_config.dart` (missions/refuge) et `kernel_progress_config.dart` (Confiance, axes, Plans/Patterns). Les deux sont appliquées depuis `zone0Settings.kernel` et `zone0Settings.kernelProgress`.
- Le Dashboard Camp/Kernel édite les récompenses d'événements, Plans et Patterns, et peut créer/supprimer une mission.
- Une `KernelMissionConfig` peut définir : type `main`, `refugeRequest` ou `weather`; prérequis de bâtiments/niveaux; Confiance Kernel; niveaux Éleveur/Bâtisseur/Restaurateur; produit demandé; habitants, Bio-batteries, XP Confiance, ressources et Pattern/Plan comme récompenses.
- Les missions avec produit demandé se valident par `Zone0GameState.fulfillKernelMission`. Les autres missions se valident automatiquement lorsque leurs conditions et prérequis sont remplis. Les IDs terminés et les récompenses Population restent persistés dans `users/{uid}/game/zone0`.
- `RefugePage` affiche les demandes, un bouton de remise pour le produit requis, et un onglet Kernel `Météo` pour les missions de type météo. Un Pattern récompensé active le Plan correspondant dans `activeKernelPlanIds`.

### P'TIBUG et Patterns publiés à distance

- `ptipote-dashboard/ptibug-config.json` est la base versionnée des coûts de Nurserie, espèces, cycles, capacités, prix du Sourcier et liens Pattern/Plan. L'onglet Dashboard `P'TIBUG` l'édite puis le publie dans `gameConfigs/zone0.zone0Settings.ptibug`.
- Chaque espèce accepte `creationCost` (dont `Mycélium` peut être ajouté ultérieurement), `creationEnergyCost`, `creationBioBatteryCost` et `creationMinutes`. Les valeurs V1 de départ sont 30 Organique, 15 Minéral et 10 Bio-batteries ; aucun coût de Mycélium n'est imposé tant qu'il n'est pas configuré.
- `ptipote-app/lib/features/game/remote_zone0_settings.dart` reconstruit `PTibugConfig` depuis Firestore et garde `defaultPTibugConfig` comme fallback hors ligne ou pour une valeur distante absente.
- `ptipote-app/lib/features/game/ptibug_config.dart` distingue `defaultPTibugConfig` (versionné) de `pTibugConfig` (configuration active). Aucun P'TIBUG, Pattern actif, ordre de création ou production du joueur n'est écrit dans la configuration distante.
- Les Patterns restent des Plans Kernel, jamais des recettes ou des objets consommables. `KernelTechnologyPlanConfig` accepte des prérequis distincts : Confiance, Éleveur, Bâtisseur, Régénérateur et `requiredBuildingLevels`.
- `Zone0GameState.kernelPlanRequirementsMet` applique ces conditions réellement lors du passage Plan découvert -> prêt. Les bâtiments reconnus sont Fablab, Cuisine, Atelier, Recycleur, Tour, Marché, Maison et Nurserie ; un identifiant futur non reconnu reste bloquant sans crash.
- L'onglet Kernel affiche désormais la liste complète des prérequis. Le choix gratuit du premier P'TIBUG reste volontairement une exception : il est accordé à la fin de la Nurserie et ne consomme aucun Pattern.
- Les missions Kernel créées depuis le Dashboard sont déjà documentées ci-dessus : elles restent séparées de l'éditeur P'TIBUG afin de ne pas mélanger objectifs de jeu et connaissances/Patterns.

### Tour, intempéries et météo

- `towerOperations_config.dart` définit les alertes et `zone0Settings.towerOperations.weatherEvents` les publie à distance : durée, préavis, produit/quantité de préparation.
- Le Dashboard Tour sépare `Tour de sécurité`, `Rondes, exploration et marchand` et les cartes d'`Intempéries`.
- Une mission Kernel `weather` reste verrouillée jusqu'à l'alerte correspondante de la Tour. Sa remise consomme le produit demandé, marque l'alerte comme préparée et attribue la récompense de mission.
- Le flux historique `fulfillWeatherPreparation` reste disponible dans l'onglet Météo de la Tour; ne pas le supprimer lors d'une évolution des missions météo.

### Correctifs refuge : habitation, énergie et cartes V1

- `ptipote-app/lib/features/game/refuge_page.dart` : les Logements ne sont plus dans la Maison. Le Cœur du Camp possède l'onglet `Habitation`, avec Population, Bien-être et Activité locale cliquables, puis le chantier de logement et le remerciement communautaire facultatif.
- La Maison reste dédiée aux P'TIPOTES, aux alcôves et à sa propre amélioration. Le chantier `housing` reste inchangé côté sauvegarde : aucun logement existant n'est retiré ou reconstruit.
- La Tour affiche une carte 3x3 stable : Camp en bas au centre, biomes autour. L'exploration d'un biome verrouillé exige désormais la moyenne de sécurité de ses voisins déjà déverrouillés, plutôt qu'une sécurité globale du camp. Les missions de surveillance sont limitées par périmètre : Camp et chaque biome possèdent leurs propres slots de niveau de Tour.
- La Lisière possède un onglet `Récolte` et crée un onglet supplémentaire pour chaque biome déverrouillé. La Plaine expose la Nurserie P'TIBUG avec son chantier existant ; les autres emplacements conservent un placeholder de Plan Kernel.
- Cuisine, Atelier et Recycleur affichent la même carte `Alimenter le Fablab`. Ouvrir une Bio-batterie ajoute l'énergie configurée. Un lancement manuel de Cuisine ou d'Atelier consomme 1 Énergie, mais une affectation P'TIPOTE ne la consomme pas. La Cuisine accepte les quantités 1, 5 et 10 comme l'Atelier.
- Les compteurs de refuge et de Tour sont rafraîchis chaque seconde. Lorsqu'un P'TIPOTE atteint le repos maximal dans une alcôve, il en sort automatiquement afin de libérer la place.

### Correctifs UI refuge et biomes futurs

- L'onglet `Habitation` est la seconde section du Cœur. La Végétalisation ne répète plus les statistiques de population. La capacité d'accueil affichée dépend du niveau du Cœur, tandis que les places habitables sont strictement `housingUnits * residentsPerHousingUnit`; les habitants sans logement sont `max(0, population - places)`.
- Les logements démarrent à `10 Organique / 20 Minéral` avant le coefficient structurel, avec une progression réduite. Les anciennes sauvegardes ne reçoivent pas de logement rétroactif : elles sont recalculées à partir de leurs unités réellement construites.
- `zone0Settings.lisiere.upcomingBiomes` prépare Montagne, Savane, Mangrove et Littoral dans le Dashboard. Ces entrées exposent risque, gains et dangers mais restent verrouillées dans Flutter jusqu'à leur implémentation de gameplay; elles ne sont pas ajoutées artificiellement à l'enum des missions.
- Le seuil de sécurité moyen pour explorer un biome est maintenant `40` dans `tower-operations-config.json` et `tower_operations_config.dart`. La carte affiche les neuf cases, dont les zones futures grisées et verrouillées.
- Les missions Kernel terminées peuvent être supprimées par un glissement vers la gauche. Les identifiants supprimés sont persistés dans `kernel.dismissedMissionIds`; une mission active ou verrouillée ne peut pas être retirée.
- L'îlot affiche une pastille sur le Kernel tant qu'au moins une mission Kernel active attend le joueur. Les onglets Kernel suivent l'ordre `Progression`, `Mission principale`, `Demandes`, `Plans`, puis `Météo`.
- Le Pattern Scarabé démarre `unknown` et ne devient actif qu'après la construction de la Nurserie et le choix initial du joueur.

### Cohérence des dépôts et crafts

- `refuge_page.dart` partage `_FablabQuantitySelector` entre Cuisine et Atelier : les deux utilisent désormais les mêmes choix `x1`, `x5` et `x10`.
- `_FablabEnergyCard` présente l'énergie en jauge : bleu au niveau normal, orange sous 30 %. La capacité visuelle s'ajuste par paliers de Bio-batterie sans limiter l'énergie déjà sauvegardée.
- `_ConstructionMaterialProgress` remplace les lignes de texte des chantiers. Chaque ressource affiche une vraie jauge avec `déposé / requis` centré, les actions `+1`, `+5`, `Max` et la récupération complète avant démarrage.
- Le dépôt de végétalisation du Cœur ouvre `_CampHeartOrganicDepositSheet`, une fiche à slot unique Organique : sélection cumulable `+1`, `+5`, `+10`, `Max`, annulation de la sélection et confirmation. L'Organique reste non consommé tant que `Investir dans le Cœur` n'a pas été confirmé.

### Couveuse Maison V1

- `ptipote-app/lib/features/game/refuge_page.dart` : la Maison possède désormais quatre onglets, dans l'ordre `P'TIPOTES`, `Couveuse`, `Amélioration`, `Infos`. La Couveuse ouvre le même `NfcPage` que le bouton de scan historique, qui reste volontairement présent avant l'entrée dans le jeu.
- `ptipote-app/lib/features/game/zone0_game_state.dart` : `hatchedPtipoteIds` est sauvegardé dans `users/{uid}/game/zone0`. Les premiers P'TIPOTES admis occupent les places actives de la Maison ; les suivants restent des œufs dans la Couveuse jusqu'à ce qu'une alcôve soit disponible.
- Chaque œuf affiche son surnom et son type. Lorsqu'une place est libre, l'action `Faire éclore` lance trois séquences de tapotements de prototype. Chaque battement est signalé sans son par un bref grossissement de l'œuf et une syllabe mise en avant; la séquence peut être rejouée librement. Les succès fissurent l'œuf, puis font apparaître le P'TIPOTE et renvoient vers l'onglet principal de la Maison.
- La Couveuse contient aussi un `Œuf de démonstration` permanent. Son éclosion reproduit les trois rythmes et la présentation finale, mais n'appelle jamais `hatchFromNursery`, ne prend pas d'alcôve et n'écrit aucune progression joueur.
- L'éclosion ajoute uniquement le P'TIPOTE à la Maison : elle ne valide pas automatiquement de câlin afin que la bulle de besoin affectif puisse apparaître ensuite. Le bouton final sert de confirmation narrative et conserve le bouton Câlin existant sur la fiche du P'TIPOTE.
- L'onglet `Amélioration` de la Maison expose maintenant le prochain niveau, le gain d'alcôves, les jauges de matériaux et le lancement de chantier directement dans la page. Il ne passe plus par une modale, car il n'existe qu'une amélioration de Maison à la fois.

### Boîtes aux lettres et consommables V1

- `ptipote-app/lib/features/game/zone0_game_state.dart` ajoute `Zone0MessageMailbox` à `PtipoteMissionReport` : `companions` pour les messages P'TIPOTE/P'TIBUG, `kernel` pour les conséquences des missions et Plans Kernel, `fablab` pour les fins de craft et les chantiers des unités Cuisine, Atelier ou Recycleur.
- Chaque rapport possède maintenant un `subject`, un `concerned` et un `summary`. Les rapports historiques sans ces champs restent lisibles et sont rangés dans la boîte Compagnons pour préserver les sauvegardes existantes.
- La Maison ouvre uniquement la boîte `P'TIPOTE & P'TIBUG`; Kernel et Fablab ont chacun leur icône de courrier, leur compteur non lu et leur propre liste. La lecture marque uniquement les messages de la boîte concernée comme lus.
- Les rapports sont volontairement synthétiques : sujet, personne ou unité concernée, puis conséquence. Un glissement vers la gauche conserve la suppression manuelle déjà existante.
- `Zone0GameState.availableConsumableRecipes` et `consumeConsumable` généralisent l'ancien flux `Repas simple`. Dans la fiche P'TIPOTE, `Manger` ouvre la liste des consommables disponibles. Dans l'inventaire global, toucher un aliment ou une boisson ouvre la liste des P'TIPOTES compatibles, puis applique les restaurations configurées de faim et vitalité.

### P'TIBUG V2 : recherche, Traits, Modules et Capsules

- `ptipote-app/lib/features/game/ptibug_config.dart` centralise les sept familles de données V1 (`Organique`, `Minérale`, `Mycélienne`, `Toxine`, `Biomimétisme`, `Énergie`, `Comportement insectoïde`), leurs qualités Commune/Recherchée/Rare et les valeurs 1/2/4. Il contient également les configurations de Patterns, Traits, Modules et des huit biomes P'TIBUG préparés.
- `ptipote-app/lib/features/game/zone0_game_state.dart` sauvegarde dans la progression Zone 0 la réserve de données, les Cellules, les progressions de Pattern, les instances de Modules, les ordres de fabrication, les Capsules et les P'TIBUG. Les données restent dans le Kernel et ne prennent pas de case d'inventaire matériel.
- Les missions de Lisière créent maintenant des `PTibugDataCell` fermées suivant trois tirages indépendants configurables par rang : première Cellule garantie (100 %), seconde à 50 %, troisième à 20 %. Le plafond reste lié à la durée (courte 1, moyenne 2, longue 3) ; l'intensité et la Sécurité n'altèrent pas ces chances. Chaque Cellule appartient à une famille de données du biome P'TIBUG : les Cellules neutres sont supprimées. L'ouverture depuis l'onglet Progression du Kernel crédite définitivement la réserve de données et crée un message Kernel.
- Chaque biome actif de Lisière conserve un niveau de `Déchets` de 0 à 10 dans `BiomeSecurityState` et dans Firestore. Le gain de mission utilise `wasteBaseGain × (wasteLevel × 0,15)`, pondéré par durée, intensité et retour anticipé ; le niveau baisse d'un palier par heure théorique effectivement passée. À 0, le biome est assaini et procure +30 % d'Organique tant qu'il reste propre. L'estimation Lisière affiche les tirages de Cellules, le niveau de Déchets, le multiplicateur ou le bonus d'Organique.
- Une `PTibugDataCell` contient exactement cinq entrées. Son ouverture crédite la réserve du Kernel; les données sont ensuite investies manuellement dans une recherche. Les Patterns sont des connaissances à maîtrise progressive, pas des objets consommables.
- Les Traits biologiques sont permanents : un P'TIBUG n'en reçoit qu'un. Son nom affiché devient par exemple `Hyme Pollinisateur II`. Le même Trait peut évoluer uniquement vers son niveau suivant via la Nurserie (I vers II, puis II vers III) lorsque le Pattern atteint la maîtrise cible. L'évolution consomme uniquement les données, matériaux et énergie du niveau cible : les coûts précédents ne sont jamais cumulés ou facturés une seconde fois. Un Trait différent ne peut pas remplacer le Trait biologique existant.
- Les Modules (`Ailes`, `Pinces`, `Réservoir`) sont des instances amovibles fabriquées dans l'Atelier, équipables, retirables et fusionnables par paires identiques. Le Réservoir ajoute +15, +18 ou +20 de capacité selon son niveau. La source de vérité de l'équipement est l'instance `equippedPTibugId`; la liste du P'TIBUG est maintenue pour la compatibilité des anciennes sauvegardes.
- Les cartes de Création P'TIBUG et de Modules réutilisent `_ProductionRecipeCard`, le composant partagé par Cuisine et Atelier. Elles affichent les ressources maison, les besoins, l'énergie, le temps de fabrication et le maximum fabriquable. Le coût V1 d'un P'TIBUG de base est 30 Organique, 15 Minéral et 10 Bio-batteries; le Mycélium reste un champ de configuration futur sans coût imposé par défaut.
- La production de base est configurée à 3 ressources par cycle et la capacité minimale est de 10. Le calcul applique successivement espèce, biome, Trait, Modules, durée du cycle, puis limite de stockage. Chaque P'TIBUG garde son stock jusqu'à la récolte individuelle.
- Une Capsule préserve l'espèce, le Trait, le niveau, l'XP, l'origine et le nom biologique. L'encapsulation exige un P'TIBUG inactif, au stock récolté et sans Module équipé. Les Modules restent séparés. Décapsuler restaure le P'TIBUG sans débloquer son Pattern ni la maîtrise scientifique du destinataire.
- Migration : les anciens champs `traitDataId` et `equippedModules` sont conservés. Les anciens biomes de Lisière sont mappés vers les identifiants P'TIBUG; aucun P'TIBUG existant, Module ou stock produit n'est supprimé. Les sauvegardes où seul `equippedPTibugId` était renseigné sont désormais reconnues par l'UI et l'encapsulation.
- `ptipote-app/lib/features/game/refuge_page.dart` expose la recherche dans le Kernel et les opérations P'TIBUG dans la Nurserie : fabrication, Trait, équipement, fusion, récolte et Capsules. L'ouverture d'une Cellule révèle désormais ses cinq entrées progressivement, avec l'option `Tout révéler`; les données ne rejoignent le Kernel qu'après validation finale.
- Le Dashboard P'TIBUG organise l'édition par fondations, espèces, Traits, recherches et biomes. Chaque Pattern V1 (espèce, Trait et Module) possède une carte structurée éditable : catégorie, liaison, origine, biomes conseillés et coûts de maîtrise I à III. Il permet aussi de créer un Trait avec ses coûts par niveau et un Pattern structuré. Les Patterns de Traits utilisent l'identifiant canonique `ptibug-trait-<traitId>` ; la migration convertit et fusionne les anciens progrès `trait-<traitId>` sans perdre la maîtrise ou les données déjà investies.
- Le Sourcier sauvegarde ses offres actives dans Firestore et peut proposer un Pattern de recherche, une Cellule spécialisée, une Cellule neutre, un Module ou une Capsule certifiée, en plus des Patterns d'espèces historiques. Les prix et la capacité de réserve de Nurserie sont configurables dans `ptipote-dashboard/ptibug-config.json` et lus par `remote_zone0_settings.dart`.
- Les Capsules migrées reçoivent des identifiants d'origine, créateur et certification de compatibilité. Les Cellules historiques sont complétées à cinq entrées lors du chargement, sans modifier les données déjà ouvertes. L'éditeur Dashboard couvre les tables V1 de familles par biome, Patterns, Traits, Modules et Capsules sous forme de cartes structurées; un équilibrage ultérieur peut modifier ces données sans changement Flutter.

### P'TIBUG V2 : effets complets et tables distantes

- `ptipote-app/lib/features/game/ptibug_config.dart` sépare les effets matériels d'un Trait (Organique, Minéral, Mycélium, Déchets) de ses effets systémiques. Les huit Traits V1 disposent désormais de coûts de données, matériaux et Énergie pour les niveaux I à III.
- Les effets systémiques sont appliqués dans `ptipote-app/lib/features/game/zone0_game_state.dart` : Éclaireur reste un point d'extension de découverte, sans modifier les trois tirages de Cellules V1 ; Filtreur augmente le poids Toxine, Économe réduit le coût d'Énergie de fabrication des Modules et Stabilisateur augmente la sécurité locale du biome lié à chaque cycle de production. Ces bonus ne créent pas de fausse ressource dans l'inventaire.
- Arac utilise une table pondérée par biome (`aracProductionWeights`) au lieu d'une ressource aléatoire globale. Les huit biomes P'TIBUG définissent leurs risques, familles de données, bonus locaux et pondérations Arac.
- `remote_zone0_settings.dart` fusionne désormais les valeurs distantes `zone0Settings.ptibug` pour les Traits, recherches, biomes, qualités de données, coûts/temps des Modules et leurs effets, sans remplacer les valeurs Dart absentes. Les sauvegardes joueur restent inchangées : seuls les réglages communs sont lus depuis Firestore.
- `ptipote-dashboard/app.js` et `ptipote-dashboard/ptibug-config.json` exposent ces tables à l'édition : Traits et coûts par niveau, recherches, familles de données, biomes, Modules et tables de production. Les configurations Dart restent le fallback hors ligne.
- Vérification ciblée : `ptipote-app/test/ptibug_config_test.dart` garantit que les effets systémiques ne sont pas injectés dans la production, que les pondérations locales d'Arac existent et que les huit Traits V1 possèdent leurs coûts par niveau.

### Patterns Kernel, niveaux et Cellules

- Les Patterns ne sont plus vendus ni acquis par le Sourcier. Ils vivent tous dans le Kernel. Au-delà de deux niveaux manquants, ils sont invisibles ; à deux niveaux, seule leur icône apparaît ; à un niveau, leur nom et leurs prérequis apparaissent ; quand tous les prérequis sont atteints, ils deviennent découverts et affichent leurs coûts de données.
- Les Patterns de productions s’activent une seule fois dans le Kernel grâce aux données investies, puis rendent leur recette disponible à l’Atelier. Les coûts de chaque recette sont dans `kernel-progress-config.json`, sous `plans[].dataRequirements`, et sont éditables dans le Dashboard Kernel.
- Les Traits P’TIBUG sont les seuls Patterns à plusieurs maîtrises. Leur découverte et leur premier niveau passent par le même panneau de données du Kernel ; leurs évolutions sont appliquées dans la Nurserie.
- Les Modules P’TIBUG sont fabriqués à l’Atelier. La Nurserie conserve uniquement leur stock, équipement, retrait et fusion ; les anciens indicateurs `unlockedModules` restent lus pour compatibilité mais ne servent plus de verrou de gameplay.
- Le Sourcier propose exactement trois Cellules spécialisées de familles distinctes et un lot d’objet fini d’Atelier. Les Cellules sont vendues pour leur contenu réel : somme des cinq valeurs de données × `sourcierCellPricePerDataValue` (V1 : 3 Bio-batteries par valeur), réglable dans le Dashboard P’TIBUG.
- Les offres d’Atelier sont des produits finis, jamais des Plans. V1 propose un produit aléatoire par visite, configuré dans le Dashboard Tour avec un stock tiré de 5 à 10 et un prix unitaire. Le Marché achète de 1 unité jusqu’au stock restant grâce au sélecteur ; le total est recalculé avant chaque achat.

### Stock de production P’TIBUG

- Le stock interne d’un P’TIBUG est strictement plafonné. À capacité atteinte, `nextProductionAt` est vidé : aucun cycle n’est gardé en attente ni rejoué après une récolte Firebase.
- Une récolte repart toujours sur un nouveau cycle à partir de l’instant de collecte. Elle ne peut donc récupérer que les ressources réellement présentes dans `storedResources`.
- La capacité de stockage est multipliée par `storageMultiplier` (V1 : `5`) pour la capacité de base et le bonus du Module Réservoir. Les valeurs configurées 10 et +15/+18/+20 donnent ainsi 50 et +75/+90/+100.
- Le Dashboard P’TIBUG expose séparément la capacité de base, le multiplicateur et les bonus de Réservoir par niveau ; toute modification est publiée dans `gameConfigs/zone0.zone0Settings.ptibug` et garde le fallback Dart versionné.

### Déchets des biomes de Lisière

### Gestion territoriale P’TIBUG

- La Lisière expose désormais deux onglets principaux : `Missions` (ancien contenu Récolte intact) et `P’TIBUG`. Ce dernier est le tableau territorial : Plaine/Nurserie d’abord, puis chaque biome découvert et enfin les P’TIBUG inactifs.
- L’affectation est persistée par `PTibug.assignedBuildingId`. La migration lit les anciens `assignedSlotIndex`, conserve les résidents qui tiennent dans la capacité de la Nurserie de Plaine et place tout dépassement ou bâtiment inconnu dans les inactifs, sans supprimer P’TIBUG, niveau, Traits, Modules, ressources ou Cellules.
- `PTibugTerritoryBuilding` sauvegarde le biome, type Nurserie/Refuge, niveau, stocks locaux Organique/Minéral, énergie locale et horodatage de consommation dans `users/{uid}/game/zone0.ptibug.territoryBuildings`. Les futurs Refuges restent non construits tant qu’un chantier réel ne les crée pas.
- Les P’TIBUG ne tirent plus leurs consommations de l’inventaire global : le joueur transfère Organique/Minéral vers le bâtiment et ouvre une Bio-batterie pour y convertir l’énergie avec le même ratio que le Fablab. Les coûts hors ligne partent de `lastConsumptionAt`; un manque rend les résidents inactifs sans coût partiel, et ils reprennent après alimentation.
- Chaque P’TIBUG garde `storedResources`/`storedMaterialProduction` séparé de `storedDataCells`. Le bouton Récolter transfère séparément les matériaux (sans dépasser l’inventaire global) et les Cellules vers la réserve Kernel; un reliquat matériel reste sur le P’TIBUG.
- La carte territoriale, l’Aperçu et la Collection doivent s’appuyer sur `pTibugTerritoryDailyConsumption`, seul calcul du bilan quotidien, afin d’éviter une valeur purement visuelle différente de la simulation. Les multiplicateurs de Biomasse déjà existants restent appliqués selon le biome du bâtiment.
- Le Dashboard P’TIBUG contient la carte `Gestion territoriale P'TIBUG`, publiée dans `gameConfigs/zone0.zone0Settings.ptibug.territory` : plafonds des niveaux, capacité par niveau, fréquences/coûts Organique, Minéral et Énergie, surcharge Module, consommation des bâtiments et capacité de Cellules.

- Le niveau de Déchets d’un biome remonte automatiquement, jusqu’au maximum configuré, même après fermeture de l’application. Chaque biome conserve son horodatage `lastWasteRegenerationAt` dans `users/{uid}/game/zone0.biomeSecurity`; les anciennes sauvegardes démarrent le nouveau cycle sans gain rétroactif.

### Biomasse des biomes

- Chaque biome de Lisière possède une Biomasse indépendante de `0` à `100`, sauvegardée avec son état dans `users/{uid}/game/zone0.biomeSecurity.<biome>.biomassPercent`. Elle ne remplace ni les Déchets du biome (butin recyclable) ni la Sécurité locale (risque).
- Les intensités modifient aussi la durée réelle de mission : Douce est plus lente, Normale est équilibrée et Intensive est plus rapide. À la fin d’une mission, la Biomasse perd la consommation associée à son intensité (`doux`, `normal`, `intensif`), proportionnellement en cas de retour anticipé. Les Cellules de données, l’exploration et les objectifs restent possibles quel que soit le niveau de Biomasse.
- Les ressources naturelles de mission (`Organique`, `Minéral`, `Déchets`) reçoivent le multiplicateur de rendement de Biomasse configuré : V1, 50–100 % = x1, 20–49 % = x0,75, 0–19 % = x0,5. Les autres récompenses ne sont pas réduites.
- La Biomasse régénère automatiquement, point par point. Le temps de base et les paliers de multiplicateur sont configurés : V1 2 h par point au-dessus de 50 % (récupération réduite de 50 %), x2 entre 30–49 %, x4 entre 20–29 %, x8 entre 10–19 %, x16 entre 0–9 %. `lastBiomassRegenerationAt` évite tout gain rétroactif sur les anciennes sauvegardes.
- `Revigorer` dépense Organique et Minéral pour restaurer un nombre configurable de points. Les coûts utilisent un multiplicateur configurable qui augmente quand la Biomasse est faible.
- L’interface Lisière et les cartes de biomes de la Tour affichent l’état visuel configuré : 🌿 Luxuriante (80–100 %), 🌱 Stable (50–79 %), 🍂 Fragile (20–49 %), 🪨 Épuisée (0–19 %), avec barre et pourcentage dans la Lisière.
- La production P’TIBUG applique la Biomasse après l’espèce, le bonus de biome, les Traits et les Modules. Le P’TIBUG contient désormais `refugeBiome` : tous les P’TIBUG existants sont migrés vers la Plaine, qui représente la Nurserie principale. Les futurs Refuges P’TIBUG n’auront qu’à modifier ce biome de Refuge ; ils ne créent ni n’améliorent de P’TIBUG.

### Atelier, Marché et postes — ajustements de progression

- Les Armatures P’TIBUG sont fabriquées à l’Atelier du Fablab, après activation de leur Pattern dans le Kernel. Elles occupent le même créneau manuel ou P’TIPOTE que les autres fabrications d’Atelier et restent ensuite placées dans une cuve depuis la Nurserie.
- Les demandes habitantes sont filtrées par un niveau minimal de Marché réglable produit par produit : alimentation au niveau 1, équipement au niveau 2 et foyer au niveau 3 par défaut. Les produits non encore débloqués ne sont pas créés comme demandes.
- Une place de Marché libre peut être revendiquée après 1 jour par défaut ; le préavis de 24 h reste conservé. Les chantiers de magasins et Distributeurs utilisent la même table : 6 min, 30 min, 60 min puis 120 min aux niveaux 1 à 4.
- Les postes communautaires sont affichés sous forme de créneaux : gris lorsqu’ils sont libres, verts avec le nom de l’habitant lorsqu’ils sont occupés. La carte occupée ouvre la fiche de son habitant.
- Le Dashboard Lisière expose une carte `Biomasse` : maximum, consommation par intensité, seuils de rendement de mission et P’TIBUG, récupération, Revigorer, et états/pictogrammes. Les valeurs Dart restent le fallback versionné.
- Le rythme `wasteHoursPerLevelRegeneration` est éditable dans chaque carte de biome du Dashboard Lisière. V1 : Savane tropicale +1/h, Semi-désert / Garrigue tropicale +1/2 h, Forêt humide relictuelle +1/2 h, Hauts-Refuges +1/3 h. Une mission consomme les Déchets puis redémarre le cycle au moment de son retour.

### Plans Kernel et recettes Atelier

- Un Plan Kernel lié à une recette doit toujours contenir `category` et `workshopRecipeId`. Sans cette liaison, le Dashboard créait une seconde fiche `craft-…` pour la même recette, mais Flutter ignorait cette fiche car seules les entrées de Plans de base sont fusionnées avec la configuration distante.
- Le Plan `filter` est découvert dès que ses prérequis Kernel sont atteints (Confiance 2, Régénérateur 1). La valeur `discoverWhenRequirementsMet` est un fallback Dart : les configurations Firebase plus anciennes, qui ne possèdent pas encore cette clé, ne peuvent donc plus bloquer le Filtre sur trois événements `pollutionObserved`.
- Les autres Plans conservent leurs déclencheurs narratifs configurés (`craftCompleted`, mission, construction ou amélioration de l'écosystème). Leur liaison recette est néanmoins désormais versionnée dans `kernel-progress-config.json`, ce qui empêche les doublons Dashboard pour Cartouche, Tenue ombragée, Ventilation Termite et Lumière solaire.

### Progression et Évolution P’TIBUG

- Le niveau est une progression propre à chaque P’TIBUG, distincte du niveau de bâtiment, de la maîtrise d’un Pattern, du niveau d’un Module et du niveau d’un Trait. La configuration `ptibug.progression` fixe le maximum V1 à 6, l’XP demandée par palier, le bonus de rendement et l’énergie de base.
- Chaque cycle créditant de l’XP utilise `_gainPTibugXp`. Au niveau maximum l’XP est volontairement bloquée : il n’y a ni niveau 7 ni réserve ayant un effet caché. Le rendement est placé une seule fois dans `_pTibugProduction`, après l’espèce et le bonus local de biome, avant les Traits et Modules, puis la Vigueur est appliquée en dernier.
- V1 : niveau 1 = 100 %, niveau 3 = 120 %, niveau 6 = 150 %. L’énergie de base est 3/jour au niveau 1, diminue de 1 par niveau et est plafonnée à 1/jour. Organique, Minéral, énergie de bâtiment et surcharge Module restent indépendants.
- Le premier Trait utilise les paliers I à III des niveaux 1 à 3. Le niveau rend seulement un palier éligible : l’Infusion volontaire dans une cuve vérifie toujours Pattern, maîtrise et Cellules requises. Organique, Minéral et Énergie sont ensuite consommés progressivement avec le ratio de l’espèce.
- L’Évolution exige niveau 3, premier Trait III et stock matériel/Cellules vide. Elle conserve identifiant, espèce, nom, niveau, XP, Modules, stock et premier Trait ; les clés techniques de compatibilité `isRenewed`, `renewedAt` et `renewalCount` restent utilisées pour éviter toute migration destructive, mais ne sont plus affichées au joueur.
- Après Évolution, le second Trait est distinct du premier et suit les paliers I/II/III des niveaux 4/5/6. Les champs de sauvegarde sont `biologicalTraitId`/`biologicalTraitLevel` pour le premier Trait et `secondTraitId`/`secondTraitLevel` pour le second. La migration traite donc tout P’TIBUG anciennement « renouvelé » comme évolué.

### Amélioration globale des Modules

- `pTibugModuleCapacityLevel` est une progression joueur sauvegardée dans `ptibug.moduleCapacityLevel`; `maxModulesPerPTibug` est calculé depuis `ptibug.moduleCapacity`. V1 commence à 1 Module, puis passe à 2 et 3 via les améliorations I et II de Nurserie → Amélioration.
- Chaque amélioration vérifie puis consomme atomiquement matériaux, Bio-batteries et les sept familles de données Kernel. V1 : I = 60 Organique, 30 Minéral, 10 Bio-batteries et les données 10/5/5/2/10/5/10 ; II double tous ces coûts. Une confirmation UI évite une dépense accidentelle et le service rejette tout second achat après le maximum.
- La capacité est globale : elle s’applique aux P’TIBUG actifs, inactifs, en Nurserie ou en Refuge. Aucun Module n’est généré ou équipé automatiquement. Les Modules historiques en excédent restent équipés et peuvent être retirés, mais aucun nouvel équipement ne peut dépasser la capacité débloquée.
- Le Dashboard P’TIBUG édite `progression` (niveaux, XP, rendement, énergie et Évolution) et `moduleCapacity` (capacités et tous les coûts), publiés sous `gameConfigs/zone0.zone0Settings.ptibug`. `ptibug_config.dart` demeure le fallback versionné hors ligne; les sauvegardes joueur ne sont jamais écrites dans la configuration distante.

### Persistance Firebase Zone 0 et chantier de Nurserie

### Refuge P’TIBUG V1

- Chaque biome découvert hors Plaine expose désormais un unique chantier `refuge-<biome>`. La Plaine conserve exclusivement la Nurserie principale. Les chantiers et les Refuges utilisent `ConstructionProject` et `PTibugTerritoryBuilding`, donc la même persistance, les mêmes calculs hors ligne et les mêmes protections contre les doubles lancements que les autres bâtiments.
- Les coûts V1 sont déposés progressivement : construction 20 Organique, 10 Minéral et 1 Bio-batterie, puis améliorations 2/3/4 : 30/15/2, 60/30/4, 120/60/8. Le joueur lance ensuite explicitement les travaux (1 minute V1). `depositedBioBatteries` est sauvegardé avec le projet ; la finalisation crée ou met à jour un seul Refuge de niveau 1 à 4.
- Un Refuge construit réutilise ses stocks locaux Organique, Minéral et Énergie, l’ouverture de Bio-batterie de l’Atelier, le bilan journalier, les affectations, les récoltes matérielles et de Cellules, la Vigueur et la météo de son biome. Sa capacité est `niveau × capacitéParNiveau` (1 à 4 V1).
- Pendant des travaux d’amélioration, les P’TIBUG restent affectés mais production et consommation du Refuge sont suspendues ; à la fin ils reprennent leur cycle si les stocks sont suffisants. Les sauvegardes existantes sans Refuge restent des chantiers non construits, sans création automatique de bâtiment.
- La section Dashboard **P’TIBUG → Bâtiments, consommation et Cellules** édite `territory` : niveaux/capacité, coût et durée de construction, coûts/durée d’amélioration, consommation du Refuge et capacité des Cellules. Les valeurs distantes sont fusionnées par `remote_zone0_settings.dart`, avec `ptibug_config.dart` comme fallback versionné.

### Récoltes détaillées et alertes de besoins

- Les cartes P’TIBUG n’affichent le compartiment **Cellules** que lorsqu’un Trait principal ou secondaire est `capteurIntelligent`. La récolte individuelle détaille désormais chaque ressource transférée, les Cellules par famille et tout reliquat matériel conservé faute de place.
- La jauge Déchets représente la réserve de Déchets récupérables du biome : à 10/10, l’estimation de mission affiche bien le gain disponible. Les sorties `Déchets` des P’TIBUG sont également pondérées par cette même réserve, sans toucher à Organique ni Minéral.
- Les retours de mission listent les ressources, Cellules, Vigueur et l’état de chaque P’TIPOTE (énergie, faim, sommeil et bonheur). Les rapports de ronde indiquent déjà le gain de sécurité et la météo détaille la préparation, demande et durée.
- `functions/index.js` ajoute `notifySavedPtipoteNeeds`, un contrôle Firebase planifié toutes les 30 minutes. Il convertit les besoins sauvegardés critiques (faim, repos, énergie) en documents de notifications ; le déclencheur FCM existant les envoie sur l’iPhone même lorsque l’application est fermée. Son déploiement Firebase est requis pour l’activer en production.

### Missions de Lisière : Récolte et Recherche

- L’onglet **Missions** réutilise un configurateur unique : type, biome, participants, durée et intensité. Les nouvelles missions ne proposent que **Normale** et **Intense** ; `doux` reste uniquement lisible dans les anciennes sauvegardes pour qu’une mission déjà partie se termine sans perte.
- Chaque `ForageMission` sauvegarde désormais `type` (`harvest` ou `research`). Une mission historique sans ce champ est migrée en Récolte. Les tirages de Cellules restent attachés à l’identifiant unique de mission (`sourceMissionId`) : une réouverture ne peut ni relancer les tirages ni dupliquer le rapport.
- **Récolte** produit les ressources naturelles du biome, les Déchets disponibles et des Cellules occasionnelles. Son rendement matériel passe par les seuils de Vigueur existants (100 %, 75 %, 50 %).
- **Recherche** ne produit jamais Organique, Minéral, nourriture, Mycélium ni autre ressource naturelle : elle rapporte seulement des Déchets et des Cellules provenant de la même table de biome que Capteur intelligent. La Vigueur ne réduit pas les Cellules et son coût est réglé séparément (V1 : x0,20 du coût de Récolte).
- L’estimation avant départ, les missions en cours et le rapport indiquent le type, les Cellules, les Déchets et l’impact prévu sur la Vigueur. Sécurité et météo continuent d’être affichées comme risques indépendants de la Vigueur.
- `lisiere-forage-config.json` expose `missionTypes.harvest` et `missionTypes.research` : multiplicateur de Vigueur, probabilité/maximum de Cellules et Déchets par heure. Le Dashboard Lisière les rend visibles dans la configuration versionnée ; `lisiere_forage_config.dart` reste le fallback hors ligne et `remote_zone0_settings.dart` fusionne toute valeur distante publiée.

### Traits P’TIBUG V1, Capteur intelligent et météo

- Les huit Traits V1 sont Pollinisateur, Mineur, Décomposeur, Récupérateur, Stabilisateur, Économe, Filtreur et Capteur intelligent. Les deux emplacements de Trait issus de l’Évolution utilisent le même service d’effets : leurs bonus matériels se cumulent et les doublons restent interdits.
- Éclaireur a été renommé en `capteurIntelligent`. La migration conserve le niveau, le propriétaire et la maîtrise du Pattern en déplaçant `trait-eclaireur` / `ptibug-trait-eclaireur` vers `ptibug-trait-capteurIntelligent`; aucune Cellule ni ressource n’est accordée rétroactivement.
- Capteur intelligent réduit la production matérielle (V1 : -50 %, avec un minimum d’une unité pour une sortie positive) et tire une Cellule à la fin d’un cycle réellement validé : 5/10/15 % aux niveaux I/II/III. La Cellule utilise les poids de données du biome actif, est ajoutée directement dans `PTibug.storedDataCells`, et ne partage pas la capacité matérielle. Le tirage est effectué une seule fois pendant la résolution/sauvegarde du cycle, jamais lors de la construction de l’interface.
- Économe applique ses réductions uniquement aux consommations locales du P’TIBUG : Organique -20 %/niveau et Énergie -10 %/niveau. `PTibugTerritoryBuilding` conserve des reliquats fractionnaires pour que les résolutions hors ligne courtes ne suppriment pas l’effet. Stabilisateur augmente uniquement la régénération de Vigueur du biome local, avec un plafond distant.
- La Tour reste la seule source de l’alerte météo. Les biomes P’TIBUG déclarent leurs types compatibles (`toxicCloud`, `heavyRain`, `heatWave`) ; une alerte compatible applique -30 % de production matérielle après Vigueur. Filtreur annule Nuage toxique, Réflecteur annule Forte chaleur et Étanchéité annule Pluie intense. La météo ne provoque jamais l’inactivité.
- Réflecteur et Étanchéité sont des `PTibugModuleType` fabriqués à l’Atelier, amovibles et soumis à la capacité globale de Modules. Le registre de Modules est commun aux Ailes, Pinces, Réservoir et contre-mesures météo.
- `ptibug.weather`, les définitions de Traits, les Patterns, les coûts et les temps des Modules sont éditables dans le Dashboard P’TIBUG et lus via `remote_zone0_settings.dart`; `ptibug_config.dart` reste le fallback Dart versionné. Fichiers principaux : `zone0_game_state.dart`, `ptibug_config.dart`, `remote_zone0_settings.dart`, `refuge_page.dart`, `ptibug-config.json` et `app.js`.

- `ptipote-app/lib/features/game/refuge_page.dart` charge désormais l'état joueur avant toute simulation, applique ensuite les résolutions hors ligne et demande une sauvegarde au passage de l'application en arrière-plan.
- `ptipote-app/lib/features/game/zone0_game_state.dart` bloque toute écriture avant le premier chargement Firebase et sérialise les écritures afin qu'une sauvegarde ancienne ne puisse plus écraser une sauvegarde récente.
- Les missions, affectations Tour, sécurité/exploration des biomes, générateur, recycleur, inventaire, chantiers et production P'TIBUG appartiennent au runtime Zone 0 sauvegardé dans `users/{uid}/game/zone0`. Les règles Firestore autorisent ce document pour son propriétaire connecté.
- Le Cœur du Camp est restauré avant les résolutions qui dépendent de son niveau. Cela évite de traiter la Nurserie, les chantiers et la production avec un niveau par défaut au redémarrage.
- La Nurserie de Plaine utilise le projet de construction commun. Son prérequis V1 est le Cœur du Camp niveau 2 : les matériaux peuvent être déposés et retirés dès l'ouverture du projet, mais le bouton de lancement reste verrouillé jusqu'au niveau 2. Les dépôts sont persistés normalement.
- La modale de chantier observe également le `CampHeartState` actif : après la restauration Firebase, elle recalcule le prérequis et ses boutons de dépôt sans conserver le niveau du Cœur capturé à l'ouverture de la Lisière.
- Au chargement, une Nurserie non construite enregistrée par une ancienne sauvegarde avec un état terminal (`built` ou `maxLevel`) est normalisée vers son projet de niveau 1. Les Nurseries réellement construites ne sont pas modifiées.
# Marché V1 — demandes, Distributeur et contrats

Le Marché utilise des piles de vente indépendantes : deux piles identiques ne sont jamais fusionnées et la logique commune de prélèvement consomme d’abord la pile la plus entamée. Les demandes habitantes sont temporaires (10–20 minutes par défaut), sans pénalité à l’expiration. Elles sont créées indépendamment du stock et choisissent le nom d’un habitant actif du Cœur lorsqu’il existe. Leur cadence de base est maintenant pilotée par niveau de Marché (`2/4/6/10` demandes par heure aux niveaux `1/2/3/4`), avec un écart minimal de deux minutes et une variation configurable. L’**activité économique** peut doubler cette cadence : bien-être (jusqu’à 30 %), niveau du Cœur (jusqu’à 40 %), niveau du Marché (jusqu’à 20 %) et météo (0–10 %). Les catégories sont pondérées par défaut : nourriture 60 %, matériaux 20 %, tenues 15 %, meubles 5 %.

Les paiements des demandes utilisent des **bio-piles** jaunes, distinctes des Bio-batteries bleues : dix bio-piles sont automatiquement converties en une Bio-batterie. Les coûts existants en Bio-batteries ne changent donc pas. Les prix par objet et les poids de catégories sont configurables dans `market.requestPriceBioPiles` et `market.requestCategoryWeights`; le HUD regroupe les deux monnaies dans une seule capsule. Il n’existe plus de cycle de vente autonome : tout prélèvement du stock répond obligatoirement à une demande habitant, manuellement ou par le Distributeur après son délai d’une minute ; les contrats du Sourcier restent séparés.

À partir du niveau 2, le Livre des demandes enregistre sur 24 h les demandes observées par le P’TIPOTE : heure, délai, produit, quantité, habitant lorsqu’il est connu, résultat et gain. Au niveau 3, il devient automatique, y compris lorsque le Marché est vide. Le Distributeur attend au minimum une minute avant de résoudre une demande afin que celle-ci soit visible dans le Livre. Les entrées terminées et expirées sont purgées après 24 h. L’écran Vente n’affiche que le compte à rebours de la prochaine demande ou les cartes des demandes actives : « prochaine vente » est une ancienne donnée de sauvegarde neutralisée à la prochaine résolution.

À partir du niveau 2, le Distributeur dispose de son propre chantier, de dépôts progressifs, d’une réserve d’Énergie commune au Marché, de ses piles de matières premières, d’une consommation hors ligne et de pannes sauvegardées. Une Bio-batterie apporte 10 Énergies par défaut. Les contrats du Sourcier sont séparés de ses quatre offres : ils doivent être acceptés volontairement, sont payés à la livraison et font évoluer la Confiance (0–100) uniquement en cas de réussite ou d’échec après acceptation. La carte du Sourcier affiche cette jauge et ses contrats directement sous elle. Les licences commerciales se débloquent au niveau 2 : 30 Bio-batteries à l’achat, 40 pour remplacer une licence ; une licence oriente 80 % des contrats, deux licences répartissent ces 80 % à 40 % chacune. Toutes ces valeurs restent configurables.

Réglages : `ptipote-dashboard/market-config.json`, chargés par `remote_zone0_settings.dart`. Sauvegarde : `users/{uid}/game/zone0.runtime.market` (piles avec identifiant, demandes, Distributeur, contrats, Confiance, licences et magasins). Fichiers métier : `market_config.dart`, `zone0_game_state.dart`; interface : `refuge_page.dart`.

Le Distributeur possède un stock local totalement distinct de celui du Marché et une spécialisation choisie avant les travaux : **Ressources** (Organique, Minéral, Déchets, Mycélium, Eau), **Alimentaire** (recettes consommables) ou **Généraliste** (matériaux transformés et produits Atelier). Ses emplacements « + » n’acceptent que les objets compatibles ; les objets peuvent être rendus à la Maison. Il ne résout que les demandes habitantes compatibles avec son propre stock, après le délai configuré.

Les emplacements de magasins sont pilotés par `market.specializedShopSlotsByMarketLevel` : le Marché possède une première boutique au niveau 1, puis 3 emplacements au niveau 2, 5 au niveau 3 et 7 au niveau 4. La spécialisation applique par défaut +30 % de gain et la première boutique généraliste affiche un malus de prix de 50 %; ces deux valeurs sont pilotables par le Dashboard.

Chaque demande persiste maintenant la boutique ciblée (`shopId`) et le Livre conserve aussi l’auteur d’une réponse (`player`, `ptipote`, `distributor`). Les boutiques spécialisées possèdent leur liste de piles, une capacité de 3 au niveau 1 puis 6 au niveau 2, un filtre de produits compatible avec leur spécialisation et un état de Distributeur sérialisable. La boutique principale continue de lire les champs historiques `market.stock` et `market.distributor` pour migrer les anciennes sauvegardes sans perte. Le P’TIPOTE du Point info réapprovisionne le Distributeur principal depuis cette boutique lorsqu’une pile compatible est disponible ; aucun remplissage ne prélève directement la Maison.

Migration boutique : une sauvegarde qui possédait l’ancienne « première boutique spécialisée » la marque désormais comme boutique principale migrée, conserve son identifiant, son niveau, son stock et son Distributeur éventuel, puis exclut cette entrée du compte de boutiques supplémentaires. Ainsi, choisir Restaurant ne crée plus une seconde boutique. Une nouvelle boutique principale est choisie au premier accès au Marché et coûte par défaut 15 Organique, 30 Minéral et 10 Bio-batteries ; un Distributeur exige 10 Organique, 20 Minéral et 5 Bio-batteries. L’amélioration d’une boutique double ce coût et passe ses piles de 3 à 6.

Le P’TIPOTE affecté au Marché gagne `niveau du Marché × 1 XP` toutes les deux heures réellement écoulées. Les crafts attribués accordent 5 XP, avec +5 XP si la commande est multiple ; un Module P’TIBUG accordé par un P’TIPOTE vaut 10 XP. Les rapports de fin de craft et de retour du Marché annoncent ces gains. Une panne du Distributeur, le lancement d’une réparation et sa fin sont consignés dans le Livre des demandes ; le joueur la termine en 1 minute, tandis qu’un P’TIPOTE utilise la durée configurée par niveau.

Chaque boutique, y compris la principale, possède désormais son stock et peut construire son propre Distributeur avec ses dépôts progressifs. Les demandes sont orientées vers une boutique spécialisée compatible lorsqu’elle existe ; sinon elles utilisent la boutique principale. Le P’TIPOTE du Point info laisse une priorité de 1 minute au Distributeur et au joueur, puis répond au bout de 3 minutes depuis n’importe quel stock compatible. La boutique principale possède aussi deux niveaux : trois piles au niveau 1, six au niveau 2 ; son amélioration coûte deux fois sa construction. Son encart affiche l’âge de vie calculé depuis la création de la figurine affectée.

Les nouveaux choix sont **Restaurant** (produits de Cuisine), **Magasin du foyer** (installations et meubles, dont Meuble simple) et **Magasin d’équipement** (produits de l’Atelier). Le type généraliste reste seulement lisible pour les sauvegardes déjà existantes : il n'est plus constructible. Une boutique P’TIBUG est prévue plus tard : les habitants demanderont uniquement les espèces de base ; le Sourcier gardera des contrats distincts, avec les délais cibles de 48 h (base), 5 jours (Trait spécifique) et 7 jours (Trait + Module), sans bloquer ses autres contrats.

Migration explicitement autorisée : lorsqu'une ancienne boutique est reconnue comme première boutique, ses piles sont transférées vers `market.stock`, son niveau devient celui de la boutique principale et son distributeur est fusionné avec `market.distributor` sans supprimer de pile ni de dépôt. Le nouveau **Magasin P’TIBUG** accepte Scarabé, Hyme et Arac de base : un P’TIBUG avec Trait, Évolution ou Module n'est jamais sélectionné. Les demandes habitantes et les contrats Sourcier `ptibug` consomment directement une créature de base de la réserve ; la carte affiche les disponibilités par espèce. Les contrats P’TIBUG de base expirent après 48 h ; les demandes de Trait/Module restent documentées comme étapes futures.
# Fabrication parallèle des modules P’TIBUG

Les modules P’TIBUG sont désormais des commandes de l’Atelier : chaque P’TIPOTE affecté occupe un emplacement Atelier et peut fabriquer un module en parallèle des autres. Le créneau manuel reste unique et coûte une unité d’Énergie de lancement supplémentaire, en plus du coût propre au module. Un craft confié à un P’TIPOTE reçoit une réduction de durée de 20 % configurée par `workshop.ptipoteCraftTimeReductionPercent`; elle s’applique à tous les crafts Cuisine, Atelier et modules.

# Météo globale V1

La météo Zone 0 est maintenant portée par un seul `GlobalWeatherEvent` actif et un événement suivant déjà tiré : type, intensité, horaires, biomes touchés, impacts locaux, graine et état (`planned`, `announced`, `active`, `completed`) sont sauvegardés dans `users/{uid}/game/zone0.weather`. Le cycle par défaut est de 6 h et la Tour annonce exactement le prochain événement 2 h avant son début. Les anciens `WeatherAlert` restent lus pour la migration et les missions Kernel, mais ne calculent plus eux-mêmes le malus P’TIBUG.

Les intensités sont Calme, Modérée, Forte et Sévère. Temps calme ne génère aucun malus ni mission. Les événements défavorables utilisent les sensibilités configurables de chaque biome : chaque biome est non touché, ou reçoit un impact faible, moyen ou élevé. La Plaine pilote la Nurserie ; chaque Refuge lit uniquement l’impact du biome auquel il appartient. Filtreur, Étanchéité et Réflecteur annulent toujours leur malus respectif. Le malus P’TIBUG est centralisé : base de l’intensité × impact local, puis plafonné par la configuration ; aucun biome hors zone d’impact ne reçoit de malus.

La Tour affiche l’événement actif et la prévision annoncée, avec biomes et impacts. La mission Kernel de préparation est créée une seule fois quand la prévision passe à `announced` et garde l’objet/demande tirés. Les transitions sont résolues au retour hors ligne sans relancer les tirages. Le Dashboard édite `towerOperations.globalWeather` : cycle, préavis, poids/intensités, malus, limites de successions, sensibilités et multiplicateurs locaux. Fichiers principaux : `tower_operations_config.dart`, `remote_zone0_settings.dart`, `zone0_game_state.dart`, `refuge_page.dart`, `tower-operations-config.json`.

Attentes futures non développées : Viabilité et réparations de bâtiments, installations structurelles, maisons/habitants détaillés, demandes météo du Marché, grands chantiers, coffre à Bio-batteries et pertes/transformation de stocks.

# Viabilité des bâtiments V1

Chaque bâtiment fonctionnel possède maintenant un état `BuildingViabilityState` persistant dans `users/{uid}/game/zone0.buildings.viability`. Il contient la Viabilité courante et maximale, le dernier événement météo appliqué, l’état hors service, les alertes et les installations structurelles. Les sauvegardes existantes sont migrées à 100 % : aucune météo passée ne provoque de dégâts rétroactifs.

Les dégâts sont calculés une seule fois lors de l’activation d’un `GlobalWeatherEvent`, dans `Zone0GameState._applyWeatherViabilityDamage`. La formule est : dégâts type/intensité × impact local du biome × protection structurelle, avec un plafond de protection configurable de 70 %. Un bâtiment hors biome touché, en construction initiale ou déjà résolu pour le même événement ne subit aucun second dégât. Les bâtiments du camp sont rattachés à la Plaine ; Nurserie et Refuges lisent leur biome propre.

États : 50–100 % normal ; 1–49 % dégradé ; 0 % hors service. Pour l’Atelier et la Cuisine, le mode dégradé applique +25 % de durée et de coût aux nouveaux crafts. Le Recycleur, le Générateur, le Marché et les territoires P’TIBUG s’arrêtent lorsqu’ils sont hors service ; un craft en cours est suspendu et conserve sa progression. Les P’TIBUG d’une Nurserie ou d’un Refuge hors service cessent de consommer et de produire, sans perdre leur affectation ni leur stock.

Une panne peut être remise en marche par le diagnostic prototype (mini-jeu V1) ou par paiement d’Organique, Minéral et Bio-batteries ; cette action restaure seulement la Viabilité minimale. La réparation est distincte de l’amélioration : elle consomme des matériaux et ajoute une portion de Viabilité sans changer le niveau. Chaque niveau du bâtiment ouvre un emplacement structurel. Ventilation Termite réduit les dégâts de Forte chaleur, Chloro-canaux ceux de Pluie intense et Installation filtrante ceux de Nuage toxique ; les rendements décroissants et le plafond sont configurés.

Le Dashboard expose `towerOperations.buildingViability` : seuils, dégâts par météo/intensité, réparation, remise en marche, slots et protections. Fichiers métier : `tower_operations_config.dart`, `remote_zone0_settings.dart`, `zone0_game_state.dart`; interface : `refuge_page.dart`; configuration : `tower-operations-config.json`.

### Ajustements météo, Kernel et Biomasse

- La Tour ne montre plus de carte « prochaine météo » ni de compte à rebours redondant : la carte de l’événement actif reste la source de durée. Elle liste désormais les protections pertinentes pour cet événement : installation structurelle de bâtiment, branche de grands chantiers du Cœur, contre-mesure P’TIBUG et produits que les habitants peuvent demander au Marché.
- Les anciennes missions météo du Kernel sont retirées de la configuration et des missions calculées. L’onglet **Météo** du Kernel disparaît ; les préparations météo sont visibles dans la Tour, le Cœur et le Marché.
- Chaque carte de biome territoriale affiche de nouveau la météo active. Si le biome est touché, elle indique le malus P’TIBUG maximal calculé pour le biome et le nombre de P’TIBUG non protégés ; si le biome est hors zone, aucun malus n’est annoncé. Le calcul reste celui de `pTibugWeatherMalusPercentFor`, donc aucune seconde formule d’interface n’est créée.
- La consommation de Vigueur/Biomasse des missions est maintenant exprimée par heure de mission : le coût d’intensité et de type est multiplié par les heures théoriques, puis pondéré une seule fois par l’avancement réel à la résolution. L’estimation avant départ utilise la même durée et le même calcul.
- La carte de niveau du Marché masque « Prochaine vente : stock vide » lorsqu’aucune vente n’est planifiée.

### Installations et coffre de la Maison

- Les installations structurelles utilisent les objets déjà fabriqués dans l’inventaire global : Ventilation Termite, Chloro-canaux et Installation filtrante. Dans les améliorations, elles sont choisies depuis des emplacements visuels « + » ; toucher un emplacement vide affiche uniquement les installations réellement disponibles en stock, puis l’objet est consommé et le bonus est appliqué. Toucher une installation posée la retire et la restitue à l’inventaire, sans duplication.
- La carte de Viabilité, incluant les emplacements d’installation, est présente dans les améliorations du Fablab, de la Maison et de la Nurserie ; les cartes de Refuge réutilisent le même composant et la même sauvegarde `buildings.viability`.
- Le coffre de la Maison ne crée pas une seconde monnaie : il protège une partie du même total HUD de Bio-batteries. Sa capacité est de 50 au niveau 0, puis augmente de 20 par amélioration, jusqu’à quatre améliorations. Les coûts par défaut sont 30, 35, 40 et 50 Minéral ; ils sont configurables dans `campHeart.communityProjects`. Le niveau est sauvegardé dans `buildings.house.protectedBatteryChestLevel`.
- L’icône coffre de la Maison ouvre le détail protégées/exposées et l’amélioration. Le coffre n’est pas dupliqué dans le tableau P’TIPOTES ; son détail affiche une jauge de remplissage des Bio-batteries protégées par rapport à sa capacité.
- Le tableau P’TIPOTES reprend le rendu de collection de la page **Mes P’TIPOTES** : une carte par compagnon avec portrait, espèce, type, surnom modifiable, éleveur, niveau et XP. Chaque carte ajoute l’activité de jeu en cours, son compte à rebours éventuel, la faim, le sommeil et l’énergie.

# Habitants et maisons météo V1

La couche sociale reste volontairement minimale. `Zone0Resident` conserve une identité stable, un nom, une maison éventuelle, un bonheur de base et des modificateurs temporaires ; `ResidentHouse` garde sa capacité, ses habitants, sa Viabilité, ses protections et le dernier événement météo résolu. Les deux listes sont persistées dans `users/{uid}/game/zone0.buildings.housing`.

Une migration crée autant d’habitants que la population déjà acquise, sans réduire celle-ci, puis une maison fonctionnelle par logement construit. Les habitants sont répartis automatiquement sans dépassement de capacité ; les autres restent explicitement sans logement. Le bonheur global du refuge est désormais la moyenne des habitants actifs, avec la valeur neutre configurée quand la liste est vide. Une maison sous 50 % applique le malus temporaire configuré (−30 % par défaut) à ses résidents ; ce malus disparaît dès 50 %, sans modifier leur bonheur de base.

Les maisons utilisent le même événement météo global et le même plafond de protection structurelle que les bâtiments : dégâts uniques par événement, uniquement dans un biome touché. Elles n’ont ni mini-jeu ni cycle à suspendre ; leur réparation par paliers consomme Organique et Minéral. Ventilation Termite, Chloro-canaux et Installation filtrante peuvent être installés dans les emplacements configurés de la maison.

Le Marché conserve les demandes ordinaires sans pénalité à l’expiration. Lorsqu’un événement météo est annoncé ou actif, les nouvelles demandes éligibles sont orientées à 80 % par défaut vers les produits configurés pour cette météo, sans transformer les cartes existantes et avec un maximum simultané égal au tiers des habitants actifs. L’étiquette `weatherType` est sauvegardée avec la demande. Réglages : `housing-config.json` et `market-config.json`; fichiers : `housing_config.dart`, `market_config.dart`, `remote_zone0_settings.dart`, `zone0_game_state.dart`, `refuge_page.dart`.

# Grands chantiers du Cœur et stocks météo V1

Le premier onglet du Cœur du camp affiche les grands chantiers communautaires. Le niveau du Cœur fixe le nombre total de choix disponibles (un par niveau par défaut) et un seul chantier peut progresser à la fois. Les branches sont : **Réflecteur solaire → Bois aux Hautes-Cimes** pour la Forte chaleur ; **Canalisations → Mousse-mycelium → Bois stabilisateur** pour la Pluie intense ; **Filtration géante → Champignon géant** pour le Nuage toxique. Les prérequis de branche sont obligatoires, mais les trois branches restent indépendantes.

Un chantier choisi reçoit d’abord ses matériaux depuis l’inventaire global, puis des points de contribution. Le joueur ajoute une contribution quotidienne (5 par défaut) ; chaque habitant actif avec un bonheur d’au moins 70 ajoute 1 point par jour. Ces valeurs, les coûts, les paliers, le plafond facultatif de contribution habitante et la valeur de protection sont éditables dans Dashboard → Cœur du Camp → « Grands chantiers, coffre et pertes météo ». L’état et les dépôts sont enregistrés dans `buildings.communityProjects` : aucun point n’est rejoué lors d’une réouverture.

Un chantier terminé ajoute sa protection aux dégâts de Viabilité de tous les bâtiments et maisons touchés par sa météo. Cette protection passe par le même calcul centralisé que les installations locales et reste bornée par le plafond global de 70 % : elle ne protège jamais directement les P’TIBUG ni leurs malus de production.

La Maison possède un coffre logique, pas une seconde monnaie : les premières 50 Bio-batteries du total HUD sont protégées, le surplus est exposé. Lors d’une météo qui touche la Plaine, les aliments périssables configurés (Organique et Repas simple V1) perdus deviennent des Déchets. Pendant une Pluie intense, seules les Bio-batteries exposées peuvent être perdues. Les pertes sont déterministes et mémorisées une fois par `weatherEventId` dans `buildings.weatherStockLoss`; l’incident est visible au Cœur et envoyé dans le rapport système. Les taux par intensité et la capacité du coffre sont configurables dans `camp-heart-config.json`; aucun ancien événement n’est rejoué pendant la migration.

### Énergie, Bio-piles et Cœurs d’énergie

- Le HUD utilise un unique pictogramme de batterie. Les Bio-batteries (unités, dizaines et centaines) sont bleues ; les Bio-piles (fraction fine) sont jaunes. Cent Bio-piles se convertissent automatiquement en une Bio-batterie. Quand il n’existe aucune Bio-batterie entière, le HUD affiche uniquement la quantité de Bio-piles, sans préfixe `0,`.
- À 600 Bio-batteries, `Zone0GameState._resolveEnergyCoreMilestones()` découvre une seule fois le Pattern **Cœur d’énergie** et place un rapport dans la boîte Kernel. Le Plan demande 20 Données Énergie, 20 Organiques, 10 Minérales, 15 Mycéliennes et 15 Biomimétismes avant activation.
- Une fois le Plan activé, l’Atelier fabrique un `Cœur d’énergie` en 15 minutes à partir de 300 Bio-batteries, 10 Organiques et 10 Minéraux. Le Cœur est un objet d’inventaire non empilable et occupe donc une place.
- Les alertes refermables sous le HUD apparaissent à 600 puis 699 Bio-batteries. Un Cœur contient 300 Bio-batteries ; son descellage est volontairement refusé au-dessus de 699, afin que le total ne dépasse jamais le plafond de 999.
- Le coffre de la Maison reçoit un emplacement de Cœur par niveau à partir du niveau 2. Les Cœurs stockés sont affichés comme des emplacements remplis, ouvrent une feuille de confirmation **Desceller**, et ne constituent pas une deuxième monnaie. Les valeurs sont persistées dans `zone0Runtime.kernel` : `energyCorePatternDiscovered`, alertes et `storedEnergyCores`.
- Fichiers principaux : `craft_config.dart`, `kernel_progress_config.dart`, `zone0_game_state.dart`, `refuge_page.dart` et `AI_READ_FIRST_PTIPOTE_APP_DATA_CARD.md`.

### Infusion des Traits et Évolution P’TIBUG

- `PTibugCultivationOperation` porte désormais un type persistant : `cultivation`, `traitInfusion` ou `evolution`. Une cuve garde toujours une seule opération et le même moteur de temps actif, de pause, de reprise, d’autonomie et de calcul hors ligne traite les trois cas.
- Une Infusion dure 6 h actives par défaut. Le coût total Organique/Minéral vaut 30 % du coût d’une Cultivation complète de l’espèce ; l’Énergie suit aussi un coefficient de 30 %. Les Cellules du rang de Trait sont réservées depuis `pTibugDataReserve` dès le lancement et ne peuvent donc jamais financer deux opérations. Le tapotement avance de 30 minutes actives.
- L’Évolution dure 12 h actives par défaut. Elle requiert niveau 3, Trait principal rang III, production matérielle et compartiment de Cellules vides. Ses coûts matériels/énergétiques sont réglés à 50 % de la Cultivation complète et sa recette de Cellules commune est configurable. Elle conserve identité, niveau, Traits et Modules, puis rend disponible le second Trait aux niveaux 4–6.
- Les ratios Hyme/Scarabé/Arac restent ceux de la Cultivation. Les débits de cuve sont ajustés à la durée de chaque opération afin qu’une cuve pleine garde environ 8 h d’autonomie, y compris pour l’Infusion et l’Évolution.
- Un P’TIBUG placé en cuve est retiré temporairement de son bâtiment territorial, cesse de produire et de consommer localement, reste visible avec l’état **En cuve**, et ne peut pas être affecté ou voir ses Modules modifiés. La précédente affectation est persistée dans l’opération pour une réaffectation explicite ultérieure. À la finalisation, le résultat est appliqué une seule fois puis la cuve est libérée.
- Une annulation restitue le P’TIBUG et les Cellules réservées, mais pas la consommation continue déjà effectuée. Les P’TIBUG existants ne sont jamais convertis ni détruits ; l’ancien libellé Renouvellement devient Évolution côté interface, tandis que les clés de sauvegarde historiques restent lues pour compatibilité.
- Réglages : `ptibug.cultivation` dans le Dashboard (`traitInfusionHours`, `evolutionHours`, coefficients, bonus de tapotement, recettes de Cellules et ratios). Fichiers : `ptibug_config.dart`, `remote_zone0_settings.dart`, `zone0_game_state.dart`, `refuge_page.dart`, `ptibug-config.json` et `app.js`.

### Identité, valeur et Capsules P’TIBUG certifiées

- Chaque P’TIBUG actif conserve un nom personnel (`displayName`) distinct de son espèce et de son Pattern. `defaultDisplayName`, l’historique de noms, la date et le compteur de renommage assurent une migration stable des anciennes créatures. Les noms créés à l’ouverture d’une cuve reçoivent un nom temporaire unique et peuvent ensuite être renommés gratuitement.
- `PTibugValuationService` calcule à la demande une valeur additive : base de l’espèce + palier cumulé de niveau + valeur de chaque Trait selon son rang + Modules effectivement équipés. Les Modules non équipés restent exclus. Le détail est affiché dans la fiche P’TIBUG et la valeur ne vaut jamais promesse de paiement.
- `ptibug.valuation` pilote la version, les règles de nom, les valeurs de base, les paliers, les rangs de Traits, les Modules, les coefficients Marché/Sourcier et le minimum de paiement. Les transactions gardent le snapshot de ces quatre composantes et de la version employée.
- Une vente crée une **Capsule P’TIBUG certifiée** : identité, espèce, niveau, Évolution, Traits, Modules, valorisation et paiement sont archivés. La mutation retire atomiquement le P’TIBUG de la collection active, retire ses Modules équipés, crédite les Bio-batteries et laisse le P’TIBUG dans `soldArchive` pour la traçabilité. Une créature vendue ne redevient pas active.
- Les Capsules sont préparées uniquement en réponse à une demande ou un contrat ; l’ancien bouton d’encapsulation libre n’est plus proposé dans la fiche. Les contrats historiques d’espèces de base sont migrés vers un archivage certifié sans recréditer les anciennes ventes.

### Administration Dashboard — comptes de test

- Le Dashboard admin liste les documents `users/{uid}` lisibles et affiche les niveaux des bâtiments principaux.
- **Remettre à zéro** demande une confirmation, supprime la progression et les bâtiments du document utilisateur, puis restaure seulement l’identité et le rôle nécessaires à la reconnexion.
- Les sous-collections Firestore, dont `users/{uid}/figurines`, ne sont pas supprimées : les P’TIPOTES sont conservés. Cette action reste réservée aux administrateurs/devs.

### Marché et Capsules — ajustements V1

- Une Bio-batterie vaut désormais **100 Bio-piles**. Le HUD affiche les batteries en bleu et le reliquat de piles en jaune.
- Le P’TIPOTE du Point info propose toujours **Faire rentrer** et, dès le niveau 2, **Gestion appro**. Les distributeurs se remplissent depuis le stock de leur magasin avant toute vente automatique ; le P’TIPOTE ne répond qu’ensuite.
- Le premier magasin spécialisé consomme les mêmes coûts que les suivants : 20 Organique, 30 Minéral et 10 Bio-batteries. Les distributeurs gardent leur dépôt progressif sans fermer la fenêtre après chaque ajout.
- La mise en Capsule est libre depuis la Nurserie : 1 Bio-batterie et 10 Minéral, avec prévisualisation. Elle conserve l’identité et les Traits ; la vente reste liée à une demande ou un contrat.
- Les contrats P’TIBUG du Sourcier reprennent la valeur de référence affichée dans la Nurserie ; la confiance ajoute son bonus uniquement au paiement final. Les contrats gonflés par la migration transitoire `×100` sont corrigés à la lecture.
- Les longues listes utilisent des sections repliables : Patterns, Armatures, Cuves et Capsules dans la Nurserie ; chaque biome dans Lisière → P’TIBUG ; Équipements, Structures, Meubles et Modules dans l’Atelier. Le gros accès à la Nurserie reste au-dessus de la Plaine.
- Au retour du Marché, le rapport du P’TIPOTE indique désormais sa durée de présence, les Bio-piles gagnées par ses propres ventes et l’XP acquise.

### Chantiers Marché et Nurserie — dépôt progressif

- Le choix d’un type de magasin ne construit plus ni ne facture instantanément. Il crée un ordre sauvegardé : **20 Organique, 30 Minéral et 10 Bio-batteries** doivent être déposés, puis le joueur lance les travaux. La construction termine hors ligne et crée le magasin une seule fois.
- Les feuilles de chantier Magasin, Distributeur et Cuve utilisent maintenant la même UX que le Fablab : jauge `déposé / requis`, actions **+1**, **+5**, **Max**, retour des matériaux et bouton **Commencer les travaux**. Les Bio-batteries sont elles aussi déposées avant le lancement ; aucune fenêtre ne se ferme après un ajout.

### Contrats P’TIBUG du Sourcier — valeur certifiée

- Un contrat de P’TIBUG de base part désormais de la valeur de certification de la Nurserie : Scarabé **20** Bio-batteries, Hyme **22**, Arac **24**. Le bonus de confiance du Sourcier est ensuite calculé et affiché séparément dans le paiement prévu.
- Lors de la livraison d’un P’TIBUG certifié, la valeur réelle du P’TIBUG (espèce, niveau, Traits et Modules équipés) est recalculée par `PTibugValuationService`, puis seul le bonus de confiance est appliqué. Ainsi, une future commande demandant des Traits ou Modules spécifiques s’appuiera sur la même certification, sans barème concurrent.
- Les contrats P’TIBUG ouverts provenant de l’ancienne conversion erronée sont relevés à la valeur minimale de leur espèce. Les contrats déjà terminés ne sont jamais modifiés.

### Cellules de mission et seuil du Cœur d’énergie

- En Mission **Récolte**, la chance de Cellule occasionnelle passe de 25 % à **12,5 %** des chances usuelles : le gain attendu de Cellules est divisé par deux. En Mission **Recherche**, cette chance passe de 100 % à **150 %** des chances usuelles.
- Le Pattern **Cœur d’énergie** est découvert uniquement quand le stock atteint **600 Bio-batteries**. Il est exclu de la découverte générique des Plans Kernel. À la migration, un Pattern découvert avant 600 est retiré de la liste, avec restitution des Données déjà investies dans ce Plan ; à 600 ou plus, la découverte normale reste inchangée.

### Prévision de production territoriale P’TIBUG

- Les cartes de la Nurserie et des Refuges utilisent une prévision déterministe. Les ressources pondérées d’Arac sont sélectionnées de manière stable à partir de son identifiant pour l’affichage, sans consommer de hasard lors d’une reconstruction de widget.
- Le cycle de production réel conserve son tirage pondéré et n’est exécuté qu’au moment de l’échéance de cycle sauvegardée. L’ouverture répétée de Lisière → P’TIBUG ne modifie donc ni le résumé affiché ni la production réellement stockée.

### Cœur du Camp — habitants par maison

- Dans l’onglet **Habitation**, les habitants actifs sont affichés directement dans la carte de la maison qu’ils occupent, avec leur nom et leur niveau de bonheur. La liste distincte ne conserve que les habitants actifs sans logement, afin de rendre immédiatement visible la répartition réelle des foyers.

### Navigation P’TIBUG — ajustements d’interface

- Une Armature associée à une opération de cuve garde sa carte visible, mais son action devient **En cours de cultivation** et ne peut plus être sélectionnée une seconde fois.
- La Plaine utilise désormais le même volet déroulant que les autres biomes dans Lisière → P’TIBUG. Dans Nurserie → Données, les Traits, Modules, Capsules et Données de Traits sont des sections repliables pour éviter les listes trop longues.
- La feuille ouverte depuis une Maison du Cœur du Camp contraint sa hauteur et utilise des cartes à largeur complète pour les installations : les libellés ne sont plus compressés verticalement.

### Noms territoriaux canoniques

- Les libellés historiques de la Lisière ne sont plus affichés. Les correspondances sont : `colline` → **Hauts-Refuges**, `plaineRiche` → **Savane tropicale**, `bassinMineral` → **Semi-désert / Garrigue tropicale** et `sousBois` → **Forêt humide relictuelle**.
- Les identifiants techniques historiques restent volontairement inchangés dans les sauvegardes, les missions et les clés Dashboard afin de préserver les parties existantes. Seuls leurs libellés visibles, les objectifs Kernel, les messages météo et les réglages publiés sont harmonisés.
- Les tables de Cellules restent liées aux identifiants canoniques P’TIBUG ; les Cellules de mission et de Capteur intelligent affichent donc le même biome territorial que les cartes P’TIBUG et le Dashboard.

### Fiche détaillée P’TIBUG depuis la Lisière

- Toucher le portrait ou le nom d’un P’TIBUG dans une carte territoriale ouvre désormais la fiche complète de la **Collection** de la Nurserie, directement sur l’onglet Collection. La vue courte propre à la Lisière a été retirée pour qu’il n’existe qu’une seule modale de détail, avec certification, calcul, Traits, Modules et actions compatibles.

### Entrée et sortie de cuve P’TIBUG

- Un P’TIBUG existant envoyé en cuve pour une Infusion ou une Évolution récolte d’abord automatiquement ses ressources et Cellules prêtes via la même transaction que le bouton Récolter ; en cas d’inventaire matériel plein, le reliquat reste sauvegardé sur lui.
- Tant qu’il est en cuve, il est désaffecté, ne produit ni ne consomme localement et le bouton **Affecter** est remplacé par **Sortir de cuve** dans la Collection comme dans Lisière → P’TIBUG. Cette action annule l’opération en cours, restitue les réserves/Cellules non consommées et rend le P’TIBUG de nouveau affectable.

### Tapotement rythmé des cuves

- Le bouton **Tapoter** d’une cuve active ouvre désormais le même défi de rythme visuel que l’Œuf de Co-training : pulsations à observer, tolérance temporelle identique, remise à zéro et possibilité de rejouer le rythme.
- Une séance de cuve demande une séquence de **3 à 6 tapotements**, choisie de manière stable selon la cuve et la séance courante. Le bonus de temps n’est appliqué qu’après validation complète de la séquence ; les limites journalières et délais minimums restent vérifiés par `applyCultivationTap`.

### Habitants V1 — identités et maisons persistantes

- `Zone0Resident` dans `ptipote-app/lib/features/game/zone0_game_state.dart` est la source de vérité d’un habitant : identité stable, maison, bonheur de base/final, modificateurs identifiables, compte interne en bio-piles et statut (`active`, `awaitingHousing`, `arriving`, `inactive`, `archived`). Les champs de besoins, envies, passions, inventaires, rôles et visions sont uniquement préparés et restent inactifs.
- La migration `residentPopulationMigrationCompleted` transforme une population numérique héritée en identités persistantes exactement une fois. Les résidents et maisons déjà sauvegardés sont enrichis sans être dupliqués ; les habitants sans place deviennent `awaitingHousing` et restent conservés.
- `ResidentHouse` est une maison fonctionnelle sans niveau : capacité fixe, Viabilité, **3 protections météo** par défaut, 4 emplacements de mobilier, générateur domestique de base, emplacement du second générateur et compte commun. Les emplacements météo, mobilier, énergie et résidents sont distincts.
- Les protections de maisons passent par le même calcul météo centralisé que les bâtiments, avec le plafond global existant. Sous 50 % de Viabilité, le malus de bonheur existant s’applique ; aucune évacuation ou perte d’habitant n’est déclenchée à 0 % dans cette étape.
- Une maison occupée produit par défaut **5 bio-piles/h** dans son compte commun, y compris hors ligne. La production est calculée avec un reste de division sauvegardé, ne s’exécute pas dans une maison vide par défaut et ne distribue encore aucun revenu aux habitants.
- `formatInternalPileBalance` centralise l’affichage interne : 100 bio-piles = 1 bio-batterie. Les comptes domestiques et habitants ne fabriquent jamais automatiquement de Cœur énergétique.

### Réorganisation Cœur, Maison et Kernel

- Le Bio-générateur conserve ses données historiques (`campGenerator`) mais son interface et son rattachement fonctionnel sont déplacés dans l’onglet **Générateur** de la Maison du joueur. Le drapeau persistant `bioGeneratorMovedToPlayerHouse` assure la migration sans recréer ni réinitialiser le générateur.
- Le Cœur du Camp ne propose plus d’onglet Générateur : il est recentré sur le Refuge, l’Habitation, les grands chantiers et un espace Avis préparé pour les futures visions.
- Le Kernel ne présente plus d’onglet **Demandes**. Les missions qui étaient affichées dans cette vue restent visibles sous **Missions** ; une section **Arrivées** vide prépare les futures candidatures sans en générer.
- Réglages Dashboard : `ptipote-dashboard/housing-config.json` et `HousingConfig` : capacités, protections, mobilier, générateur domestique, comptes initiaux et comportement des maisons vides. Le chargeur Firestore est `remote_zone0_settings.dart`.

### Habitants V2 — besoins physiques et inventaire personnel

- `ResidentNeedsState` est désormais persistant pour chaque `Zone0Resident` : jour résolu, repas requis/consommés/manquants, statut nutritionnel, envie, profil intérieur, protections météo requises/manquantes et horodatages. La résolution quotidienne est idempotente : la même journée ne consomme jamais deux fois les mêmes repas.
- `ResidentOwnedItem` stocke uniquement des produits finis personnels (repas, boissons, tenues, protections, meubles ou équipement final). Les matières brutes comme Organique, Minéral et Cellules sont explicitement refusées par `giveResidentFinishedItem`. Le vestiaire est une lecture filtrée de cet inventaire, sans second stock parallèle.
- Chaque habitant requiert **2 repas/jour** par défaut. Les états `nourri`, `partiellement nourri` et `non nourri` appliquent respectivement 0, -10 et -30 bonheur (réglables). La migration laisse les habitants nourris pour la journée courante et accorde 24 h de grâce avant la première consommation automatique.
- Une seule envie stable est attribuée : `Bouche sucrée`, `Aime la sape`, `Aime le confort` ou `Aime les outils`. Elle reste secondaire à la faim et apporte seulement un bonus configurable lorsqu’elle est satisfaite. `Aime la sape` vérifie deux tenues utilisables ; le confort utilise l’intérieur ; les outils peuvent être personnels ou installés.
- Les protections personnelles sont déterminées à l’annonce de la météo globale, puis utilisées une seule fois à l’activation de l’événement : Tenue ombragée pour la chaleur, Peau amphibienne/Tenue étanche pour la pluie et Cartouche/Filtre pour le nuage toxique. Leur durabilité est diminuée par événement, jamais par heure. Un manque applique un modificateur temporaire retiré à la fin de l’événement.
- Les profils d’intérieur `Simple`, `Technique` et `Esthète` lisent uniquement le mobilier réellement installé dans `ResidentHouse`. La V1 de tags associe Meuble simple à lit/meuble fonctionnel/décoration et les installations techniques aux tags techniques. Les capacités de mobilier ne sont jamais confondues avec les slots météo, énergie ou habitants.
- `ResidentHappinessService` centralise le calcul additif (base, nutrition, météo, envie, intérieur, Viabilité, logement et historiques), plafonné entre 0 et 100. La fiche Habitant affiche le détail actif ; le bonheur global/Harmonie continue d’utiliser cette même valeur.
- Les besoins météo et matériels sont préparés comme états lisibles par le futur Marché, sans créer encore de demande commerciale automatique ni de demande de ressource brute. Les écrans Habitation proposent les gestes de test : donner un repas fini et installer un Meuble simple.
- Réglages Dashboard : la section `housing-config.json` expose repas, malus nutritionnels, bonus intérieur/envie, usure des protections, malus météo, grâce de migration et nombre de tenues. Les fichiers principaux sont `zone0_game_state.dart`, `housing_config.dart`, `remote_zone0_settings.dart`, `refuge_page.dart` et `ptipote-dashboard/app.js`.

### Habitants V3 — passions et rôles communautaires

- Chaque habitant actif possède une seule passion persistante : **Cuisiner**, **Fabriquer**, **Commercer**, **Observer le vivant** ou **Veiller**. La migration diversifie d’abord les petites populations puis emploie un tirage pondéré et déterministe. Les anciennes valeurs `protect`, `weatherStudy` et `weather` sont converties vers `watching` (Veiller).
- `CommunityRoleAssignment` conserve un historique atomique de rôle : habitant, passion, bâtiment, slot, état, dates, capacité, production journalière et reste d’efficacité. Un changement archive le rôle précédent, libère son slot et ne laisse jamais un habitant actif dans deux rôles.
- Les slots habitants sont distincts des slots P’TIPOTE, P’TIBUG, craft et boutiques. Cuisine et Atelier gagnent des slots selon leur niveau ; le Marché et la Lisière ont leur propre slot ; les rôles Sécurité et Météo partagent les slots de la Tour afin qu’un Veilleur ne cumule pas les deux bonus.
- La Cuisine communautaire fabrique uniquement des **Repas simples** avec les ingrédients physiques de la recette existante et les attribue dans l’inventaire personnel des habitants prioritaires (0 repas, puis 1 repas, puis identifiant stable). Sans ingrédients elle passe en `awaitingResources`, sans supprimer l’affectation. Le Fablab communautaire fabrique lentement un Filtre fini, jamais Modules, Cœurs, Capsules ou recettes avancées.
- L’Observation en Lisière est une exception explicitement configurée : elle rapporte lentement de l’Organique (et éventuellement du Minéral) mais reste suspendue en météo défavorable ou sous le seuil de Sécurité. Veiller à la Sécurité ajoute **+1 Sécurité / 3 h** par défaut, avec plafond existant ; Veiller à la météo produit seulement un indicateur de couverture, sans raccourcir l’annonce globale.
- Les habitants utilisent une efficacité communautaire de **50 %** par défaut, accumulée avec un reste sauvegardé afin que les petites productions ne deviennent pas gratuites. Les cycles sont calculés hors ligne, limités, liés aux stocks/capacités et idempotents.
- `CommunityCoverageService` centralise rôles actifs/en pause, slots libres, couverture alimentaire, repas restant, Sécurité et observation produites, ainsi que la disponibilité commerciale préparatoire. Il n’y a pas encore de revenus, de propriété automatique de boutique, de vente habitant ni de demande de Capsule automatique.
- `ownedCertifiedPtibugIds` reste la base préparatoire pour la future possession P’TIBUG : plafond configurable de 3, chance configurable de 10 % au moment d’une future demande uniquement, sans nouveau tirage à l’ouverture ni transaction dans cette étape.
- Réglages Dashboard : `ptipote-dashboard/community-roles-config.json`, chargé par `remote_zone0_settings.dart`, couvre poids, efficacité, intervalles, intrants/couverture de cuisine, fabrication, observation, Sécurité et préparation P’TIBUG. L’interface Cœur → Habitation montre le bilan global et la fiche d’un habitant permet l’affectation manuelle aux rôles compatibles.

### Habitants V4 — économie interne, production et règlements

- Tous les comptes internes stockent des **bio-piles entières** : 100 piles = 1 bio-batterie et 200 batteries = 1 Cœur énergétique physique. `formatInternalPileBalance` reste l’unique affichage joueur des comptes internes ; aucun compte d’habitant ou de maison ne crée automatiquement de Cœur énergétique.
- Chaque `ResidentHouse` possède maintenant un horodatage de production (`lastHouseholdEnergyResolvedAt`), un reliquat fractionnaire (`energyProductionRemainder`) et des compteurs de bilan. Une maison occupée produit 5 piles/h par défaut ; le second générateur augmente ce débit de 50 % par défaut, sans ajouter de niveau à la maison. Les fractions sont conservées et les comptes ont des plafonds configurables, très élevés par défaut.
- La distribution est équitable et par lots : toutes les heures par défaut, les piles entières du compte commun sont divisées entre les occupants actifs. Le reste indivisible demeure dans `householdPileBalance`. Un déplacement règle d’abord l’ancienne maison, ce qui interdit une double part durant la même période.
- `ResidentEconomicTransaction`, `EconomicSettlementBatch`, `CommunityProductionBatch` et `SupplierContribution` constituent le grand livre persistant. Chaque mouvement a une clé d’idempotence ; les transactions et règlement quotidiens sont agrégés, tandis que l’historique par habitant reste lisible.
- La Cuisine et le Fablab communautaires ne distribuent plus de produits gratuits : ils consomment les intrants existants, placent le produit fini dans l’inventaire réel et créent un lot avec fabricant, intrants et provenance. Un lot non vendu ne verse aucun revenu.
- `purchaseResidentFinishedItem` est le moteur central et atomique des achats : contrôle du besoin, produit fini, stock, solde, réserve, provenance, transfert, répartition, besoin et historique avant sauvegarde. Les matières brutes sont refusées. La V1 résout automatiquement les repas disponibles ; vêtements, protections, mobilier et installations sont préparés dans la file mais ne déclenchent pas encore d’achat autonome final.
- Une vente d’un lot communautaire répartit le prix en piles selon 50 % fabricant, 25 % fournisseur et 25 % commerçant par défaut. Les parts sont arrondies vers le bas et le reliquat est attribué au commerçant, puis au fabricant ou au joueur. Une contribution sans habitant représente le stock joueur et crédite donc le joueur ; une part absente ne disparaît jamais.
- `ResidentUncoveredNeed` conserve les besoins de produits finis non couverts et une raison (`noStock`, `noProducer`, `insufficientFunds`, etc.). Aucun client habitant ne demande une matière brute ; une insolvabilité ne crée ni dette, ni intérêt, ni solde négatif. `financialStrainScore` est descriptif et ne baisse pas directement le bonheur.
- L’interface Cœur → Habitation affiche un bilan économique global. Les fiches habitant et maison montrent solde, revenus/dépenses, production du foyer, distribution, besoin en attente et historique court. Les réglages sont pilotés par `ptipote-dashboard/resident-economy-config.json`, chargé via `remote_zone0_settings.dart`.
- Limites volontaires V4 : pas de banque, taxe, dette, spéculation, propriété automatique de magasin, réparation autonome ni achat autonome final de meubles/protections/second générateur. Ces décisions seront branchées aux prochains prompts sans changer les comptes ni les lots existants.

### Habitants V5 — Marché, commerces et Point Information

- Le Marché garde un seul bâtiment et trois spécialisations strictes : **Restaurant**, **Équipement** et **Fournitures du foyer**. Les demandes habitantes concernent exclusivement des produits finis ; Organique, Minéral, Cellules et autres intrants restent réservés à la production ou au Sourcier.
- `MarketShopSlot` rend les emplacements persistants et idempotents : niveau 1 = 1 emplacement, niveau 2 = 2, niveau 3 = 4. Les boutiques existantes sont conservées et associées à un slot ; tout excédent hérité est marqué `legacyExtraSlot` au lieu d’être supprimé.
- À partir du niveau 2, un emplacement réellement vacant depuis 7 jours peut créer un préavis de 24 h pour un habitant ayant la passion **Commercer**. Le candidat et la spécialisation sont sauvegardés, le joueur peut encore démarrer sa construction, puis le commerce communautaire devient durable avec propriétaire, stock, capacité et compte en piles distincts.
- Le choix d’un commerce habitant privilégie une catégorie absente, puis les besoins finis non couverts, et vérifie qu’au moins un produit compatible est accessible. Un commerce impossible n’est pas créé et un commerçant ne peut posséder qu’un magasin.
- Le **Livre des demandes** et le **Point Information** sont respectivement déverrouillés au niveau 3. Le P’TIPOTE du Point Information est global : il ne devient pas obligatoire par magasin et ses automatismes restent soumis aux consignes de réapprovisionnement du joueur.
- Les Distributeurs restent attachés aux magasins, respectent leur spécialisation et n’inventent aucun stock. Leur niveau 1 est déverrouillé au Marché 2, le niveau 2 au Marché 3 et le niveau 3 au Marché 4. Le Sourcier et ses contrats restent distincts des demandes habitantes.
- Les réglages V5 sont dans `ptipote-dashboard/market-config.json` : emplacements, vacance, préavis, niveaux du Livre/Point Information, niveaux des Distributeurs, capacité et réserve des commerces habitants. Ils sont chargés par `remote_zone0_settings.dart`.

### Habitants V6 — arrivées, visions et autonomie domestique

- `ResidentArrivalCandidate` devient un dossier narratif persistant : nom, origine, départ, raison de venir, récit court, passion, envie, profil d’intérieur, contribution, conditions concrètes et accompagnants. Les textes sont assemblés une fois puis sauvegardés ; une arrivée n’augmente jamais un simple compteur.
- Les candidatures sont affichées dans **Kernel → Missions → Arrivées**. Le joueur peut accepter, reporter ou refuser. L’acceptation réserve une maison si possible ; les conditions manquantes maintiennent le dossier en attente et l’arrivée ne crée les vrais `Zone0Resident` (accompagnants inclus) qu’à l’échéance, dans une transition atomique.
- Le niveau du Cœur augmente seulement l’attractivité pratique (cadence et limite de dossiers configurables) : il ne force aucune arrivée. Les places réellement libres des `ResidentHouse` restent la contrainte d’installation. Refus, expiration et migration libèrent toujours les réservations.
- `ResidentVision` conserve une seule vision active par habitant vers un grand chantier accessible. Le Cœur affiche les soutiens ; ils conseillent sans contraindre le choix. Un chantier non soutenu déclenche une déception temporaire configurable, un projet mené à terme accorde un bonus modéré plafonné et génère ensuite une ambition de palier supérieur (70 % même branche, 30 % autre branche par défaut).
- `HouseholdAutonomyService` ordonne les décisions lentes des foyers : protection avant météo, Kit de réparation sous 50 % de Viabilité, mobilier requis, puis second générateur seulement en cas de manque financier durable et de besoins alimentaires déjà stabilisés. Les produits sont achetés dans des stocks réels de magasin avec les piles communes, puis éventuellement une contribution plafonnée et égale des occupants ; aucune matière brute ni objet gratuit n’est créé.
- Les maisons restent sans niveau et gardent leurs trois slots météo, slots mobilier et unique emplacement de second générateur. Le plafond météo global reste celui du service central (70 % par défaut). Chaque décision est mémorisée dans la maison afin que l’interface explique le blocage ou la priorité.
- `HouseholdRepairJob` persiste les réparations : un Kit fini réservé permet +10 % de Viabilité en 3 jours par défaut. Une intervention du joueur est plus rapide, suspend sans perdre une réparation habitante et la reprend seulement si nécessaire. Les résolutions hors ligne respectent les stocks, les horodatages et les clés d’idempotence.
- Les réglages V6 sont ajoutés à `ptipote-dashboard/housing-config.json` et lus par `HousingConfig`/`remote_zone0_settings.dart` : limites et délais d’arrivées, visions, réserve de foyer, contribution et réparation autonome. Les nouvelles listes sont sauvegardées dans `buildings.housing` avec les habitants et maisons existants.
- Limites volontaires : aucune natalité, mortalité, dette, taxe, niveau de maison, arrivée automatique non validée, demande habitante de matière brute ou système politique contraignant.

### Correctifs Marché — retour P’TIPOTE, Sourcier et Distributeurs

- Le retour manuel du P’TIPOTE du Point Information passe toujours par `removeFromMarket` et affiche désormais un bilan complet : durée, bio-piles, XP, articles vendus et Distributeurs réparés. Le même bilan est enregistré dans le Journal du Marché ; un retour automatique par fatigue conserve la mise au repos.
- La carte du P’TIPOTE du Marché est organisée en trois colonnes : identité et image, statistiques, puis actions. Le bouton **Faire rentrer** affiche explicitement le résultat, y compris dans l’état de repli.
- Le Livre des demandes mémorise le surnom du P’TIPOTE ayant réellement servi une demande. Les ventes de Distributeur et joueur conservent leur libellé propre.
- Les Capsules P’TIBUG certifiées sont reconnues comme stock P’TIBUG pour les contrats du Sourcier ; une Capsule disponible peut satisfaire un contrat d’espèce correspondante. Le Magasin P’TIBUG accepte aussi le libellé de Capsule.
- Le Sourcier indique désormais le magasin spécialisé requis pour chaque contrat. Les matériaux bruts utiles au Sourcier sont explicitement acceptés par le Magasin du foyer ; cette exception n’autorise pas les habitants à demander des matières brutes.
- Un chantier de magasin peut être arrêté même après son démarrage : tous les matériaux et Bio-batteries déposés sont rendus atomiquement, puis l’emplacement réservé est libéré si nécessaire.
- Un Distributeur peut être amélioré séparément de son magasin. Sa progression reste limitée par les paliers du Marché, possède son propre coût et sa propre durée, et n’augmente jamais le niveau de la boutique.

### Météo, Viabilité et carte territoriale P’TIBUG

- Chaque bilan météo distingue les pertes réellement appliquées : moyenne et total de Viabilité perdus par les habitations, même lecture pour les Refuges P’TIBUG, Organique converti en Déchets et Bio-batteries exposées perdues. Les nouvelles valeurs sont persistées dans l’incident météo, sans rejouer les dégâts à l’ouverture.
- Les repères du camp affichent une jauge de Viabilité sous le nom du bâtiment. La couleur évolue du jaune légèrement vert quand le bâtiment est sain jusqu’au rouge sous 10 % ; elle lit le même `BuildingViabilityState` que les dégâts météo et ne crée pas de seconde jauge.
- Lisière → P’TIBUG utilise une carte territoriale 3×3 construite sur la topologie de l’Exploration de la Tour. La Plaine propose la Nurserie, les autres biomes un Refuge. Un territoire construit montre son pictogramme de maison et sa Viabilité ; toucher la Nurserie ouvre sa page existante, les autres tuiles ouvrent leur carte existante.
- Le bouton **Entrer dans la Nurserie** reste grisé avant la construction. Les P’TIBUG inactifs restent sous la carte : leur dépôt sur un Refuge/Nurserie construit demande confirmation avant l’affectation.
- Les cartes territoriales présentent l’identité technique plutôt que le surnom de Collection : espèce de base, armature/style et Trait biologique. Le nom personnel reste réservé à la Collection et au dialogue d’affectation.

### Aspect esthétique P’TIBUG

- Un P’TIBUG conserve désormais un aspect visuel persistant : couleur principale, motif facultatif, couleur pastel du motif, couleur du Trait et animation nominale. Ces valeurs ne modifient ni production, ni XP, ni valeur commerciale.
- Une Infusion de Trait actualise l’aspect : une couleur est tirée parmi les quatre couleurs de l’espèce et un motif apparaît avec 30 % de chance par défaut. Le motif prend une couleur principale adoucie ; le noir reste noir et ne peut pas être repris comme motif lorsque le P’TIBUG est déjà noir.
- Hyme utilise jaune/bleu/orange/noir et le motif **Rayé** ; Scarabé vert/bleu/rouge/noir et **Irisé** ; Arac violet/rouge/jaune/noir et **Pointillé**. Les P’TIBUG déjà sauvegardés reçoivent un aspect une seule fois à leur migration.
- Les animations nominales sont **Volant** ou **Terrier** pour Hyme, **Cornu** ou **Briseur** pour Scarabé, et **Sauteuse** ou **Tisseuse** pour Arac. Elles sont tirées et sauvegardées avec l’aspect, sans animation graphique imposée à ce stade.
- Le Dashboard expose ces palettes comme sélecteurs RGB dans `ptibug-config.json`. Le pictogramme utilise déjà la couleur principale ; les rendus détaillés des motifs seront ajoutés lorsque leurs règles graphiques seront fournies.
