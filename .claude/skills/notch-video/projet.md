# Vidéos de présentation de Notchkit

Où sont les vidéos, comment elles sont faites et où elles vont. La méthode de tournage est dans
`SKILL.md` ; le tournage en verre dans `verre.md` (à relire avant chaque vidéo).

## Projet

- Projet HyperFrames hors du dépôt : `~/Documents/Projets/Notchkit-video`.
  - 16:9 de 45 s à la racine, 9:16 de 30 s dans `vertical/`.
  - Textes `en.json` / `fr.json`, design calqué sur le code de l'app dans `design.md`.
  - Rendus dans `renders/`.
- Tournage avec la vraie encoche (build Debug à jour, Notchkit quitté) :
  `sh .claude/skills/notch-video/scripts/record.sh ~/Documents/Projets/Notchkit-video/tournages/<film> en fr`
- Un dossier `<film>-reel/` par film, prises dans `tournages/`, rendus par `assets/render-reel.py`.

## Films

- **Vidéos de la 2.0** (refaites le 26/10/2026 avec la vraie encoche filmée par le mode démo) : cinq films
  de 30 s en 16:9, anglais et français, dans `renders/Vidéos 16-9/`. Logo, bannière et photo de profil
  YouTube dans `renders/Logo/` ; miniatures dans `renders/Miniature vidéos/`.
- **Films « utilisation normale »** (style premium, 16:9 et vertical) :
  - code : `usage/make.py` et `usage/premium.js` ;
  - scénarios : `tournages/make-scenarios-usage.py` ;
  - rendus : `renders/Utilisation/`.
  - Premier film : « Une journée ordinaire » (02/11/2026, fond Verre filmé avec le vrai fond d'écran).
- Le README montre « Notchkit 3.0 — The Glass design » (depuis le 02/11/2026).

## Musique

- `assets/music/danker.mp3` jusqu'au 31/10/2026.
- Depuis le 01/11/2026, un morceau différent par vidéo, proposé au propriétaire (souvent de la French house
  dans l'esprit de Daft Punk). Il faut que sa licence permette un usage commercial sur YouTube et les
  réseaux ; Daft Punk lui-même demanderait une licence.
- Registre des morceaux proposés et retenus, avec leur licence : `assets/music/MUSIQUES.md`.

## Diffusion

- Chaque nouvelle vidéo va aussi dans le dossier Google Drive « NotchKit ».
- Vidéo du README : lien `github.com/user-attachments/assets/…`. Pour l'obtenir, téléverser le fichier
  (moins de 10 Mo, sinon réencoder en deux passes) dans l'éditeur web du README sur GitHub, sans
  enregistrer, puis remplacer le lien dans le README local.
