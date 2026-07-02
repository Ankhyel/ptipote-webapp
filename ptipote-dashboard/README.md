# PTIPOTE Dashboard

Dashboard interne statique pour suivre les donnees admin de PTIPOTE sans exposer de credentials serveur.

## Architecture choisie

- App web statique dans `ptipote-dashboard`, sans build step.
- Firebase Web SDK charge depuis le CDN.
- Auth Google cote client.
- Lectures Firestore avec `getCountFromServer()` pour eviter de telecharger les documents.
- Acces dashboard verifie avec `users/{uid}.role` (`admin` ou `dev`) et le bootstrap admin deja present dans `firestore.rules`.

Cette premiere version ne contient aucune cle admin. La cle Firebase Web est un identifiant client normal ; elle ne donne pas de droits si les rules Firestore sont correctes.

## Stats tentees par le dashboard

- `users` : nombre total d'utilisateurs.
- `users/*/figurines` : nombre total de PTIPOTES enregistres via collection group.
- `publicFigurines` : nombre de PTIPOTES publics.
- `transferRequests` : total des demandes de transfert.
- `transferRequests` par `status` : `pending`, `accepted`, `confirmed`, `refused`.

Si les rules refusent l'acces, les cartes affichent un tiret et un message explicite.

## Rules Firestore

Le repo contient `firestore.rules`. Le dashboard suit le modele existant :

- bootstrap admin UID dans `isBootstrapAdmin()`;
- role applicatif dans `users/{uid}.role`;
- roles autorises pour le dashboard : `admin` et `dev`.

La premiere ouverture lit le document `users/{uid}` du compte connecte. Si le role n'est pas `admin` ou `dev`, les compteurs restent bloques cote UI. Les rules gardent la vraie securite et autorisent les lectures necessaires aux compteurs dashboard pour `admin/dev`.

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
