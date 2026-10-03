# MediaRemoteAdapter (code tiers)

- Origine : https://github.com/ungive/mediaremote-adapter
- Commit : 29718252613a5b0e210bdc64de0bd944ab379706 (30 septembre 2026)
- Licence : BSD 3 clauses (voir `LICENSE.txt`), compatible avec un usage commercial.
- Contenu repris : `bin/mediaremote-adapter.pl`, `include/`, `src/` (dans `src/test`, seul `NowPlayingTest.h` est gardé car `test.m` l'inclut). Aucune modification.

## Rôle

Permet de lire le morceau en cours (« À l'écoute » de macOS) et de piloter la lecture,
quelle que soit l'app (Deezer, navigateurs…), via le framework privé MediaRemote.
Depuis macOS 15.4, seul un binaire système autorisé (`/usr/bin/perl`) peut l'utiliser :
le script charge ce framework dans Perl et écrit les mises à jour en JSON sur sa sortie.

⚠️ API privée : Apple peut casser ce mécanisme à toute mise à jour de macOS.
Notchkit se replie alors automatiquement sur Music et Spotify (API publiques).

## Mise à jour

Remplacer `bin/`, `include/` et `src/` par la nouvelle version (dans `src/test`, ne garder que `NowPlayingTest.h`),
mettre à jour le commit ci-dessus, puis `xcodegen generate`.
