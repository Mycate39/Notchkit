---
name: notch-video
description: Faire une vidéo de présentation de Notchkit avec la VRAIE encoche filmée (mode démo de l'app, ScreenCaptureKit, fond transparent), montée dans HyperFrames sur des décors reconstruits (bureau, écran verrouillé, vidéo plein écran), avec sous-titres, caméra, pointeur de macOS 27, musique et carte de fin. À utiliser pour toute nouvelle vidéo, démo, publicité ou short de Notchkit, ou pour refaire une vidéo existante « avec la vraie encoche ».
---

# Vidéo de Notchkit avec la vraie encoche

L'encoche n'est jamais redessinée : c'est l'app qui la dessine (SwiftUI, vrais ressorts, symboles,
polices, animations Face ID). Le mode démo de Notchkit joue un scénario minuté sur la vraie encoche et
filme sa fenêtre seule, sur fond transparent. HyperFrames pose cette prise sur un décor et ajoute la
mise en scène.

Projet vidéo : `~/Documents/Projets/Notchkit-video` (hors du dépôt). Moteur commun :
`assets/nk2-engine.js` ; page générée par `assets/make-index.py` ; films avec l'encoche réelle :
`<film>-reel/` (ex. `decompte-reel/`, « 5 New Things in 30 Seconds »), prises dans `tournages/<film>/`.

## 1. Écrire le scénario

Un dossier de tournage par film, un sous-dossier par langue :
`Notchkit-video/tournages/<film>/<en|fr>/scenario.json`.

```json
{ "duration": 28.5, "region": { "width": 900, "height": 260 }, "fps": 60,
  "steps": [ { "at": 3.0, "do": "unlock" },
             { "at": 7.7, "do": "music.play", "title": "danker", "artist": "Gabester" } ] }
```

`at` = secondes depuis le début de la prise ; la vidéo commence à 0 au même instant, donc les temps
du scénario sont ceux du montage. Caler les temps sur les temps du film (sous-titres, chiffres).

| Action (`do`) | Paramètres | Effet (chemin réel de l'app) |
|---|---|---|
| `unlock` / `touchID` | | Animation Face ID / Touch ID (`UnlockModule.preview`) |
| `music.play` / `music.pause` | `title`, `artist` | Morceau factice imposé ; la vraie musique de l'utilisateur est ignorée pendant tout le tournage |
| `timer.start` | `minutes` | Minuteur des activités en direct (bulle qui descend) |
| `bubble.hover` / `bubble.leave` | `module` (défaut `activities`) | Survol de la bulle : elle s'allonge avec ses commandes |
| `timer.pause` / `timer.stop` | | Pause / arrêt du dernier minuteur |
| `claude.work` | `project`, `file`, `old`, `new`, `prompt` | Événements de hooks de Claude Code : session au travail, diff du fichier |
| `claude.ask` | `command`, `description` | Demande d'autorisation (retenue, comme avec Claude Code) |
| `claude.allow` | `command` | « Autoriser » depuis l'encoche, puis la commande s'exécute |
| `claude.done` | | Fin de tâche (Stop) |
| `expand` / `collapse` | `module` (ex. `agents`) | Ouvre l'encoche sur une page / la referme |
| `fullscreen` | `hidden` | Masquage pendant une vidéo plein écran |
| `lock` / `unlock.screen` | | Mode écran verrouillé (lecteur de musique compris) |
| `end` | | Rien (marque la fin) |

La `description` d'une demande Claude est affichée telle quelle : la traduire dans le scénario `fr`.
Le préfixe (« Runs: » / « Exécute : ») vient de l'app. Seuls les modules Musique, Activités, Agents
(et Claude Code) et Déverrouillage sont actifs pendant le tournage (`DemoSettings`) ; ajouter une action
pour un autre module = un cas dans `DemoDirector.perform` (+ le module dans `DemoSettings.modules`).

## 2. Tourner

1. Demander au propriétaire de **quitter Notchkit** (l'app de /Applications et l'instance Xcode), de
   garder la souris loin du haut de l'écran, et d'accepter « Enregistrement de l'écran » si macOS le
   demande. Ne jamais tuer son instance.
2. Lancer :
   ```sh
   sh .claude/skills/notch-video/scripts/record.sh ~/Documents/Projets/Notchkit-video/tournages/<film> en fr
   ```
   Le script s'arrête si Notchkit tourne encore. Chaque langue produit `notch.mov` (ProRes 4444),
   `notch.webm` (VP9 avec alpha, lu par Chrome) et `timeline.json` (zone filmée, écran en points,
   instants réels des étapes). `DEMO-OK` = réussi ; `DEMO-ERREUR` = message explicite.
3. Dire au propriétaire qu'il peut relancer Notchkit.
4. Contrôler la prise : images clés avec ffmpeg sur un fond coloré
   (`-filter_complex "color=c=0xB08A6A:s=1800x520[bg];[bg][0:v]overlay=shortest=1"`, seek **après** `-i`).

Le build Debug suit la langue du système : chaque langue est passée par `-AppleLanguages`. Le mode
démo travaille sur une copie jetable des réglages (domaine `com.andeolchenaux.notchkit.demo`, effacé à
la fin) : rien ne change chez l'utilisateur.

## 3. Monter dans HyperFrames

1. Créer `Notchkit-video/<film>-reel/` comme `decompte-reel/` : liens `assets -> ../assets` et
   `prise -> ../tournages/<film>`, `hyperframes.json`, `package.json`, `meta.json`, `film.js`.
2. `film.js` (voir `decompte-reel/film.js` et l'en-tête de `nk2-engine.js`) : `stateAt` décrit le
   décor (lumière, écran verrouillé, vidéo plein écran, caméra `s.zoom`), le pointeur et les textes.
   Les états de l'encoche dessinée sont ignorés : la prise la remplace.
3. Générer la page avec l'écran réel de la prise (lire `timeline.json` → `screen`) :
   `"cfg": {"S": 1920 / screen.width, "screen": {"screenW", "screenH", "menubar", "hwW", "hwH", "closedH"}}`
   et `"realNotch": {"src": "prise/<lang>/notch.webm", "width": region.width, "height": region.height, "duration"}`.
   Mesures de l'encoche matérielle : `NSScreen.auxiliaryTopLeftArea/RightArea` (largeur) et
   `safeAreaInsets.top` (hauteur). Ex. écran « Plus d'espace » du MacBook Pro 14 : 1800 × 1169 pt,
   encoche 220 × 38 pt, barre des menus 39 pt.
4. Pointeur : `assets/cursor-arrow.png` (pointeur de macOS 27 exporté de `NSCursor.arrow`, 28 × 40 pt,
   point de clic 5 × 5). Les cibles se mesurent **dans la prise** (taille d'encoche dépliée = réglages de
   l'utilisateur) : extraire l'image, trouver le bouton, convertir en points depuis le centre de la zone
   (`x / scale − width / 2`, `y / scale`). Ex. `allowAt` dans `decompte-reel/make.sh`.
5. `npx --yes hyperframes@0.8.170 check`, puis `snapshot --at …` aux moments clés, puis `render`.
   Pour les cinq films existants (`journee`, `unplan`, `claude`, `decompte`, `notes`, dossiers `<film>-reel/`),
   `python3 assets/render-reel.py [film…]` fait tout : lit l'écran de chaque prise, mesure le bouton
   « Autoriser », écrit la page et rend l'anglais et le français dans `renders/Vidéos 16-9/`
   (`--index en` écrit seulement les pages, pour les captures). Un nouveau film s'y ajoute en complétant
   `FILMS` dans `assets/render-all.py` (titres, sous-titres, textes).
   Les avertissements de contraste sur la barre des menus transparente sont acceptés (fidèles à macOS).

## 4. Miniatures (obligatoires)

Chaque nouvelle vidéo a sa miniature YouTube, dans chaque langue : ajouter le film dans `THUMBS` de
`assets/make-thumbs.py` (instant de la prise à montrer, décor `desktop` / `lock` / `video`, zoom, titre
et sous-titre par langue, `big` pour un grand chiffre, `accent` pour le mot en ambre), puis
`python3 assets/make-thumbs.py <film>`. Sortie : `renders/Miniature vidéos/<English|Français>/`
(1920 × 1080, JPEG). Choisir une image de prise différente de celles des autres films.

## Règles

- Jamais d'encoche redessinée quand une prise existe ; si une prise ne convient pas, on change le
  scénario et on refait la prise.
- Mise en scène (textes, cartes, flou de mouvement, cascades) libre ; l'encoche reste telle quelle.
- Vidéos en 16:9 1920 × 1080, anglais et français, rendus dans `Notchkit-video/renders/`, puis copiés
  dans le dossier Google Drive « NotchKit » (voir la mémoire du projet).
- Le code du mode démo est dans `Notchkit/App/Debug/Demo/` (Debug seulement). Toute modification de
  l'app suit les règles de CLAUDE.md (build, tests, stress test, test du propriétaire avant commit).
