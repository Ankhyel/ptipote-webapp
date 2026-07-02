# PTIPOTE Game - Zone 0 Proto 1

Vertical slice HTML/CSS/JS mobile-first, sans framework et sans backend.

## Tester en local

Depuis la racine du repo :

```bash
python3 -m http.server 4173
```

Puis ouvrir :

```text
http://localhost:4173/ptipote-app/ptipote-game/
```

## Fichiers

- `index.html` : structure de l'app et chargement des scripts.
- `styles.css` : interface mobile-first.
- `data.js` : donnees mockees, batiments, ressources, objectifs.
- `state.js` : etat, sauvegarde localStorage, initialisation future par URL.
- `tasks.js` : recolte, craft, maison, tour, marche, progression.
- `ui-island.js` : HUD, ilot, navigation.
- `ui-panels.js` : fiches basses, P'TIPOTES, journal.
- `main.js` : orchestration et evenements.

## Parcours coeur

Choisir un P'TIPOTE -> l'assigner a la Lisiere -> attendre -> recuperer -> crafter un Repas -> soigner a la Maison -> progresser au Bio-ordinateur.
