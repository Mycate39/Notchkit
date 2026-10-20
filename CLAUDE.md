# Notchkit

**Langue : réponds toujours en français** (messages, explications, résumés, questions), quelle que soit la langue du code ou des outils.
Seul ce qui part sur GitHub reste en anglais (voir les règles ci-dessous).

App macOS native qui transforme l'encoche (ou une pilule flottante sur les Mac qui n'en ont pas) en zone vivante :
musique, minuteurs, batterie, météo, calendrier, presse-papiers, étagère de fichiers, activité de Claude Code, téléchargements vidéo, conversion de fichiers.
App de barre des menus (`LSUIElement`), distribuée hors Mac App Store, non sandboxée.

## Stack technique

| Élément | Version |
|---|---|
| Swift | Mode de langage 6.0 (`SWIFT_VERSION: "6.0"`), compilateur 6.2.4 |
| Xcode | 27.1 (27A9275) — définir `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` par sécurité ; XcodeGen et `gh` installés via Homebrew (`/opt/homebrew/bin`) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Observation (`@Observable`) |
| macOS minimum | 14.0 (fond Liquid Glass uniquement sur macOS 26) |
| Génération du projet | XcodeGen 2.44.1 — `project.yml` fait foi, ne jamais modifier `Notchkit.xcodeproj` à la main |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) |
| Dépendances | Sparkle 2.10.0 (SPM, MIT) pour les mises à jour automatiques ; MediaRemoteAdapter (copié dans `ThirdParty/`, BSD 3-Clause) |
| Architectures | Universelle (x86_64 + arm64) ; la machine de dev est un MacBook Pro 14" M1 Pro avec une vraie encoche (MacBookPro18,3 : encoche 185 × 32 pt, barre des menus 33 pt) |
| Signature | Debug : ad hoc (`"-"`). Release : certificat auto-signé gratuit « Notchkit Self-Signed » (trousseau de session, recréé le 17/10/2026 après la perte de l'ancien Mac, valable jusqu'en 2036), avec Hardened Runtime et `disable-library-validation` (sans identifiant d'équipe, sinon Sparkle ne se charge pas et l'app plante au lancement) ; non notarisée |

## Règles impératives

- **Pas de code GPL** (ex. Boring Notch, FaceMac) : inspiration uniquement, jamais de copie.
- **API publiques uniquement**, sauf les API privées déjà acceptées : MediaRemote (via MediaRemoteAdapter), DisplayServices (luminosité de l'écran intégré) et SkyLight (`LockScreenSpace` : espace de niveau supérieur qui garde l'encoche au-dessus de tous les bureaux, du plein écran et de l'écran verrouillé). Demander avant d'ajouter toute autre API privée.
- **Glisser-déposer** : le serveur de fenêtres ne livre pas le glisser à une fenêtre de l'espace SkyLight, qui passerait aussi devant l'image du fichier glissé. `DropCatcher` (fenêtre invisible du bureau ordinaire, même cadre que l'encoche) reçoit le glisser et héberge le contenu de l'encoche le temps du glisser. Déplacer la fenêtre vers le bureau courant (`SLSGetActiveSpace`) n'a aucun effet visible : ne pas réessayer.
- **Pas de HomeKit** (`HMHomeManager` n'est pas disponible sur macOS natif). La domotique, si un jour, passe par l'app Raccourcis (`shortcuts run`).
- **Ne jamais lancer l'app dans Xcode à la place du propriétaire** (pas d'AppleScript sur Xcode) : il lance lui-même avec ⌘R et teste. Pour un changement visible en usage réel (survol, bureaux, écran verrouillé), lui demander de tester avant de committer.
- **Ne jamais tuer tous les processus Notchkit** (`pkill -x Notchkit`) : le propriétaire fait tourner une instance depuis Xcode. N'arrêter que les instances de test sous `build.noindex/DerivedData/Build/Products`.
- Les instances de test partagent le vrai domaine `UserDefaults` (`com.andeolchenaux.notchkit`) : nettoyer toute clé écrite par un test.
- Ne committer qu'après réussite du build, des tests **et** du stress test. Messages de commit en anglais ; le propriétaire du dépôt est le seul auteur (pas de ligne co-auteur).
- Tout ce qui est sur GitHub est en anglais (README, notes de version, commits). Les commentaires du code sont en français.

## Architecture des dossiers

```
Notchkit/
  App/            Point d'entrée, AppDelegate, menu de la barre des menus, Updater (Sparkle), Debug/ (rendu de captures),
                  Onboarding/ (tutoriel d'accueil : étapes, démonstrations animées, fenêtre)
  Core/
    Modules/      Protocole NotchModule, ModuleDescriptor, ModuleManager, ModuleRegistry (liste des modules)
    State/        NotchViewModel (dépliage/repliage, survol, bulles), NotchLayout (toutes les tailles et ressorts), NotchAlert
    Window/       NotchPanel, NotchWindowController, NotchHostingView (zones de survol), ScreenLocator, MenuBarAvoidance,
                  LockScreenSpace (espace SkyLight au-dessus des bureaux), DropCatcher (réception du glisser-déposer)
    Permissions/  PermissionCenter (état et demande des 8 autorisations macOS)
    Layout/       WidgetLayout (pages, tailles), LayoutPresets
    Settings/     AppSettings, NotchAppearance, SettingsStore (décodage tolérant), LaunchAtLogin
    Drop/ Licensing/ Utilities/ (AutomatedRun, Haptics, ObservationTracking)
  Modules/<Nom>/  Un dossier par module : <Nom>Module.swift (+ <Nom>Views.swift, utilitaires)
  UI/             NotchContainerView, NotchShape, NotchStyle (boutons StandBy, barres, curseur Liquid Glass, cartes),
                  Glyphs, ModuleIcon, FlowLayout, Mascot/ (33 mascottes, mouvements, réactions au clic, sons synthétisés),
                  Settings/ (fenêtre des réglages : Général, Apparence, Disposition, Widgets = liste de tous les modules
                  avec page de détail et bouton retour, Autorisations, À propos)
  Resources/      Localizable.xcstrings, InfoPlist.xcstrings, Assets.xcassets (AppIcon), entitlements,
                  Info.plist (généré depuis project.yml)
NotchkitTests/    Suites Swift Testing, un fichier par domaine
ThirdParty/       MediaRemoteAdapter (voir PROVENANCE.md)
scripts/          AppIcon.swift (dessine l'icône), make-dmg.sh, add-to-appcast.sh
appcast.xml       Flux de mises à jour Sparkle (lu par l'app depuis la branche main)
build.noindex/    Sortie de build, ignorée par git ; « .noindex » empêche Spotlight de lister l'app Debug
```

## Où trouver quoi

Carte pour aller droit au bon fichier (chercher ensuite le symbole avec `grep -n`). Un changement d'apparence ou de taille passe presque toujours par `NotchLayout` (valeurs) et `NotchContainerView` (rendu).

**Démarrage et câblage**
- `App/AppDelegate.swift` : crée `SettingsStore`, `ModuleManager`, `NotchViewModel` et `NotchWindowController`, puis les relie (alertes, réglages, maintien ouvert, mode jeu, zones de dépôt et ce que fait chaque dépôt). Lance aussi les modes `NOTCHKIT_STRESS` / `NOTCHKIT_SNAPSHOT`.
- `App/MenuBarContent.swift` : menu de l'icône de la barre des menus (dont la bascule du mode jeu et le menu Débogage).

**Encoche : état, tailles, rendu**
- `Core/State/NotchViewModel.swift` : dépliage/repliage (`expand`, `collapse`, `expand(showing:)`), survol (`hoverChanged`, délais), bulles (`bubbleModules`, `hoverBubble`, menu empilé, commandes `hoverBubbleControls`), largeur repliée (`compactSideWidth`), tailles de la forme et de la fenêtre (`shapeSize`, `panelSize`), alertes (`present`), glisser-déposer, mode jeu (`setQuiet`), écran verrouillé (`setScreenLocked`).
- `Core/State/NotchLayout.swift` : toutes les constantes et fonctions de taille, d'espacement et d'animation (largeur des activités `activitySideWidth`, bulles, ombres, ressort `spring`, curseurs, `shapeSize`, pagination).
- `UI/NotchContainerView.swift` : le rendu. `CompactNotchView` (activité repliée gauche/droite, `compactRow`, île), `CompactBubbles` (bulles, pile, bulle allongée avec commandes), `ExpandedNotchView` (en-tête, onglets de pages, indicateur, pages de widgets), `PageView` (cartes), `WidgetContextMenu` (clic droit sur un widget).
- `Core/State/NotchAlert.swift` : alerte temporaire (gauche/droite, ou contenu agrandi sous l'encoche avec `expandedSize`).
- `UI/NotchShape.swift` : la forme (congés, coins). `Core/Settings/NotchAppearance.swift` : `notchBackground` (noir, couleur, Liquid Glass), tailles d'encoche dépliée, couleur d'accent (`accentColor`, `onAccentColor`).
- `UI/NotchStyle.swift` : composants du style StandBy (boutons `.standBy`, `StandByBar`, curseur `StandBySlider`/`SliderTrack`/`SliderKnob`, `.notchCard()`, couleurs `StandBy.*`, `\.onAccent`, `\.sliderTint`).

**Fenêtre et système**
- `Core/Window/NotchWindowController.swift` : la fenêtre (taille animée, écran choisi, bureaux, verrouillage, évitement des menus, diagnostic). `NotchPanel` (niveau de fenêtre), `NotchHostingView` (souris et glisser-déposer reçus par AppKit), `DropCatcher`, `LockScreenSpace` (SkyLight), `ScreenLocator` (quel écran, encoche réelle ou non), `MenuBarAvoidance`.

**Modules**
- `Core/Modules/NotchModule.swift` : le protocole (`compactLeading/Trailing`, `compactPriority`, `bubblePriority`, `bubbleControls`, `expandedView`, `miniView`, `settingsView`, `widgetModuleID`) et `ModuleContext` (services offerts aux modules : alertes, `showModule`, `holdExpanded`, `otherModule`, `setQuietMode`…). Ajouter un service = un champ ici + son branchement dans `ModuleManager.makeContext` et l'AppDelegate.
- `Core/Modules/ModuleDescriptor.swift` : identité et drapeaux d'un module. `ModuleRegistry.swift` : la liste des modules. `ModuleManager.swift` : activation, activité principale (`compactModule`) et bulles (`secondaryCompactModules`), pages et tailles des widgets.
- `Modules/<Nom>/` : un dossier par module. Les plus gros : Music (sources MediaRemote et apps scriptables dans `Sources/`, égaliseur et analyse audio dans `Spectrum/`), Claude (serveur de hooks, installation, suivi des sessions) + Agents (page pleine), SystemHUD (touches, volume/luminosité, centre du son `AudioCenter`), LiveActivities (minuteurs, téléchargements), VideoDownload (yt-dlp), Converter.

**Réglages, disposition, divers**
- `Core/Settings/AppSettings.swift` : réglages généraux (délais de survol, écran, haptique, mascotte…) ; un réglage propre à un module vit plutôt dans le module (`UserDefaults`, clé `module.<id>.<nom>`).
- `UI/Settings/` : `SettingsView.swift` (fenêtre, onglets `SettingsTab`, Général, liste des widgets et page de détail, À propos), `AppearanceSettingsView`, `LayoutSettingsView` (éditeur de disposition), `PermissionsSettingsView`.
- `Core/Layout/WidgetLayout.swift` : tailles de widget et calcul des pages ; `LayoutPresets` : dispositions prêtes à l'emploi.
- `Core/Permissions/PermissionCenter.swift` : les autorisations (ajouter un cas = titre, usage, icône, couleur, ancre des Réglages Système, état, demande).
- `App/Onboarding/` : étapes du tutoriel (`OnboardingStep`), fenêtre et démonstrations animées.
- `UI/Mascot/` : dessins des mascottes (`MascotDesigns`, `RobotMascots`, `FaceIDMascots`), mouvements et réactions (`MascotMotion`), sons (`MascotSounds`).
- `Core/Utilities/Haptics.swift` : vibrations du trackpad (`Haptics.play(.tap/.step/.snap)`).
- `App/Debug/` : captures (`SnapshotRenderer`, `PromoSnapshots`) et rendu vidéo des mascottes.
- Tests : `NotchkitTests/<Domaine>Tests.swift` ; la mise en page de l'encoche et les bulles sont dans `ModuleManagerTests` (`NotchLayoutTests`) et `BubbleControlsTests`.

## Conventions de code

- **Modules** : une classe `<Nom>Module` conforme à `NotchModule`, avec un `descriptor` statique (`id` en minuscules comme `"music"`, `"activities"`), `compactPriority`, `compactLeading()/compactTrailing()`, `expandedView()`, `miniView()`, `settingsView()`. L'enregistrer dans `ModuleRegistry.allModules`. Les vues s'appellent `<Nom>ExpandedView`, `<Nom>MiniView`, `<Nom>SettingsView`. Un module sans widget (arrière-plan seulement) met `descriptor.providesWidget = false`. Un module qui doit rester utilisable widget masqué met `descriptor.contextual = true` et implémente `var hasContextualContent` (ex. Étagère, Captures) : il tourne toujours, et s'affiche en dernière page, hors de la disposition, tant qu'il a du contenu (`ModuleManager.contextualIDs`, `layoutPageIDs` pour l'éditeur). Un module dont les animations viennent du système (branchement du chargeur, AirPods, touches de volume) met `descriptor.backgroundEvents = true` : widget désactivé, il tourne quand même pour ses alertes, sans carte ni activité repliée (`ModuleManager.backgroundIDs`) ; c'est le cas de Batterie, AirPods et HUD. Les nouveaux widgets sont masqués par défaut (`defaultEnabled: false`).
- **Tailles de widget** : `WidgetSize` vaut `.mini`, `.small`, `.medium`, `.large` (poids 0,5 / 1 / 1,5 / 2), lu avec `@Environment(\.widgetSize)`. Les vues doivent tenir dans toutes les tailles et toutes les tailles d'encoche (`NotchAppearance.Size`) ; préférer `ViewThatFits` aux cadres fixes.
- **Constantes de mise en page et ressorts** : dans `NotchLayout`, sous forme de fonctions statiques pures et testées. Pas de nombres magiques éparpillés dans les vues.
- **Style** : look StandBy — `.buttonStyle(.standBy(size, active:, circle:))`, `StandByBar`, `StandBySlider`, `StandBy.surface/amber/defaultAccent`, `.notchCard()`. La couleur d'accent (bleu de macOS par défaut, `StandBy.defaultAccent`) vient de `.tint` ; le texte posé dessus vient de `@Environment(\.onAccent)` (blanc sur une couleur foncée, noir chaud sur une claire). L'ambre reste pour les états qui demandent l'attention.
- **Localisation** : les chaînes sources sont en français (`sourceLanguage: fr`), l'anglais est la langue de développement. Les builds en ligne de commande ne synchronisent **pas** le catalogue : ajouter chaque nouvelle clé avec **à la fois** `en` et `fr` via `scripts/add-strings.py fichier.json` (objet `{ "français": "English" }` ; `--catalog Notchkit/Resources/InfoPlist.xcstrings` pour Info.plist). `LocalizationTests` échoue si les deux tables diffèrent.
- **Exécutions automatisées** : tout ce qui pourrait solliciter l'utilisateur (capture audio, presse-papiers, mises à jour) est ignoré quand `AutomatedRun.isActive`.
- **Tests** : structs Swift Testing ; les noms de test sont des phrases françaises en camelCase (`bullesZoneSepareeDeLEncoche`). Extraire la logique dans des fonctions pures pour la tester sans UI.
- **Écran verrouillé** : `NotchViewModel.isScreenLocked` ; seules les activités repliées restent visibles, sans aucune interaction (pas d'ouverture, de gonflement au survol, de menu des bulles, de dépôt ni de clic). Toute nouvelle interaction doit respecter ce verrou.
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

# Captures (Debug uniquement) : rend l'UI en fichiers PNG, puis quitte. Les vues AppKit (formulaires,
# interrupteurs, égaliseur) passent par `saveWindow` (fenêtre hors écran) : reglages-widgets.png, egaliseur.png…
NOTCHKIT_SNAPSHOT=/chemin/vers/dossier build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit

# Journal de l'espace SkyLight et du verrouillage (/usr/bin/log : sous zsh, « log » est une commande interne)
/usr/bin/log show --last 10m --predicate 'subsystem == "com.andeolchenaux.notchkit" AND category == "espace"'

# Forcer une langue : ajouter  -AppleLanguages "(en)"
```

### Publication

1. Augmenter `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, lancer `xcodegen generate`, tester, committer `Version x.y.z`.
   Xcode réécrit parfois les catalogues `.xcstrings` (mise en forme, `extractionState`, commentaires). Avant de committer un tel changement, vérifier qu'aucune traduction n'est ajoutée, retirée ou modifiée ; s'il ne s'agit que de métadonnées, le committer à part (« Sync string catalogs with Xcode »). Pendant une publication, les mettre de côté (`git stash push -- Notchkit/Resources/*.xcstrings`, puis `git stash pop`).
2. Build universel :
   `xcodebuild -project Notchkit.xcodeproj -scheme Notchkit -configuration Release -derivedDataPath build.noindex/Release -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO build`
3. `scripts/make-dmg.sh build.noindex/Release/Build/Products/Release/Notchkit.app <dossier-sortie>`
   Le build Release est signé avec « Notchkit Self-Signed » : vérifier `codesign -dvv <app>` (Authority=Notchkit Self-Signed). Ne jamais supprimer ce certificat du trousseau ni le remplacer : macOS ferait perdre aux utilisateurs leurs autorisations (Accessibilité) à la mise à jour suivante. Il doit exister une sauvegarde chiffrée (export .p12) hors de ce Mac : l'ancien certificat a été perdu avec l'ancien Mac. Aucun certificat payant n'est utilisé.
   **Avant de publier, lancer l'app Release** (`<app>/Contents/MacOS/Notchkit`) et vérifier qu'elle tourne encore après quelques secondes : les tests et le stress test passent par le build Debug (signé ad hoc) et ne détectent pas un échec de chargement propre au build Release (1.0.1 et 1.0.2 ont été publiées dans cet état).
4. `scripts/add-to-appcast.sh <dossier-sortie>/Notchkit-x.y.z.dmg <app> <notes.md>` — signe le DMG avec la clé privée EdDSA stockée dans le trousseau de session (« Private key for signing Sparkle updates » ; ne jamais la supprimer, sauvegarde via `generate_keys -x`) et ajoute l'entrée en tête de `appcast.xml`. La clé a été remplacée au build 12 (1.0.1) : le script marque chaque entrée comme informative (`sparkle:informationalUpdate`, `belowVersion` 12) pour que les builds 11 et antérieurs affichent un lien vers la release au lieu d'échouer. Committer `appcast.xml` seulement après la création de la release GitHub.
5. `git push`, `git tag -a vx.y.z`, pousser le tag, `gh release create vx.y.z <dmg> --latest --notes-file <notes.md>` (les versions 1.x ne sont plus des préversions), puis pousser `appcast.xml`.
   L'URL du flux est `https://raw.githubusercontent.com/Mycate39/Notchkit/main/appcast.xml`.

**Bêta** : même procédure, avec `MARKETING_VERSION` `x.y.z-beta.N` (le build augmente normalement), tag `vx.y.z-beta.N`, `gh release create … --prerelease --latest=false`, et **sans** étape `appcast.xml` : les utilisateurs actuels ne la reçoivent pas automatiquement.

## État (20 octobre 2026 : 1.0.6 publiée, 2.0.0 beta 2 en préversion)

### Fonctionne
- Fenêtre d'encoche sur n'importe quel écran : vraie encoche, encoche simulée ou pilule flottante ; reste en place à travers les Spaces ; se décale à droite pour ne jamais masquer les menus de l'app active (nécessite l'autorisation Accessibilité).
- Activités compactes, mini-encoches, menu empilé, zones de survol séparées, contour style Dynamic Island. Une bulle qui a des commandes (`bubbleControls()`, ex. la musique) s'allonge vers la droite au survol au lieu d'ouvrir l'encoche ; `bubblePriority` garde la bulle de la musique en pause.
- Encoche dépliée avec pages et widgets en quatre tailles, éditeur de disposition, dispositions prêtes à l'emploi, taille d'encoche personnalisée, contrôles style StandBy, couleur d'accent, fond Liquid Glass (macOS 26). Réglages groupés par catégorie.
- Modules historiques : Musique, Horloge, Batterie, Calendrier, Météo, Claude Code, Étagère + AirDrop, AirPods/Bluetooth, Activités en direct, Presse-papiers, HUD volume/luminosité (aussi Touch Bar et Centre de contrôle), Déverrouillage, Téléchargements vidéo.
- Ajouts de la 1.0 (masqués par défaut) : Captures d'écran (contextuel), Étagère contextuelle avec texte déposé et actions (ZIP, conversion, iCloud Drive), Commutateurs rapides (mode sombre, anti-veille, icônes du bureau, verrouillage clavier), Webcam, Journée, Notes, chronomètre/alarmes/Pomodoro, Rappels (EventKit), Moniteur système (échantillonneur partagé `SystemSampler`, actif seulement si une carte est visible), Dashboard, Temps d'écran et Santé (mesurés localement), Traduction (framework Translation, macOS 15+), Ancrage des fenêtres.
- Anglais et français ; mises à jour Sparkle ; DMG signé avec le certificat auto-signé.

### Version 2.0.0 (en cours)
- Publié dans la beta 1 (`v2.0.0-beta.1`, préversion GitHub, hors appcast) : tutoriel d'accueil au premier lancement (rejouable par « Revoir le tutoriel… » ; `AppSettings.onboardingCompleted`, vrai par défaut pour un ancien fichier de réglages), onglet Widgets unique dans les réglages, indicateur de pages visible seulement pendant un balayage, engrenage sans pastille.
- Fait depuis : barres de l'égaliseur arrondies aux deux bouts (animation de hauteur, plus d'échelle), indicateur de pages animé (pastille qui glisse avec `NotchLayout.pageIndicatorSpring`, icônes qui se précisent, apparition en fondu).
- Fait depuis la beta 1 : encoche gardée en permanence dans l'espace SkyLight de niveau 400 (niveaux connus : 100 assistant de configuration, 300 écran verrouillé, 400 centre de notifications sur l'écran verrouillé ; l'ancien niveau 100 restait sous l'écran verrouillé). Elle s'affiche à l'écran verrouillé (vérifié le 18/10/2026 sur macOS 27) et ne doit plus disparaître ni se redimensionner en changeant de bureau ; au verrouillage, la fenêtre passe aussi au-dessus du bouclier (`NotchPanel.lockedLevel`) avec `canBecomeVisibleWithoutLogin`. Écran verrouillé sans interaction. Égaliseur : animations relancées au changement de bureau, retour à l'animation simple si le flux audio s'interrompt, hauteurs en direct posées sans animation.
- Fait depuis (19/10/2026) :
  - Page Agents (`Modules/Agents`, pleine page, `fullPage`) inspirée de coucou : mascotte choisie parmi 33 (Réglages > Apparence, aussi dans l'encoche repliée), étapes de Claude Code, éditeur et terminal en direct, autorisations et questions de Claude Code répondues depuis l'encoche (hooks version 4 ; pendant une question, le panneau prend toute la page). Widgets Claude Code et Ollama retirés ; Claude Code n'est plus un module à part dans les réglages : c'est le moteur de la page Agents (`companionOf: "agents"`, activé avec elle), dont seule l'intégration (hooks) reste réglable, dans la page du widget Agents. Délai pour répondre depuis l'encoche supprimé. Widgets Git et GitHub, et services Vercel / Stripe, supprimés (19/10/2026). La discussion avec la mascotte (Apple Intelligence ou Claude, avec outils façon Siri) a été essayée puis abandonnée le 19/10/2026 : trop limitée face au nouveau Siri, ne pas la refaire.
  - Mascotte interactive : réactions au clic, sons synthétisés (`MascotSounds`, aucun fichier, transposés d'une quarte vers le grave), réglables dans Apparence.
  - Publié dans la beta 2 (`v2.0.0-beta.2`, 19/10/2026) : tous les points de cette liste, sauf le compteur d'images par seconde du mode jeu et les commandes de la bulle de la musique (20/10/2026).
  - Mode jeu (`Modules/GameMode`) : encoche discrète et images par seconde seulement (`FrameRateMeter` : ScreenCaptureKit compte les images complètes de l'app au premier plan, autorisation Enregistrement de l'écran). S'active comme le mode jeu de macOS (jeu en plein écran au premier plan, `FullScreenDetector`), ou à la main.
  - Centre du son dans le panneau du volume : sortie, micro, apps qui jouent (repli sur l'app « À l'écoute », les navigateurs ne signalant pas toujours leur sortie), volume par app par interception Core Audio (macOS 14.2+).
  - Onglet Autorisations et synthèse dans le tutoriel ; curseurs Liquid Glass (macOS 26+) ; zones cliquables agrandies ; boutons natifs dans les réglages.
  - Convertisseur (`Modules/Converter`, widget temporaire) : images, audio (afconvert), vidéo (AVFoundation, GIF), documents (CoreText) et PDF ; zones de dépôt toujours proposées : étagère, Convertir, AirDrop ; dépôt direct sur sa page ouverte.
- Reste à faire avant la 2.0.0 : mentionner le tutoriel et les nouveautés dans le README, publier en version finale (avec appcast).

### Vidéo de présentation
- Projet HyperFrames hors du dépôt : `~/Documents/Projets/Notchkit-video` (16:9 de 45 s à la racine, 9:16 de 30 s dans `vertical/`, textes `en.json` / `fr.json`, design calqué sur le code de l'app dans `design.md`). Rendus dans `renders/`.
- Musique de toutes les vidéos : `assets/music/danker.mp3` ; extraits calés pour que la montée à 24 s tombe à l'ouverture de l'encoche.
- Chaque nouvelle vidéo va aussi dans le dossier Google Drive « NotchKit ».
- La vidéo du README est un lien `github.com/user-attachments/assets/…` : on l'obtient en téléversant le fichier dans l'éditeur web du README sur GitHub (sans y enregistrer), puis on remplace le lien dans le README local.

### Limites connues
- Pas de suivi des téléversements des autres apps (aucune API publique) ; True Tone et notifications avec réponse abandonnés (API privées).
- La lecture AX, le rendu Liquid Glass, l'ancrage des fenêtres et la détection de projet Terminal n'ont été vérifiés que par tests et captures, pas en usage réel sur une vraie encoche.
- L'app n'est pas notarisée (clic droit > Ouvrir la première fois).
- Les barres de l'égaliseur se figent parfois après un changement de bureau (encoche dans l'espace SkyLight) alors que les niveaux continuent d'arriver : non résolu, abandonné pour l'instant (réafficher l'espace et supprimer les animations implicites n'ont rien changé).
- Sauvegardes à faire hors de ce Mac : certificat « Notchkit Self-Signed » (export .p12) et clé Sparkle (`generate_keys -x`).
- Le module assistant IA est masqué (code conservé dans `Modules/Assistant`).
- Convertisseur : pas de sortie MP3 (aucun encodeur dans macOS) ; un document converti en PDF garde le texte et ses styles, pas les images intégrées.

### Pistes après la 1.0
1. Performance : signposts autour du dépliage/repliage, Instruments (SwiftUI, Animation Hitches, Energy).
2. Widgets tiers déclaratifs (`widget.json` + scripts, rendus avec les composants StandBy).
3. Domotique via l'app Raccourcis.
