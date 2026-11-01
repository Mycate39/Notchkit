# Filmer l'encoche en verre (Liquid Glass)

À lire avant chaque tournage où l'encoche a le fond « Verre » (`"background": "glass"`).
Le verre est le style par défaut de Notchkit 3.0 : c'est presque toujours le cas.

## Pourquoi la prise peut sortir floue

Le verre n'est pas une image fixe que l'app dessine. C'est macOS qui le calcule à chaque image, à partir
de ce qui se trouve réellement derrière la fenêtre, sur l'écran. Deux conditions doivent être réunies :

1. **Il faut un vrai fond derrière l'encoche au moment du tournage.** Le tournage par défaut filme les
   fenêtres de Notchkit seules, sur fond transparent. Le verre n'a alors rien à réfracter dans la
   vidéo : il ressort flou ou gris. Il ne réfractera jamais le décor HyperFrames ajouté au montage.
2. **L'encoche doit être la fenêtre clé.** Le Liquid Glass n'a son rendu net que dans la fenêtre clé ;
   sinon macOS le dessine en flou terne. Depuis le commit `fc46acd` (30/10/2026, beta 6), l'encoche
   devient fenêtre clé dès qu'elle s'ouvre (`NotchWindowController.updateKeyStatus`). Un build Debug plus
   ancien filme donc un verre flou.

Ne jamais remplacer le verre par un verre imité en CSS au montage : le propriétaire veut le vrai verre
de macOS, et la règle de la skill (encoche jamais redessinée) s'applique.

## Marche à suivre

1. **Build Debug à jour** depuis la racine du dépôt (`git pull`, puis la commande `xcodebuild build` de
   CLAUDE.md). `record.sh` lance ce build-là.
2. **Fond filmé** : dans le scénario, `"setup": { "background": "glass", "backdrop": true, … }`.
   Le fond d'écran de macOS est alors filmé derrière l'encoche et la vidéo est opaque
   (`DemoRecorder`, `config.shouldBeOpaque`). Exemples : `tournages/verre/` et `tournages/nouveautes/`.
3. **Choisir le décor avant de tourner** : avec `backdrop`, le décor visible derrière l'encoche est le
   fond d'écran du Mac, pas celui de HyperFrames. Demander au propriétaire de mettre en fond d'écran
   l'image voulue (celle du décor du film). Ce décor ne peut plus être changé au montage. Le reste de
   l'écran filmé (icônes, barre des menus, fenêtres des autres apps) est exclu de la prise.
4. **Au montage**, la prise opaque se pose à sa place exacte sur le même décor, pour que le bord de la
   zone filmée ne se voie pas. Les textes, cartes et effets se posent par-dessus.
5. **Tourner** normalement (section « 2. Tourner » de `SKILL.md` : Notchkit quitté, souris loin du haut
   de l'écran).

## Contrôler la prise

Extraire quelques images où l'encoche est ouverte (seek **après** `-i`) :

```sh
ffmpeg -i notch.mov -ss 12 -frames:v 1 controle.png
```

- Verre net, couleurs du fond visibles à travers, reflets sur les bords : bon.
- Gris uniforme ou flou terne avec `backdrop: true` : build trop ancien (point 2), ou l'encoche n'était
  pas fenêtre clé. Vérifier que le build contient `fc46acd` (`git log --oneline | grep -i glass`), puis
  refaire la prise.
- Flou seulement sans `backdrop` : normal (point 1). Ajouter `backdrop: true`.

## Fond noir

Une scène en fond Noir (`"background": "black"`) n'a pas de verre : elle peut garder le fond
transparent (sans `backdrop`) et se poser sur n'importe quel décor au montage.
