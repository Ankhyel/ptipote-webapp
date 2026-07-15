# AI READ FIRST - PTIPOTE App Data Card

Derniere mise a jour: 2026-07-09

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
- Risques biome: Colline `10%`, Plaine riche `8%`, Bassin mineral `14%`, Sous-bois `12%`.
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
- Synchro automatique Dashboard -> Flutter runtime non branchee; exporter le JSON et reporter dans `ptipote_stats_config.dart`.
- Mise a jour hors-ligne fine non finalisee: la simulation applique les ticks en Maison et persiste les valeurs, mais la chronologie hors-ligne mission/repos/craft devra etre raffinee quand les activites longues seront toutes modelisees.

## TOUR DE SECURITE ET LISIERE V1

### 1. Fichiers crees ou modifies

- `ptipote-app/lib/features/game/security_tower_config.dart`: configuration V1 de la Tour, cout, slots, gain/decroissance de securite et ticks.
- `ptipote-app/lib/features/game/lisiere_forage_config.dart`: valeurs V1 des biomes, formule de risque minimum, coefficient de reduction securite, dangers possibles et champs futurs de restauration de la Plaine.
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
- Un P'TIPOTE affecte passe en surveillance Tour, disparait de la Maison et devient indisponible pour les missions.

### 3. Securite

- Stockage runtime: `refugeSafety`, sauvegarde Firebase `users/{uid}/game/zone0.campSecurity`.
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
