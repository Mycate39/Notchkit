# Notchkit

**Langue : réponds toujours en français** (messages, explications, résumés, questions), quelle que soit la langue du code ou des outils.
Seul ce qui part sur GitHub reste en anglais (voir les règles ci-dessous).

App macOS native qui transforme l'encoche (ou une pilule flottante sur les Mac qui n'en ont pas) en zone vivante :
musique, minuteurs, batterie, météo, calendrier, presse-papiers, étagère de fichiers, activité de Claude Code, téléchargements vidéo.
App de barre des menus (`LSUIElement`), distribuée hors Mac App Store, non sandboxée.

## Stack technique

| Élément | Version |
|---|---|
| Swift | Mode de langage 6.0 (`SWIFT_VERSION: "6.0"`), compilateur 6.2.4 |
| Xcode | 26.3 (17C528) — définir `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (`xcode-select` pointe vers les Command Line Tools) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Observation (`@Observable`) |
| macOS minimum | 14.0 (fond Liquid Glass uniquement sur macOS 26) |
| Génération du projet | XcodeGen 2.44.1 — `project.yml` fait foi, ne jamais modifier `Notchkit.xcodeproj` à la main |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) |
| Dépendances | Sparkle 2.10.0 (SPM, MIT) pour les mises à jour automatiques ; MediaRemoteAdapter (copié dans `ThirdParty/`, BSD 3-Clause) |
| Architectures | Universelle (x86_64 + arm64) ; la machine de dev est un MacBook Pro Intel 2017 sans encoche |
| Signature | Debug : ad hoc (`"-"`). Release : certificat auto-signé gratuit « Notchkit Self-Signed » (trousseau de session, valable jusqu'en 2036), avec Hardened Runtime ; non notarisée |

## Règles impératives

- **Pas de code GPL** (ex. Boring Notch, FaceMac) : inspiration uniquement, jamais de copie.
- **API publiques uniquement**, sauf les API privées déjà acceptées : MediaRemote (via MediaRemoteAdapter) et DisplayServices (luminosité de l'écran intégré). Demander avant d'ajouter toute autre API privée.
- **Pas de HomeKit** (`HMHomeManager` n'est pas disponible sur macOS natif). La domotique, si un jour, passe par l'app Raccourcis (`shortcuts run`).
- **Ne jamais tuer tous les processus Notchkit** (`pkill -x Notchkit`) : le propriétaire fait tourner une instance depuis Xcode. N'arrêter que les instances de test sous `build.noindex/DerivedData/Build/Products`.
- Les instances de test partagent le vrai domaine `UserDefaults` (`com.andeolchenaux.notchkit`) : nettoyer toute clé écrite par un test.
- Ne committer qu'après réussite du build, des tests **et** du stress test. Messages de commit en anglais ; le propriétaire du dépôt est le seul auteur (pas de ligne co-auteur).
- Tout ce qui est sur GitHub est en anglais (README, notes de version, commits). Les commentaires du code sont en français.

## Architecture des dossiers

```
Notchkit/
  App/            Point d'entrée, AppDelegate, menu de la barre des menus, Updater (Sparkle), Debug/ (rendu de captures)
  Core/
    Modules/      Protocole NotchModule, ModuleDescriptor, ModuleManager, ModuleRegistry (liste des modules)
    State/        NotchViewModel (dépliage/repliage, survol, bulles), NotchLayout (toutes les tailles et ressorts), NotchAlert
    Window/       NotchPanel, NotchWindowController, NotchHostingView (zones de survol), ScreenLocator, MenuBarAvoidance
    Layout/       WidgetLayout (pages, tailles), LayoutPresets
    Settings/     AppSettings, NotchAppearance, SettingsStore (décodage tolérant), LaunchAtLogin
    Drop/ Licensing/ Utilities/ (AutomatedRun, Haptics, ObservationTracking)
  Modules/<Nom>/  Un dossier par module : <Nom>Module.swift (+ <Nom>Views.swift, utilitaires)
  UI/             NotchContainerView, NotchShape, NotchStyle (boutons StandBy, barres, curseur, cartes),
                  Glyphs, ModuleIcon, Settings/ (fenêtre et onglets des réglages)
  Resources/      Localizable.xcstrings, InfoPlist.xcstrings, Assets.xcassets (AppIcon), entitlements,
                  Info.plist (généré depuis project.yml)
NotchkitTests/    Suites Swift Testing, un fichier par domaine
ThirdParty/       MediaRemoteAdapter (voir PROVENANCE.md)
scripts/          AppIcon.swift (dessine l'icône), make-dmg.sh, add-to-appcast.sh
appcast.xml       Flux de mises à jour Sparkle (lu par l'app depuis la branche main)
build.noindex/    Sortie de build, ignorée par git ; « .noindex » empêche Spotlight de lister l'app Debug
```

## Conventions de code

- **Modules** : une classe `<Nom>Module` conforme à `NotchModule`, avec un `descriptor` statique (`id` en minuscules comme `"music"`, `"activities"`), `compactPriority`, `compactLeading()/compactTrailing()`, `expandedView()`, `miniView()`, `settingsView()`. L'enregistrer dans `ModuleRegistry.allModules`. Les vues s'appellent `<Nom>ExpandedView`, `<Nom>MiniView`, `<Nom>SettingsView`. Un module sans widget (arrière-plan seulement) met `descriptor.providesWidget = false`. Un module qui doit rester utilisable widget masqué met `descriptor.contextual = true` et implémente `var hasContextualContent` (ex. Étagère, Captures) : il tourne toujours, et s'affiche en dernière page, hors de la disposition, tant qu'il a du contenu (`ModuleManager.contextualIDs`, `layoutPageIDs` pour l'éditeur). Les nouveaux widgets sont masqués par défaut (`defaultEnabled: false`).
- **Tailles de widget** : `WidgetSize` vaut `.mini`, `.small`, `.medium`, `.large` (poids 0,5 / 1 / 1,5 / 2), lu avec `@Environment(\.widgetSize)`. Les vues doivent tenir dans toutes les tailles et toutes les tailles d'encoche (`NotchAppearance.Size`) ; préférer `ViewThatFits` aux cadres fixes.
- **Constantes de mise en page et ressorts** : dans `NotchLayout`, sous forme de fonctions statiques pures et testées. Pas de nombres magiques éparpillés dans les vues.
- **Style** : look StandBy — `.buttonStyle(.standBy(size, active:, circle:))`, `StandByBar`, `StandBySlider`, `StandBy.surface/amber/onAccent`, `.notchCard()`. La couleur d'accent (ambre par défaut) vient de `.tint`.
- **Localisation** : les chaînes sources sont en français (`sourceLanguage: fr`), l'anglais est la langue de développement. Les builds en ligne de commande ne synchronisent **pas** le catalogue : ajouter chaque nouvelle clé avec **à la fois** `en` et `fr` via `scripts/add-strings.py fichier.json` (objet `{ "français": "English" }` ; `--catalog Notchkit/Resources/InfoPlist.xcstrings` pour Info.plist). `LocalizationTests` échoue si les deux tables diffèrent.
- **Exécutions automatisées** : tout ce qui pourrait solliciter l'utilisateur (capture audio, presse-papiers, mises à jour) est ignoré quand `AutomatedRun.isActive`.
- **Tests** : structs Swift Testing ; les noms de test sont des phrases françaises en camelCase (`bullesZoneSepareeDeLEncoche`). Extraire la logique dans des fonctions pures pour la tester sans UI.
- **Réglages** : tout nouveau réglage a une valeur par défaut et un décodage tolérant (`decodeIfPresent` + valeur de repli) pour que les anciens fichiers de réglages se chargent toujours.

## Commandes fréquentes

À lancer depuis la racine du dépôt avec `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
xcodegen generate                                   # après toute modification de project.yml ou ajout/suppression de fichiers

xcodebuild build -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'

xcodebuild test -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'   # chercher « TEST SUCCEEDED »

# Stress test (Debug uniquement) : 200 cycles dépliage/repliage, affiche STRESS-OK (raccourci : scripts/stress.sh)
NOTCHKIT_STRESS=1 build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit \
  -module.claude.port 52799

# Captures (Debug uniquement) : rend l'UI en fichiers PNG, puis quitte
NOTCHKIT_SNAPSHOT=/chemin/vers/dossier build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit

# Forcer une langue : ajouter  -AppleLanguages "(en)"
```

### Publication

1. Augmenter `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, lancer `xcodegen generate`, tester, committer `Version x.y.z`.
2. Build universel :
   `xcodebuild -project Notchkit.xcodeproj -scheme Notchkit -configuration Release -derivedDataPath build.noindex/Release -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO build`
3. `scripts/make-dmg.sh build.noindex/Release/Build/Products/Release/Notchkit.app <dossier-sortie>`
   Le build Release est signé avec « Notchkit Self-Signed » : vérifier `codesign -dvv <app>` (Authority=Notchkit Self-Signed). Ne jamais supprimer ce certificat du trousseau ni le remplacer : macOS ferait perdre aux utilisateurs leurs autorisations (Accessibilité) à la mise à jour suivante. Aucun certificat payant n'est utilisé.
4. `scripts/add-to-appcast.sh <dossier-sortie>/Notchkit-x.y.z.dmg <app> <notes.md>` — signe le DMG avec la clé privée EdDSA stockée dans le trousseau de session (« Private key for signing Sparkle updates » ; ne jamais la supprimer) et ajoute l'entrée en tête de `appcast.xml`. Committer `appcast.xml`.
5. `git push`, `git tag -a vx.y.z`, pousser le tag, `gh release create vx.y.z <dmg> --prerelease --notes-file <notes.md>`.
   L'URL du flux est `https://raw.githubusercontent.com/Mycate39/Notchkit/main/appcast.xml`.

## État (octobre 2026, version 1.0.0 en préparation ; 0.1.9 publiée)

### Fonctionne
- Fenêtre d'encoche sur n'importe quel écran : vraie encoche, encoche simulée ou pilule flottante ; reste en place à travers les Spaces ; se décale à droite pour ne jamais masquer les menus de l'app active (nécessite l'autorisation Accessibilité).
- Activités compactes, mini-encoches, menu empilé, zones de survol séparées, contour style Dynamic Island.
- Encoche dépliée avec pages et widgets en quatre tailles, éditeur de disposition, dispositions prêtes à l'emploi, taille d'encoche personnalisée, contrôles style StandBy, couleur d'accent, fond Liquid Glass (macOS 26). Réglages groupés par catégorie.
- Modules historiques : Musique, Horloge, Batterie, Calendrier, Météo, Claude Code, Étagère + AirDrop, AirPods/Bluetooth, Activités en direct, Presse-papiers, HUD volume/luminosité (aussi Touch Bar et Centre de contrôle), Déverrouillage, Téléchargements vidéo.
- Ajouts de la 1.0 (masqués par défaut) : Captures d'écran (contextuel), Étagère contextuelle avec texte déposé et actions (ZIP, conversion, iCloud Drive), Commutateurs rapides (mode sombre, anti-veille, icônes du bureau, verrouillage clavier), Webcam, Journée, Notes, chronomètre/alarmes/Pomodoro, Rappels (EventKit), Moniteur système (échantillonneur partagé `SystemSampler`, actif seulement si une carte est visible), Dashboard, Temps d'écran et Santé (mesurés localement), Traduction (framework Translation, macOS 15+), Git, GitHub (jeton en Keychain), Ollama, Ancrage des fenêtres.
- Anglais et français ; mises à jour Sparkle ; DMG signé avec le certificat auto-signé.

### Limites connues
- Pas de suivi des téléversements des autres apps (aucune API publique) ; True Tone et notifications avec réponse abandonnés (API privées).
- La lecture AX, le rendu Liquid Glass, l'ancrage des fenêtres et la détection de projet Terminal n'ont été vérifiés que par tests et captures, pas en usage réel sur une vraie encoche.
- L'app n'est pas notarisée (clic droit > Ouvrir la première fois).
- Le module assistant IA est masqué (code conservé dans `Modules/Assistant`).

### Pistes après la 1.0
1. Performance : signposts autour du dépliage/repliage, Instruments (SwiftUI, Animation Hitches, Energy).
2. Widgets tiers déclaratifs (`widget.json` + scripts, rendus avec les composants StandBy).
3. Domotique via l'app Raccourcis.
