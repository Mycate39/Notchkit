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
                  avec page de détail, Autorisations, À propos ; flèches Précédent / Suivant)
  Resources/      Localizable.xcstrings, InfoPlist.xcstrings, AppIcon.icon (icône à couches Icon Composer : verre,
                  variantes sombre / transparente / teintée faites par macOS), Assets.xcassets, entitlements,
                  Info.plist (généré depuis project.yml)
NotchkitTests/    Suites Swift Testing, un fichier par domaine
ThirdParty/       MediaRemoteAdapter (voir PROVENANCE.md)
scripts/          AppIconLayers.swift (dessine les couches PNG de AppIcon.icon/Assets), make-dmg.sh, add-to-appcast.sh
appcast.xml       Flux de mises à jour Sparkle (lu par l'app depuis la branche main)
build.noindex/    Sortie de build, ignorée par git ; « .noindex » empêche Spotlight de lister l'app Debug
```

## Où trouver quoi

Carte pour aller droit au bon fichier (chercher ensuite le symbole avec `grep -n`). Un changement d'apparence ou de taille passe presque toujours par `NotchLayout` (valeurs) et `NotchContainerView` (rendu).

**Démarrage et câblage**
- `App/AppDelegate.swift` : crée `SettingsStore`, `ModuleManager`, `NotchViewModel` et `NotchWindowController`, puis les relie (alertes, réglages, maintien ouvert, mode jeu, zones de dépôt et ce que fait chaque dépôt). Lance aussi les modes `NOTCHKIT_STRESS` / `NOTCHKIT_SNAPSHOT`.
- `App/MenuBarContent.swift` : menu de l'icône de la barre des menus (dont la bascule du mode jeu et le menu Débogage). L'icône peut être masquée (`AppSettings.showsMenuBarIcon`, `MenuBarExtra(isInserted:)` dans `NotchkitApp`) ; relancer l'app depuis le Finder ouvre alors les réglages (`applicationShouldHandleReopen`, ignoré si `AutomatedRun.isActive`).

**Encoche : état, tailles, rendu**
- `Core/State/NotchViewModel.swift` : dépliage/repliage (`expand`, `collapse`, `expand(showing:)`), survol (`hoverChanged`, délais), bulles (`bubbleModules`, `hoverBubble`, menu empilé, commandes `hoverBubbleControls`), largeur repliée (`compactSideWidth`), tailles de la forme et de la fenêtre (`shapeSize`, `panelSize`), alertes (`present`), glisser-déposer, mode jeu (`setQuiet`), écran verrouillé (`setScreenLocked`).
- `Core/State/NotchLayout.swift` : toutes les constantes et fonctions de taille, d'espacement et d'animation (largeur des activités `activitySideWidth`, bulles, ombres, ressort `spring`, curseurs, `shapeSize`, pagination).
- `UI/NotchContainerView.swift` : le rendu. `CompactNotchView` (activité repliée gauche/droite, `compactRow`, île), `CompactBubbles` (bulles qui descendent du haut de l'écran ; commandes d'une bulle : musique, minuteur, fichiers de l'étagère, pile avec ses points, menu déroulé dont la première bulle reste suspendue, bulle allongée avec commandes : musique, minuteur), `ExpandedNotchView` (en-tête avec l'engrenage, pages de widgets côte à côte décalées selon la page ; plus d'indicateur de pages depuis le 28/10/2026 : sur une page étroite il n'avait pas la place à côté de la caméra, ne pas le remettre), `PageSwiper` (balayage au trackpad par moniteur d'événements ; logique dans `Core/State/PageSwipe.swift` : le défilement par pages de SwiftUI restait bloqué entre deux pages, ne pas y revenir), `PageView` (cartes), `WidgetContextMenu` (clic droit sur un widget).
- `Core/State/NotchAlert.swift` : alerte temporaire (gauche/droite, ou contenu agrandi sous l'encoche avec `expandedSize`).
- `UI/NotchShape.swift` : la forme (congés, coins). `Core/Settings/NotchAppearance.swift` : `notchBackground` (noir, couleur, Liquid Glass), couleur d'accent (`accentColor`, `onAccentColor`).
- `UI/NotchStyle.swift` : composants du style StandBy (boutons `.standBy`, `StandByBar`, curseur `StandBySlider`/`SliderTrack`/`SliderKnob`, `.notchCard()`, couleurs `StandBy.*`, `\.onAccent`, `\.sliderTint`).

**Fenêtre et système**
- `Core/Window/NotchWindowController.swift` : la fenêtre (taille animée, écran choisi, bureaux, verrouillage, évitement des menus, diagnostic). `NotchPanel` (niveau de fenêtre), `NotchHostingView` (souris et glisser-déposer reçus par AppKit), `DropCatcher`, `LockScreenSpace` (SkyLight), `ScreenLocator` (quel écran, encoche réelle ou non), `MenuBarAvoidance`.

**Modules**
- `Core/Modules/NotchModule.swift` : le protocole (`compactLeading/Trailing`, `compactPriority`, `bubblePriority`, `bubbleControls`, `expandedView`, `miniView`, `settingsView`, `widgetModuleID`) et `ModuleContext` (services offerts aux modules : alertes, `showModule`, `holdExpanded`, `otherModule`, `setQuietMode`…). Ajouter un service = un champ ici + son branchement dans `ModuleManager.makeContext` et l'AppDelegate.
- `Core/Modules/ModuleDescriptor.swift` : identité et drapeaux d'un module. `ModuleRegistry.swift` : la liste des modules. `ModuleManager.swift` : activation, activité principale (`compactModule`) et bulles (`secondaryCompactModules`), pages et tailles des widgets.
- `Modules/<Nom>/` : un dossier par module. Les plus gros : Music (sources MediaRemote et apps scriptables dans `Sources/`, égaliseur et analyse audio dans `Spectrum/`), Claude (serveur de hooks, installation, suivi des sessions) + Agents (page pleine), SystemHUD (touches, volume/luminosité, centre du son `AudioCenter`), LiveActivities (minuteurs, téléchargements ; réglage à la règle façon iOS dans `TimerRuler.swift`, dont `ScrollCatcherView` garde le défilement horizontal que `PageSwiper` lui laisse), VideoDownload (yt-dlp), Converter.
- Étagère et Convertisseur (revus le 30/10/2026) : un seul moteur de conversion, `FileConverter` (le menu « Convertir en » de l'étagère propose les mêmes formats que le convertisseur ; `FileActions` ne garde que ZIP et iCloud Drive). Les images sont écrites déjà tournées, étiquette d'orientation remise à droite et métadonnées gardées (`orientedImage`), le SVG passe par AppKit, le Markdown est mis en forme (`MarkdownText`). Le travail lourd (PDF, documents, GIF) tourne hors du fil principal, l'avancement d'une vidéo, d'un GIF ou d'un PDF s'affiche dans la barre (`currentProgress`), et une conversion ratée efface son fichier à moitié écrit. Un dépôt sur le convertisseur s'ajoute aux fichiers en attente de la même famille (`ConverterModule.merged`), sinon les remplace ; un fichier non convertible déposé sur « Convertir » affiche une alerte rouge. Étagère : un fichier redéposé repart en tête pour 5 minutes (`ShelfModule.dropped`), un texte déposé (`ShelfTextClipping`) est effacé quand il quitte l'étagère. Un fichier glissé hors de l'encoche passe par `NSItemProvider.file(at:)` (lien du fichier) : avec `NSItemProvider(contentsOf:)`, le Finder créait « Image PNG.png ». Après un dépôt sur « Convertir », l'encoche se replie et se rouvre dans la même image : `expand(showing:)` choisit la page lui-même (le `onAppear` de la vue dépliée ne repasse pas), et une sortie de survol annoncée par AppKit alors que le pointeur est encore sur la fenêtre (fin du glisser) est ignorée. Vérifié en vrai le 30/10/2026 par glisser-déposer depuis le Finder (`glisse2`).

**Réglages, disposition, divers**
- `Core/Settings/AppSettings.swift` : réglages généraux (délais de survol, écran, haptique, mascotte…) ; un réglage propre à un module vit plutôt dans le module (`UserDefaults`, clé `module.<id>.<nom>`).
- `UI/Settings/` : `SettingsView.swift` (fenêtre, onglets `SettingsTab`, historique Précédent / Suivant dans `SettingsRouter` posé sur chaque page par `.settingsHistory`, Général, liste des widgets et page de détail, À propos, icônes `SidebarIcon` au style d'icônes de macOS lu dans la clé non documentée `AppleIconAppearanceTheme` : aucune valeur = Par défaut, `RegularDark`, `ClearLight`/`ClearDark`, `…Automatic`), `AppearanceSettingsView`, `LayoutSettingsView` (éditeur de disposition), `PermissionsSettingsView`. Revue du 30/10/2026 :
  - Les réglages d'un module (`settingsView()`) sont des éléments séparés dans un `Group`, jamais un `VStack` : le formulaire en fait une ligne chacun.
  - La fenêtre reçoit à sa création le titre de la page ouverte (`SettingsTab.title(in:)`), sinon elle restait « Sans titre » ; elle retient sa taille et sa position (clé `NSWindow Frame NotchkitSettings`).
  - L'aperçu d'Apparence reprend la vraie forme et le vrai fond (`notchBackground`) sur un fond d'écran coloré.
  - À propos montre l'icône de l'app ; les licences listent MediaRemoteAdapter, Sparkle (`ThirdParty/Sparkle/Sparkle-LICENSE.txt`, copiée dans les ressources), Open-Meteo et les animations LottieFiles.
  - L'ouverture de session gère l'attente d'accord de macOS (`LaunchAtLogin.needsApproval`), et « Ne pas cacher les menus » propose l'accès Accessibilité quand il manque.
  - `AppSettings` décode chaque clé avec `try?` : une valeur illisible ne fait plus perdre les autres réglages.
- `Core/Layout/WidgetLayout.swift` : tailles de widget et calcul des pages ; `LayoutPresets` : dispositions prêtes à l'emploi. Dans l'éditeur, une page se déplace entière avec sa poignée ou ses flèches (`WidgetLayoutEngine.movePage`, contenu glissé `PageDrag`).
- `Core/Permissions/PermissionCenter.swift` : les autorisations (ajouter un cas = titre, usage, icône, couleur, ancre des Réglages Système, état, demande).
- `App/Onboarding/` : étapes du tutoriel (`OnboardingStep`), fenêtre et démonstrations animées. Refait le 30/10/2026 pour la 3.0 : les démonstrations reprennent le fond choisi (`\.onboardingAppearance` ; verre dessiné, le Liquid Glass ne suivait pas la taille animée), s'ouvrent sur le lecteur de musique, montrent les bulles (temps restant du minuteur, Autoriser / Refuser de l'agent cerclé d'ambre) et l'encoche à la taille de ses widgets ; celles de l'encoche repliée sont grossies (`DemoScreen(zoom:)`). La démo Fichiers est animée par images clés (`TimelineView`, une seule horloge) : avec `PhaseAnimator`, le document et l'encoche se décalaient. Un contenu retiré pendant que l'encoche de démonstration rétrécit laissait un rectangle fantôme : superposer les contenus, chacun à sa largeur, plutôt que les retirer. Dispositions en grille de tuiles (trois puis deux). Vérifiées en vrai, image par image (rafales de captures assemblées en planches). Avant-dernière étape : essai guidé sur la vraie encoche (`OnboardingTrialTask`, gestes cochés en observant `NotchViewModel`, l'étagère et le minuteur d'essai) ; un changement de page juste après l'ouverture ne compte pas comme un balayage (`isSwipe`), et un fichier redéposé compte (date du premier élément de l'étagère). Le fichier d'essai se glisse par une source AppKit `AcceptedInternalDragSource` : l'encoche refuse sinon tout glisser venu de Notchkit, et `DropCatcher` ne voit les glissers internes que par `internalDragDidStart`.
- Déverrouillage (`Modules/Unlock`) : animation Face ID façon Dynamic Island, vidéo HEVC transparente `Resources/FaceIDUnlock.mov` rendue depuis une animation Lottie (moteur SVG de lottie-web pour garder son flou, fond retiré, recadrée : cercle à 48 % d'un carré de 200 pt, coins de 40 pt via `NotchAlert.centersExpandedContent` / `expandedCornerRadius`). Demande Touch ID dans le même carré : vidéo `Resources/TouchIDPrompt.mov` (empreinte, en pause à 2 s pendant l'attente via `TouchIDPromptState`, puis transformation en cercle quand la demande se ferme), relayée par le cercle et la coche Face ID en rouge dessinés en SwiftUI.
- `UI/Mascot/` : dessins des mascottes (`MascotDesigns`, `RobotMascots`, `FaceIDMascots`), mouvements et réactions (`MascotMotion`), sons (`MascotSounds`).
- `Core/Utilities/Haptics.swift` : vibrations du trackpad, selon les règles d'Apple : `.tap` (geste ou commande), `.step` (cran : volume, minutes de la règle), `.snap` (alignement : page, zone de dépôt, bout de la règle). Les alertes ne vibrent pas.
- Accessibilité (HIG) : texte de 10 pt au moins, opacité 0,55 au moins sur fond noir, `.accessibilityLabel` sur chaque bouton à icône seule, boucles décoratives arrêtées si `NotchAccessibility.reduceMotion` (`UI/NotchStyle.swift`). Les boutons qui précèdent une demande d'autorisation système s'appellent « Demander l'accès… ».
- Priorité de l'activité repliée (`ModulePriority`) : la musique en lecture (`media`) passe devant toutes les activités en cours (Claude Code qui travaille, minuteurs) ; seule une information urgente (`high` : minuteur qui sonne) la relègue dans une bulle. Claude Code qui demande une autorisation (`urgentActivity`) reste dans une bulle cerclée d'ambre à côté de la musique : au survol, Autoriser et Refuser en sortent (`ClaudeBubbleControls`) ; la bulle de l'agent ne s'ouvre qu'au clic (`bubbleOpensOnHover`). Une nouvelle demande n'ouvre plus l'encoche d'elle-même (28/10/2026), sinon la bulle ne servait à rien. La bulle du minuteur survolée montre le temps restant.
- Verre net et fenêtre clé (30/10/2026) : le Liquid Glass de macOS n'a son rendu net que dans la fenêtre clé (sinon flou terne). L'encoche devient donc fenêtre clé dès qu'elle s'ouvre et la rend à la fermeture (`NotchWindowController.updateKeyStatus` : réglages s'ils sont devant, sinon l'app au premier plan) ; ne pas poser `becomesKeyOnlyIfNeeded` sur le panneau. Les réglages et le tutoriel donnent une icône dans le Dock tant qu'ils sont ouverts et réclament la fenêtre clé jusqu'à l'obtenir (`WindowActivation`). Le propriétaire veut le verre de macOS, pas un verre dessiné par Notchkit.
- Volume et luminosité au clavier : le niveau glisse vers le cran suivant en 0,2 s (`LevelRamp` dans `SystemHUDModule.swift`), comme avec macOS ; pendant le glissement, les changements de volume intermédiaires ne sont pas affichés.
- Banc d'essai des alertes : l'action de démo `alert` (`value` = nom, voir `DemoDirector.demoAlert`) affiche chaque alerte simple ; une alerte a sa propre identité de vue (`.id(alert.id)`), pour que deux alertes de suite du même module ne partagent pas leur état animé.
- Contour de l'encoche et des bulles (style Live Activities) : `NotchModule.keyLineColor` (couleur de l'activité, `nil` = gris neutre), dessiné avec `NotchLayout.keyLine`.
- `App/Debug/` : captures (`SnapshotRenderer`, `PromoSnapshots`), rendu vidéo des mascottes, et mode démo (`Demo/`) : `NOTCHKIT_DEMO=scenario.json` joue un scénario minuté sur la vraie encoche (vrais chemins : aperçu du déverrouillage, minuteurs, hooks de Claude Code, `NotchViewModel`) et filme sa fenêtre seule sur fond transparent (ScreenCaptureKit, ProRes 4444), avec des réglages jetables (`DemoSettings`). Utilisé par la skill `.claude/skills/notch-video` pour les vidéos de présentation.
- Tests : `NotchkitTests/<Domaine>Tests.swift` ; la mise en page de l'encoche et les bulles sont dans `ModuleManagerTests` (`NotchLayoutTests`) et `BubbleControlsTests`.

## Conventions de code

- **Modules** : une classe `<Nom>Module` conforme à `NotchModule`, avec un `descriptor` statique (`id` en minuscules comme `"music"`, `"activities"`), `compactPriority`, `compactLeading()/compactTrailing()`, `expandedView()`, `miniView()`, `settingsView()`. L'enregistrer dans `ModuleRegistry.allModules`. Les vues s'appellent `<Nom>ExpandedView`, `<Nom>MiniView`, `<Nom>SettingsView`. Un module sans widget (arrière-plan seulement) met `descriptor.providesWidget = false`. Un module qui doit rester utilisable widget masqué met `descriptor.contextual = true` et implémente `var hasContextualContent` (ex. Étagère, Captures) : il tourne toujours, et s'affiche en dernière page, hors de la disposition, tant qu'il a du contenu (`ModuleManager.contextualIDs`, `layoutPageIDs` pour l'éditeur). Un module dont les animations viennent du système (branchement du chargeur, AirPods, touches de volume) met `descriptor.backgroundEvents = true` : widget désactivé, il tourne quand même pour ses alertes, sans carte ni activité repliée (`ModuleManager.backgroundIDs`) ; c'est le cas de Batterie, AirPods et HUD. Les nouveaux widgets sont masqués par défaut (`defaultEnabled: false`).
- **Tailles de widget** : `WidgetSize` vaut `.mini`, `.small`, `.medium`, `.large` (poids 0,5 / 1 / 1,5 / 2), lu avec `@Environment(\.widgetSize)`. Les vues doivent tenir dans toutes les tailles ; préférer `ViewThatFits` aux cadres fixes. Il n'y a plus de taille d'encoche à choisir (27/10/2026) : l'encoche ouverte suit les widgets de la page affichée : hauteur selon le plus grand widget (`NotchLayout.expandedHeight(sizes:)` : 150 pt avec des Mini seulement, 190 pt avec des Petit ou des Moyen, 222 pt dès qu'il y a un Grand) et largeur (`NotchLayout.pageSize` : 140 pt par unité de poids, plus écarts et marges ; au plus 4 unités par page, page pleine pour un widget pleine page). Elle s'élargit ou se resserre en changeant de page ; un widget est donc dessiné pour sa propre largeur, pas pour celle de l'encoche.
- **Constantes de mise en page et ressorts** : dans `NotchLayout`, sous forme de fonctions statiques pures et testées. Pas de nombres magiques éparpillés dans les vues.
- **Style** : look StandBy — `.buttonStyle(.standBy(size, active:, circle:))`, `StandByBar`, `StandBySlider`, `StandBy.surface/amber/defaultAccent`, `.notchCard()`. La couleur d'accent (bleu de macOS par défaut, `StandBy.defaultAccent`) vient de `.tint` ; le texte posé dessus vient de `@Environment(\.onAccent)` (blanc sur une couleur foncée, noir chaud sur une claire). L'ambre reste pour les états qui demandent l'attention.
- **Localisation** : les chaînes sources sont en français (`sourceLanguage: fr`), l'anglais est la langue de développement. Les builds en ligne de commande ne synchronisent **pas** le catalogue : ajouter chaque nouvelle clé avec **à la fois** `en` et `fr` via `scripts/add-strings.py fichier.json` (objet `{ "français": "English" }` ; `--catalog Notchkit/Resources/InfoPlist.xcstrings` pour Info.plist). `LocalizationTests` échoue si les deux tables diffèrent.
- **Exécutions automatisées** : tout ce qui pourrait solliciter l'utilisateur (capture audio, presse-papiers, mises à jour) est ignoré quand `AutomatedRun.isActive`.
- **Tests** : structs Swift Testing ; les noms de test sont des phrases françaises en camelCase (`bullesZoneSepareeDeLEncoche`). Extraire la logique dans des fonctions pures pour la tester sans UI.
- **Écran verrouillé** : `NotchViewModel.isScreenLocked` ; seules les activités repliées restent visibles, sans aucune interaction (pas d'ouverture, de gonflement au survol, de menu des bulles, de dépôt ni de clic). Toute nouvelle interaction doit respecter ce verrou. Seule exception : le lecteur de l'écran verrouillé (`Modules/Music/LockScreenPlayer.swift`, réglage « Grand lecteur », « Dans l'encoche » ou « Aucun »). Grand lecteur (par défaut, `NotchModule.lockScreenMedia`, fenêtre `LockScreenMediaWindow`, tailles `NotchLayout.lockScreenMedia(screen:)`) : pochette sous l'heure puis panneau en verre transparent ; un clic sur la pochette la range dans le panneau, comme sur l'iPhone. Aucun verre ni flou de macOS ne voit le fond au-dessus de l'écran verrouillé (voile gris uniforme) : ne pas réessayer `glassEffect`, `NSGlassEffectView` ni `NSVisualEffectView`. Dans l'encoche (`NotchModule.lockScreenLeading/Trailing`, `NotchViewModel.lockScreenModule`) : l'encoche s'élargit sans descendre (`NotchLayout.lockScreenSideWidth` ; l'heure de macOS, juste dessous, ne peut pas bouger), avec pochette, titre, commandes et barres de son. Un lecteur sorti de « À l'écoute » en pause (Deezer, navigateurs) ne reçoit plus de commande : envoyer « lecture » par MediaRemote ouvre alors Apple Music, ne pas réessayer ; ses boutons sont grisés.
- **Réglages** : tout nouveau réglage a une valeur par défaut et un décodage tolérant (`decodeIfPresent` + valeur de repli) pour que les anciens fichiers de réglages se chargent toujours.

## Commandes fréquentes

À lancer depuis la racine du dépôt avec `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
xcodegen generate                                   # après toute modification de project.yml ou ajout/suppression de fichiers

xcodebuild build -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'

xcodebuild test -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'   # chercher « TEST SUCCEEDED »

# Tournage d'une vidéo avec la vraie encoche (Debug ; Notchkit quitté) : voir .claude/skills/notch-video
sh .claude/skills/notch-video/scripts/record.sh ~/Documents/Projets/Notchkit-video/tournages/<film> en fr

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
   Le build Release est signé avec « Notchkit Self-Signed » : vérifier `codesign -dvv <app>` (Authority=Notchkit Self-Signed). Ne jamais supprimer ce certificat du trousseau ni le remplacer : macOS ferait perdre aux utilisateurs leurs autorisations (Accessibilité) à la mise à jour suivante. Sauvegarde faite le 26/10/2026 (l'ancien certificat avait été perdu avec l'ancien Mac) : image disque chiffrée `Notchkit-sauvegarde.dmg` (AES-256, certificat .p12 + clé Sparkle), dans iCloud Drive › NotchKit et à un second endroit hors de ce Mac ; mots de passe dans l'app Mots de passe. À refaire si le certificat ou la clé changent. Aucun certificat payant n'est utilisé.
   **Avant de publier, lancer l'app Release** (`<app>/Contents/MacOS/Notchkit`) et vérifier qu'elle tourne encore après quelques secondes : les tests et le stress test passent par le build Debug (signé ad hoc) et ne détectent pas un échec de chargement propre au build Release (1.0.1 et 1.0.2 ont été publiées dans cet état).
4. `scripts/add-to-appcast.sh <dossier-sortie>/Notchkit-x.y.z.dmg <app> <notes.md>` — signe le DMG avec la clé privée EdDSA stockée dans le trousseau de session (« Private key for signing Sparkle updates » ; ne jamais la supprimer, sauvegarde via `generate_keys -x`) et ajoute l'entrée en tête de `appcast.xml`. La clé a été remplacée au build 12 (1.0.1) : le script marque chaque entrée comme informative (`sparkle:informationalUpdate`, `belowVersion` 12) pour que les builds 11 et antérieurs affichent un lien vers la release au lieu d'échouer. Committer `appcast.xml` seulement après la création de la release GitHub.
5. `git push`, `git tag -a vx.y.z`, pousser le tag, `gh release create vx.y.z <dmg> --latest --notes-file <notes.md>` (les versions 1.x ne sont plus des préversions), puis pousser `appcast.xml`.
   L'URL du flux est `https://raw.githubusercontent.com/Mycate39/Notchkit/main/appcast.xml`.

**Bêta / RC** : même procédure, avec `MARKETING_VERSION` `x.y.z-beta.N` (ou `x.y.z-rc.N`, candidate à la version finale, comme sur iOS) (le build augmente normalement), tag `vx.y.z-beta.N`, `gh release create … --prerelease --latest=false`. Depuis le 29/10/2026, l'étape `appcast.xml` se fait aussi : `add-to-appcast.sh` met une bêta ou une RC dans le canal Sparkle « beta » (`<sparkle:channel>beta</sparkle:channel>`), proposé seulement à qui a activé « Recevoir les versions bêta » (Réglages > Général ; activé d'office sur une bêta installée, `Updater.allowedChannels`). Les versions finales, sans canal, vont à tout le monde. Les versions sans ce réglage (3.0.0-beta.3 et antérieures) ne voient jamais les bêtas de l'appcast : il faut installer la première bêta qui l'a à la main.

## État (24 octobre 2026 : 2.0.0 publiée)

### Fonctionne
- Fenêtre d'encoche sur n'importe quel écran : vraie encoche, encoche simulée ou pilule flottante ; reste en place à travers les Spaces ; se décale à droite pour ne jamais masquer les menus de l'app active (nécessite l'autorisation Accessibilité).
- Activités compactes, mini-encoches, menu empilé, zones de survol séparées, contour style Dynamic Island. Une bulle qui a des commandes (`bubbleControls()`, ex. la musique) s'allonge vers la droite au survol au lieu d'ouvrir l'encoche ; `bubblePriority` garde la bulle de la musique en pause.
- Encoche dépliée avec pages et widgets en quatre tailles, éditeur de disposition, dispositions prêtes à l'emploi, encoche ouverte à la largeur de ses widgets, contrôles style StandBy, couleur d'accent, fond Liquid Glass (macOS 26). Réglages groupés par catégorie.
- Modules historiques : Musique, Horloge, Batterie, Calendrier, Météo, Claude Code, Étagère + AirDrop, AirPods/Bluetooth, Activités en direct, Presse-papiers, HUD volume/luminosité (aussi Touch Bar et Centre de contrôle), Déverrouillage, Téléchargements vidéo.
- Ajouts de la 1.0 (masqués par défaut) : Captures d'écran (contextuel), Étagère contextuelle avec texte déposé et actions (ZIP, conversion, iCloud Drive) ; depuis la 2.0, chaque fichier y reste 5 minutes (`ShelfModule.retention`, réglable) et l'étagère s'affiche alors comme une activité en cours, Commutateurs rapides (mode sombre, anti-veille, icônes du bureau, verrouillage clavier), Webcam, Journée, Notes, chronomètre/alarmes/Pomodoro, Rappels (EventKit), Moniteur système (échantillonneur partagé `SystemSampler`, actif seulement si une carte est visible), Dashboard, Temps d'écran et Santé (mesurés localement), Traduction (framework Translation, macOS 15+). L'ancrage des fenêtres a été supprimé le 24/10/2026.
- Anglais et français ; mises à jour Sparkle ; DMG signé avec le certificat auto-signé.

### Version 2.0.0 (publiée le 24/10/2026, `v2.0.0`, build 25, avec appcast)
- Publié dans la beta 1 (`v2.0.0-beta.1`, préversion GitHub, hors appcast) : tutoriel d'accueil au premier lancement (rejouable par « Revoir le tutoriel… » ; `AppSettings.onboardingCompleted`, vrai par défaut pour un ancien fichier de réglages), onglet Widgets unique dans les réglages, indicateur de pages visible seulement pendant un balayage, engrenage sans pastille.
- Fait depuis : barres de l'égaliseur arrondies aux deux bouts (animation de hauteur, plus d'échelle), indicateur de pages animé (pastille qui glissait avec `NotchLayout.pageIndicatorSpring`, devenu `selectionSpring`, icônes qui se précisent, apparition en fondu).
- Fait depuis la beta 1 : encoche gardée en permanence dans l'espace SkyLight de niveau 400 (niveaux connus : 100 assistant de configuration, 300 écran verrouillé, 400 centre de notifications sur l'écran verrouillé ; l'ancien niveau 100 restait sous l'écran verrouillé). Elle s'affiche à l'écran verrouillé (vérifié le 18/10/2026 sur macOS 27) et ne doit plus disparaître ni se redimensionner en changeant de bureau ; au verrouillage, la fenêtre passe aussi au-dessus du bouclier (`NotchPanel.lockedLevel`) avec `canBecomeVisibleWithoutLogin`. Écran verrouillé sans interaction. Égaliseur : animations relancées au changement de bureau, retour à l'animation simple si le flux audio s'interrompt, hauteurs en direct posées sans animation.
- Fait depuis (19/10/2026) :
  - Page Agents (`Modules/Agents`, pleine page, `fullPage`) inspirée de coucou : mascotte choisie parmi 33 (Réglages > Apparence, aussi dans l'encoche repliée), étapes de Claude Code, éditeur et terminal en direct, autorisations et questions de Claude Code répondues depuis l'encoche (hooks version 4 ; pendant une question, le panneau prend toute la page). Widgets Claude Code et Ollama retirés ; Claude Code n'est plus un module à part dans les réglages : c'est le moteur de la page Agents (`companionOf: "agents"`, activé avec elle), dont seule l'intégration (hooks) reste réglable, dans la page du widget Agents. Délai pour répondre depuis l'encoche supprimé. Widgets Git et GitHub, et services Vercel / Stripe, supprimés (19/10/2026). La discussion avec la mascotte (Apple Intelligence ou Claude, avec outils façon Siri) a été essayée puis abandonnée le 19/10/2026 : trop limitée face au nouveau Siri, ne pas la refaire.
  - Mascotte interactive : réactions au clic, sons synthétisés (`MascotSounds`, aucun fichier, transposés d'une quarte vers le grave), réglables dans Apparence.
  - Publié dans la beta 2 (`v2.0.0-beta.2`, 19/10/2026) : tous les points de cette liste, sauf le compteur d'images par seconde du mode jeu et les commandes de la bulle de la musique (20/10/2026).
  - Publié dans la beta 3 (`v2.0.0-beta.3`, 20/10/2026) : commandes dans les bulles (musique, minuteur), mode jeu aux images par seconde, icône de batterie de macOS 27, balayage des pages géré à la main, bulles qui descendent du haut, points de la pile, largeurs uniformes, accent bleu par défaut.
  - Publié dans la beta 4 (`v2.0.0-beta.4`, 21/10/2026) : minuteur à la règle, étagère en activité de 5 minutes, animation Touch ID au déverrouillage, Précédent / Suivant et icônes au style de macOS dans les réglages, bouton Rétablir des délais de survol, barre de progression de la musique stable en mode rebondissant.
  - Publié dans la RC 1 (`v2.0.0-rc.1`, 22/10/2026, candidate à la version finale) : règle du minuteur à disposition stable et défilement cinétique, audit des règles d'Apple (accessibilité, vibrations, icône de barre des menus masquable, textes des autorisations, contour coloré, icône Icon Composer). L'intégration à Siri (App Intents) a été essayée puis abandonnée le 21/10/2026.
  - Publié dans la RC 2 (`v2.0.0-rc.2`, 23/10/2026) : tutoriel refait avec les nouveautés et essai guidé sur la vraie encoche, indicateur de volume et de luminosité élargi (`NotchLayout.levelIndicatorSideWidth` ; autres exceptions à la largeur de la musique depuis la 3.0 : alertes qui écrivent un mot à droite, `NotchAlert.withTextSides()`, 90 pt, et rappels de Santé, 120 pt), fenêtres des réglages et du tutoriel toujours au premier plan (`WindowActivation` ; depuis le 30/10/2026, icône dans le Dock tant qu'elles sont ouvertes, `setActivationPolicy(.regular)`, car macOS rendait la main au Finder après un clic dans l'encoche, et `moveToActiveSpace` pour s'ouvrir sur le bureau courant), bouton × des bulles réparé (commandes qui débordent : la colonne des bulles ne doit pas avoir de `contentShape`, qui limiterait aussi leurs clics).
  - Publié dans la RC 3 (`v2.0.0-rc.3`, 24/10/2026) : lecteur de musique sur l'écran verrouillé, encoche masquée pendant une vidéo en plein écran (`Core/Window/FullScreenHiding.swift`, activé par défaut : app au premier plan en plein écran sur l'écran de l'encoche ET un autre processus qui empêche la veille de l'écran ; l'anti-veille de Notchkit est ignorée), animation Face ID, cran haptique des pages pendant le balayage, lecteur vide dans le widget Musique, barres de son aplaties en points à l'arrêt, heure repliée désactivée par défaut.
  - Mode jeu (`Modules/GameMode`) : encoche discrète et images par seconde seulement (`FrameRateMeter` : ScreenCaptureKit compte les images complètes de l'app au premier plan, autorisation Enregistrement de l'écran). S'active comme le mode jeu de macOS (jeu en plein écran au premier plan, `FullScreenDetector`), ou à la main.
  - Centre du son dans le panneau du volume : sortie, micro, apps qui jouent (repli sur l'app « À l'écoute », les navigateurs ne signalant pas toujours leur sortie), volume par app par interception Core Audio (macOS 14.2+).
  - Onglet Autorisations et synthèse dans le tutoriel ; curseurs Liquid Glass (macOS 26+) ; zones cliquables agrandies ; boutons natifs dans les réglages.
  - Convertisseur (`Modules/Converter`, widget temporaire) : images, audio (afconvert), vidéo (AVFoundation, GIF), documents (CoreText) et PDF ; zones de dépôt toujours proposées : étagère, Convertir, AirDrop ; dépôt direct sur sa page ouverte.
- Publié dans la 2.0.0 finale (24/10/2026) : tout ce qui précède, plus la demande Touch ID (empreinte puis coche rouge), l'étagère repliée réduite à son icône (elle quitte l'encoche une fois ses fichiers récupérés) et la suppression de l'ancrage des fenêtres. README réécrit pour la 2.0.
- Animations de déverrouillage : « Apple Face ID » (Mau Ali) et « Fingerprint Touch ID » (Himanshu Patel), gratuites sous la Lottie Simple License (usage commercial et modification permis, crédit facultatif ; vérifié le 26/10/2026), créditées dans le README.

### Vidéo de présentation
- Projet HyperFrames hors du dépôt : `~/Documents/Projets/Notchkit-video` (16:9 de 45 s à la racine, 9:16 de 30 s dans `vertical/`, textes `en.json` / `fr.json`, design calqué sur le code de l'app dans `design.md`). Rendus dans `renders/`.
- Musique de toutes les vidéos : `assets/music/danker.mp3` ; extraits calés pour que la montée à 24 s tombe à l'ouverture de l'encoche.
- Chaque nouvelle vidéo va aussi dans le dossier Google Drive « NotchKit ».
- Vidéos de la 2.0 (refaites le 26/10/2026 avec la vraie encoche filmée par le mode démo, skill `notch-video`) : cinq films de 30 s en 16:9, anglais et français, dans `renders/Vidéos 16-9/` ; logo, bannière et photo de profil YouTube dans `renders/Logo/`, miniatures dans `renders/Miniature vidéos/`. Un dossier `<film>-reel/` par film, prises dans `tournages/`, rendus par `assets/render-reel.py`. Le README montre « A Day with Notchkit 2.0 » (anglais, encoche réelle).
- La vidéo du README est un lien `github.com/user-attachments/assets/…` : on l'obtient en téléversant le fichier dans l'éditeur web du README sur GitHub (sans y enregistrer), puis on remplace le lien dans le README local.

### Version 3.0.0 (en cours, gratuite ; l'abonnement viendra plus tard)
- Publié dans la beta 1 (`v3.0.0-beta.1`, 27/10/2026, préversion GitHub, hors appcast, build 26) : design « Verre », encoche à la taille de ses widgets (plus de réglage « Taille »), fonds Noir et Verre seulement, corrections d'affichage des widgets et des animations au changement de bureau, ombre de lisibilité en mode verre, engrenage toujours visible. Banc d'essai visuel : `scripts/visual-matrix.py` (dont `glass`).
- Publié dans la beta 2 (`v3.0.0-beta.2`, 28/10/2026, préversion GitHub, hors appcast, build 27) : grand lecteur de l'écran verrouillé (pochette qui se range dans le panneau au clic), musique en lecture devant les activités en cours, temps restant dans la bulle du minuteur, alertes à texte élargies, volume et luminosité qui glissent d'un cran à l'autre, verre toujours au rendu actif, AirPlay au premier clic sur l'écran verrouillé, indicateur de pages retiré.
- Publié dans la beta 3 (`v3.0.0-beta.3`, 28/10/2026, préversion GitHub, hors appcast, build 28) : barre de lecture fluide et glissable (déplacement dans le morceau), indicateur de volume et de luminosité au-dessus d'une vidéo en plein écran, bulle de l'agent ouverte au clic avec Autoriser et Refuser au survol, plus d'ouverture automatique sur une demande d'autorisation.
- Publié dans la beta 4 (`v3.0.0-beta.4`, 29/10/2026, préversion GitHub, build 29, **dans l'appcast en canal « beta »**, première bêta à y figurer) : réglage « Recevoir les versions bêta » et canal bêta de Sparkle. À installer à la main une fois ; les bêtas suivantes arrivent par la mise à jour.
- Publié dans la beta 5 (`v3.0.0-beta.5`, 30/10/2026, préversion GitHub, build 30, canal « beta » de l'appcast) : lecteur de musique en première page, traducteur intégré, pages déplaçables dans l'éditeur, grands coins de l'encoche noire, revue de l'étagère et du convertisseur, des réglages et du tutoriel, plus aucun texte coupé par « … » dans les widgets.

### Design « Verre » (27/10/2026)
- Fond « Verre » façon lecteur de l'iPhone : noir sur le haut, long dégradé vers un verre clair (Liquid Glass `.clear`), grands congés (20 pt) et coins (36 pt), sans contour ; widgets posés sur le verre, sans carte, écart agrandi. Depuis le 30/10/2026, la musique n'est plus un widget (`providesWidget = false`, `playerPage`) : son lecteur est toujours la première page de l'encoche ouverte, même quand rien ne joue, hors de la disposition (`ModuleManager.pageIDs`). Petit lecteur façon iPhone, avec les deux fonds : Grand 456 × 200 pt par défaut ou Compact 384 × 168 pt, éléments à l'échelle `MusicPlayerStyle.scale` (`MusicPlayerStyle`, Réglages > Widgets > Musique), avec aléatoire et répétition, sans engrenage à côté de la caméra.
- Depuis le 30/10/2026, l'encoche ouverte sur fond noir a les mêmes grands congés et coins que le Verre (`NotchLayout.earRadius` / `cornerRadii`), et garde son contour.
- À faire : revoir certains widgets pour ce mode (pensés pour une carte noire : textes sombres, éléments qui débordent, contrastes).

### Limites connues
- Pas de suivi des téléversements des autres apps (aucune API publique) ; True Tone et notifications avec réponse abandonnés (API privées).
- La lecture AX, le rendu Liquid Glass et la détection de projet Terminal n'ont été vérifiés que par tests et captures, pas en usage réel sur une vraie encoche.
- Changement de bureau pendant une animation (diagnostic du 26/10/2026, `scripts/visual-matrix.py spaces | animations | during | faceid`, mode démo avec `NOTCHKIT_DIAGNOSTIC`) :
  - Corrigé : Face ID / Touch ID figés sans la coche (une AVPlayerLayer décroche au changement de bureau ; `VideoHostView` pose désormais les images sur une couche ordinaire) ; encoche décalée et ouverture sans animation (remise au premier plan et replacement de la fenêtre au changement de bureau, désormais seulement si elle a disparu ou si l'écran a changé).
  - Limite de macOS, non corrigeable : au balayage du trackpad, macOS gèle l'affichage de l'encoche environ 1 s alors que l'app continue de dessiner (toutes les images sont posées) ; l'animation saute ensuite. `activeSpaceDidChange` arrive à la FIN de la transition : impossible de mettre en pause au début. Le gel ne vient ni de l'espace SkyLight ni d'une fenêtre masquée (`occlusionState` reste visible), et `.stationary` est déjà posé. Une alerte affichée est prolongée de 1,1 s (`NotchViewModel.spaceDidChange`).
  - Les barres de l'égaliseur ne se sont pas figées en 20 changements de bureau (Ctrl ←/→, son réel) : bug non reproduit.
- Le module assistant IA est masqué (code conservé dans `Modules/Assistant`).
- Convertisseur : pas de sortie MP3 ni WebP (aucun encodeur dans macOS ; FLAC oui, par afconvert), pas de lecture WebM ni MKV par AVFoundation (la conversion échoue avec un message) ; un document converti en PDF garde le texte et ses styles, pas les images intégrées.
