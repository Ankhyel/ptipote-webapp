# PTIPOTE Dashboard

Dashboard interne statique pour suivre les donnees admin de PTIPOTE sans exposer de credentials serveur.

## Architecture choisie

- App web statique dans `ptipote-dashboard`, sans build step.
- Firebase Web SDK charge depuis le CDN.
- Auth Google cote client.
- Lectures Firestore avec `getCountFromServer()` pour eviter de telecharger les documents.
- Securite attendue dans Firestore rules : seuls les comptes admin/dev doivent pouvoir lire ces collections ou les futurs agregats.

Cette premiere version ne contient aucune cle admin. La cle Firebase Web est un identifiant client normal ; elle ne donne pas de droits si les rules Firestore sont correctes.

## Stats tentees par le dashboard

- `users` : nombre total d'utilisateurs.
- `users/*/figurines` : nombre total de PTIPOTES enregistres via collection group.
- `publicFigurines` : nombre de PTIPOTES publics.
- `transferRequests` : total des demandes de transfert.
- `transferRequests` par `status` : `pending`, `accepted`, `confirmed`, `refused`.

Si les rules refusent l'acces, les cartes affichent un tiret et un message explicite.

## Rules Firestore recommandees

Le repo ne contient pas encore de `firestore.rules`. Pour un dashboard interne, privilegier un custom claim `admin` pose par un environnement serveur ou la console Admin SDK.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function isAdmin() {
      return request.auth != null && request.auth.token.admin == true;
    }

    match /users/{userId} {
      allow read: if isAdmin();
      match /figurines/{figurineId} {
        allow read: if isAdmin();
      }
      match /notifications/{notificationId} {
        allow read: if isAdmin();
      }
      match /fcmTokens/{tokenId} {
        allow read: if false;
      }
    }

    match /publicProfiles/{uid} {
      allow read: if isAdmin();
    }

    match /publicFigurines/{publicKey} {
      allow read: if isAdmin();
    }

    match /friendInvites/{inviteId} {
      allow read: if isAdmin();
    }

    match /transferRequests/{transferId} {
      allow read: if isAdmin();
    }

    match /chats/{chatId} {
      allow read: if isAdmin();
    }

    match /adminStats/{docId} {
      allow read: if isAdmin();
      allow write: if false;
    }
  }
}
```

Pour `fcmTokens`, eviter une lecture brute cote dashboard. Preferer un agregat serveur, par exemple `adminStats/fcm` avec `activeTokenCount`, `staleTokenCount`, `lastRefreshAt`.

## Donnees a instrumenter ensuite

- Utilisateurs actifs : ajouter `lastSeenAt`, `lastAppOpenAt`, `appVersion`, `platform` dans `users/{uid}`.
- Activite recente : creer `adminEvents/{eventId}` ou `adminStats/recentActivity/items`, alimente par Cloud Functions.
- Scans NFC : logger `scanSuccess`, `scanError`, `publicKey`, `figurineIdHash`, `platform`, `createdAt`.
- Erreurs importantes : logger seulement des codes et contextes non sensibles (`auth_error`, `firestore_permission_denied`, `nfc_write_failed`).
- Notifications FCM : agreger cote serveur les tokens actifs, tokens invalides et erreurs d'envoi.
- Transferts : normaliser `status` avec les valeurs `pending`, `accepted`, `confirmed`, `refused`.

## Lancement local

Depuis la racine du repo :

```bash
python3 -m http.server 5174
```

Puis ouvrir `http://localhost:5174/ptipote-dashboard/`.
