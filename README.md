# Notchkit

Transformez l'encoche de votre Mac en un espace vivant : musique, minuteurs, batterie,
météo, calendrier, presse-papiers, étagère de fichiers et suivi de Claude Code, à portée
de souris. Sans encoche ? Notchkit affiche une pastille flottante, ou simule une encoche.

> **Version bêta.** Notchkit est en développement actif : signalez les problèmes dans
> l'onglet *Issues*.

## Fonctionnalités

- **Musique** : morceau en cours (Apple Music, Spotify, et la plupart des lecteurs, y compris
  dans le navigateur), pochette, commandes, barres qui réagissent au son, affichage façon
  Dynamic Island.
- **Volume et luminosité** : indicateur intégré à l'encoche à la place de celui de macOS.
- **AirPods et casques** : animation à la connexion, batterie des appareils Bluetooth.
- **Minuteurs** : durée au choix, à la manière de l'iPhone.
- **Batterie, horloge, météo** (Open-Meteo) et **calendrier**.
- **Presse-papiers** : historique recherchable, éléments épinglés.
- **Étagère et AirDrop** : glissez des fichiers sur l'encoche pour les garder ou les envoyer.
- **Claude Code** : ce que fait Claude en direct, ses messages, l'utilisation restante,
  et la possibilité de lui écrire depuis l'encoche.
- **Téléchargement de vidéos** (avec yt-dlp, installé à la demande).
- **Retour à l'app précédente**, animations de déverrouillage, retour haptique du trackpad.
- **Personnalisation** : widgets en plusieurs tailles, pages, dispositions prêtes à
  l'emploi, taille de l'encoche, animations, couleurs, fond (dont Liquid Glass sur macOS 26).

## Installation

1. Téléchargez `Notchkit-x.y.z.zip` depuis la page [Releases](../../releases) et
   décompressez-le.
2. Glissez **Notchkit.app** dans le dossier **Applications**.
3. Premier lancement : Notchkit n'est pas encore notarisé par Apple, macOS le bloque donc
   une première fois. Faites **clic droit > Ouvrir** sur l'app, ou ouvrez
   **Réglages Système > Confidentialité et sécurité** et cliquez sur **Ouvrir quand même**.

Notchkit vit dans la barre des menus (pas d'icône dans le Dock). Les réglages s'ouvrent
depuis cette icône ou depuis la roue dentée de l'encoche.

### Configuration requise

- macOS 14 Sonoma ou plus récent (Liquid Glass : macOS 26).
- Mac Apple Silicon ou Intel, avec ou sans encoche, un ou plusieurs écrans.

### Autorisations

Notchkit ne demande une autorisation que lorsqu'une fonction en a besoin : Accessibilité
(touches de volume et luminosité), Calendriers, Localisation (météo), enregistrement de
l'audio du système (barres réactives à la musique). Rien n'est envoyé sur Internet, à
part les requêtes météo (Open-Meteo) et le téléchargement de yt-dlp si vous l'installez.

## Compiler depuis les sources

Prérequis : Xcode 26 et [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Notchkit.xcodeproj
```

## Remarques

Certaines fonctions s'appuient sur des interfaces non officielles de macOS (lecture du
morceau en cours de n'importe quelle app, luminosité de l'écran intégré). Une mise à jour
de macOS peut les interrompre ; Notchkit se replie alors sur les interfaces publiques.

## Licence

© 2026 Andéol Chenaux. Tous droits réservés : le code est publié pour consultation
uniquement (voir [LICENSE](LICENSE)). L'application est gratuite pour un usage personnel.
Composants tiers : [MediaRemoteAdapter](ThirdParty/MediaRemoteAdapter) (BSD 3 clauses).
