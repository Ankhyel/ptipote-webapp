# AI READ FIRST - PTIPOTE App Data Card

Derniere mise a jour: 2026-07-02

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
| Image figurine | `ptipote-app/lib/features/figurines/ptipote_image.dart` | Resolution et affichage des images PTIPOTE. |
| Scan NFC | `ptipote-app/lib/features/nfc/nfc_page.dart` | UI scan, decodage NDEF, adoption, confirmation transfert, carte debug/dev. |
| Profil et roles | `ptipote-app/lib/features/profile/profile_page.dart` | Profil eleveur, panneau admin pour assigner le role dev. |
| Amis | `ptipote-app/lib/features/friends/friends_page.dart` | Recherche profils, invitations, accept/refuse/cancel. |
| Liste chats | `ptipote-app/lib/features/chat/chats_page.dart` | Liste des conversations et badges messages. |
| Conversation chat | `ptipote-app/lib/features/chat/chat_page.dart` | Messages entre deux amis. |
| Jeu / refuge Flutter | `ptipote-app/lib/features/game/refuge_page.dart` | Ecran dev du refuge joueur, accessible par bouton Jeu sur Home si `canSeeDiagnostics`. |
| Assets jeu Flutter | `ptipote-app/ptipote-game/image_game/` | Images d'ecran du jeu, resolues par nom sans dependance a l'extension. |
| Prototype web Zone 0 | `ptipote-app/ptipote-game/` | Vertical slice HTML/CSS/JS mobile-first du refuge: Ilot, P'TIPOTES, Journal, Lisiere, Atelier, Tour, Marche, Maison. |

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
- Dans la page Maison ouverte depuis `RefugePage`, les P'TIPOTES de `FigurineService.watchMyFigurines()` sont affiches comme sprites sur le tiers bas. `PtipoteFigurine.vitality` vaut `3/3` par defaut, et une vitalite a 0 place le P'TIPOTE dans une des trois alcoves du haut.
- Clic sur un sprite dans la Maison: ouvre/ferme une bulle avec espece, type, surnom, niveau, energie, XP et vitalite.
- Test dev Maison: l'emoji haltere permet de choisir un P'TIPOTE puis `Entrainer` retire 1 vitalite localement; a 0 il va dans une alcove.
- Fichiers du prototype: `index.html`, `styles.css`, `data.js`, `state.js`, `tasks.js`, `ui-island.js`, `ui-panels.js`, `main.js`.
- L'ecran Ilot du prototype affiche maintenant le refuge du joueur avec fond illustre, cases batiment a opacite 20%, P'TIPOTE visible et Kernel pour scanner.
- Boucle coeur prototype: choisir un P'TIPOTE -> assigner a la Lisiere -> attendre -> recuperer -> crafter un Repas -> soigner a la Maison -> progresser.
- Handoff V1 mobile: creer progressivement Ilot, Kernel, Lisiere proche/lointaine, Atelier et Cuisine a slots, sans simulation complete.
- Lisiere V1: exactement deux onglets, `Lisiere proche` et `Lisiere lointaine`. Pas d'onglet PTIBUG separe.
- Refuge PTIBUG est un batiment dans le biome Plaine PTIBUG. Plaine PTIBUG = biome, Refuge PTIBUG = batiment.
- Atelier et Cuisine V1 utilisent des slots de salle et des elements contextuels gratuits, pas une main globale de cartes.
- Ne pas casser amis, chat entre amis, transfert, adoption NFC et rules Firestore existantes.
- Si une nouvelle fonction est ajoutee, mettre a jour cette data card avec son fichier source de verite, son flux et ses contraintes.

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
