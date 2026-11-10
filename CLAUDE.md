# Notchkit

**Langue : réponds toujours en français** (messages, explications, résumés, questions), quelle que soit la langue du code ou des outils.
Seul ce qui part sur GitHub reste en anglais (voir les règles ci-dessous).

App macOS native qui transforme l'encoche (ou une pilule flottante sur les Mac qui n'en ont pas) en zone vivante :
musique, minuteurs, batterie, météo, calendrier, presse-papiers, étagère de fichiers, activité de Claude Code, téléchargements vidéo, conversion de fichiers.
App de barre des menus (`LSUIElement`), distribuée hors Mac App Store, non sandboxée.

## Stack technique

| Élément | Version |
|---|---|
| Swift | Mode de langage 6.0, compilateur 6.2.4 |
| Xcode | 27.1 — définir `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` ; XcodeGen et `gh` via Homebrew (`/opt/homebrew/bin`) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Observation (`@Observable`) |
| macOS minimum | 14.0 (Liquid Glass uniquement sur macOS 26) |
| Projet | XcodeGen — `project.yml` fait foi, ne jamais modifier `Notchkit.xcodeproj` à la main |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) |
| Dépendances | Sparkle 2.10.0 (SPM) ; MediaRemoteAdapter (copié dans `ThirdParty/`, BSD 3-Clause) |
| Architectures | Universelle ; machine de dev : MacBook Pro 14" M1 Pro avec vraie encoche (185 × 32 pt, barre des menus 33 pt) |
| Signature | Debug : ad hoc. Release : certificat auto-signé « Notchkit Self-Signed » (trousseau de session, valable jusqu'en 2036), Hardened Runtime et `disable-library-validation` (sinon Sparkle ne se charge pas) ; non notarisée |

## Règles impératives

- **Pas de code GPL** (ex. Boring Notch, FaceMac) : inspiration uniquement, jamais de copie.
- **API publiques uniquement**, sauf les API privées déjà acceptées : MediaRemote (via MediaRemoteAdapter), DisplayServices (luminosité) et SkyLight (`LockScreenSpace` : espace de niveau 400 qui garde l'encoche au-dessus des bureaux, du plein écran et de l'écran verrouillé). Demander avant d'en ajouter une autre.
- **Pas de HomeKit** (indisponible sur macOS natif) ; la domotique passerait par `shortcuts run`.
- **Ne jamais lancer l'app dans Xcode à la place du propriétaire** (pas d'AppleScript sur Xcode) : il lance lui-même avec ⌘R. Pour un changement visible en usage réel (survol, bureaux, écran verrouillé), lui demander de tester avant de committer.
- **Vérifier soi-même avant de demander un essai au propriétaire.** Pour chaque point à vérifier, se demander d'abord si on peut le faire seul, et le faire :
  - captures (`NOTCHKIT_SNAPSHOT`, une langue avec `-AppleLanguages "(es)"`) ;
  - mode démo filmé (`NOTCHKIT_DEMO`, Notchkit quitté), images extraites en planches ;
  - tests, stress test, et vraies commandes ou vrais hooks envoyés à une instance de test.

  Ne demander au propriétaire que ce qui exige vraiment lui ou son Mac : survol et gestes réels sur l'encoche, vibrations, Touch ID, écran verrouillé, ses comptes et ses apps, autorisations système à accorder. Lui dire ce qui a déjà été vérifié, et comment.
- **Ne jamais tuer tous les processus Notchkit** (`pkill -x Notchkit`) : n'arrêter que les instances de test sous `build.noindex/`.
- Les instances de test partagent le vrai domaine `UserDefaults` (`com.andeolchenaux.notchkit`) : sauvegarder (`defaults export`) puis restaurer (`defaults import`), ou nettoyer toute clé écrite.
- Ne committer qu'après réussite du build, des tests **et** du stress test. Messages de commit en anglais ; le propriétaire est le seul auteur (pas de ligne co-auteur).
- Tout ce qui est sur GitHub est en anglais (README, notes de version, commits). Les commentaires du code sont en français.

## Architecture des dossiers

```
Notchkit/
  App/            AppDelegate (câblage), menu de la barre des menus, Updater (Sparkle), Debug/ (captures, mode démo), Onboarding/
  Core/
    Modules/      NotchModule (protocole + ModuleContext), ModuleDescriptor, ModuleManager, ModuleRegistry
    State/        NotchViewModel (dépliage, survol, bulles, alertes), NotchLayout (toutes les tailles et ressorts), NotchAlert, PageSwipe
    Window/       NotchWindowController, NotchPanel, NotchHostingView, ScreenLocator, MenuBarAvoidance, LockScreenSpace,
                  DropCatcher, FullScreenHiding
    Permissions/  PermissionCenter     Layout/  WidgetLayout, LayoutPresets
    Settings/     AppSettings, NotchAppearance, SettingsStore, LaunchAtLogin     Utilities/  AutomatedRun, Haptics…
  Modules/<Nom>/  Un dossier par module : <Nom>Module.swift (+ <Nom>Views.swift, utilitaires)
  UI/             NotchContainerView (rendu), NotchShape, NotchStyle (style StandBy), Mascot/, Settings/ (fenêtre des réglages)
  Resources/      Localizable.xcstrings, InfoPlist.xcstrings, AppIcon.icon, Assets.xcassets, vidéos Face ID / Touch ID
NotchkitTests/    Suites Swift Testing, un fichier par domaine
scripts/          make-dmg.sh, add-to-appcast.sh, add-strings.py, stress.sh, visual-matrix.py, AppIconLayers.swift
appcast.xml       Flux Sparkle (lu depuis la branche main)
build.noindex/    Sortie de build, ignorée par git (« .noindex » : pas dans Spotlight)
```

## Où trouver quoi

Un changement d'apparence ou de taille passe presque toujours par `NotchLayout` (valeurs) et `UI/NotchContainerView.swift` (rendu : `CompactNotchView`, `CompactBubbles`, `ExpandedNotchView`, `PageSwiper`, `PageView`, `WidgetContextMenu`). Chercher ensuite le symbole avec `grep -n`.

- **État de l'encoche** : `NotchViewModel` (`expand`, `collapse`, `expand(showing:)`, `hoverChanged`, bulles `bubbleModules` / `hoverBubbleControls`, `compactSideWidth`, `present`, `setQuiet`, `setScreenLocked`).
- **Modules** : protocole dans `NotchModule.swift` (`compactLeading/Trailing`, `compactPriority`, `bubblePriority`, `bubbleControls`, `expandedView`, `miniView`, `settingsView`, `keyLineColor`). Ajouter un service à `ModuleContext` = un champ + son branchement dans `ModuleManager.makeContext` et l'AppDelegate.
- **Gros modules** : Music (`Sources/`, `Spectrum/`, `LockScreenPlayer.swift`), Claude (hooks, sessions) + Agents (page pleine), SystemHUD (`LevelRamp`, `AudioCenter`), LiveActivities (`TimerRuler.swift`), Shelf, Converter (`FileConverter`, seul moteur de conversion), Unlock, GameMode, Scripts.
- **Agents de code** (`Modules/Claude/`) : Claude Code parle par hooks HTTP. Codex, Gemini CLI et Cursor n'ont que des hooks « commande » : `AgentHooksInstaller` écrit leurs hooks (`~/.codex/hooks.json`, `~/.gemini/settings.json`, `~/.cursor/hooks.json`) et le script `agent-hook.sh` (Application Support, jeton), qui relaie le JSON au même serveur (`/notchkit/agent/hook`, en-tête `X-Notchkit-Agent`). `AgentHookTranslator` traduit leurs événements en événements de Claude Code (session préfixée `codex:`, `gemini:`, `cursor:` ; `CodingAgent.of(sessionID:)`) et les réponses vers leur format (Gemini CLI et Cursor attendent toujours du JSON). Seuls Claude Code et Codex acceptent une décision depuis l'encoche ; Codex n'exécute un nouveau hook qu'après `/hooks` (approbation de l'utilisateur). Aucun de ces trois agents n'était installé sur la machine de dev : vérifié par tests et par de vrais hooks envoyés au script (05/11/2026).
- **Commande `notchkit`** (`Modules/Scripts/`) : script shell (`ScriptCommandInstaller`, lien dans `/opt/homebrew/bin`, `/usr/local/bin` ou `~/.local/bin`) qui envoie un formulaire (`curl --data-urlencode`) au serveur du module Commandes (port 52732, son propre jeton) : `notify`, `start`, `progress`, `end`, `run`. Bannière sous l'encoche `ScriptBanner` (`NotchLayout.scriptBannerSize`). Les liens `notchkit://activity/…` des Activités en direct existent aussi.
- **Capot fermé** (`Modules/LidAwake/`, 4.0) : garde le Mac éveillé capot fermé (interrupteur, agents au travail via `ClaudeModule.tracker.hasActiveSession` + délai calme, `notchkit awake` et `notchkit run --awake`). La veille est coupée par l'assistant système `NotchkitAwakeHelper` (cible `Helper/`, `pmset -a disablesleep`, `pmset sleepnow`), démon lancé par launchd via `SMAppService.daemon` après l'accord de l'utilisateur (Réglages Système > Général > Ouverture) ; échanges XPC (`AwakeHelperProtocol`, exigence de signature : identifiant + certificat « Notchkit Self-Signed » en Release, identifiant seul en Debug). Sécurités (`LidAwakePolicy`, testées) : seuil de batterie, chaleur capot fermé (`thermalState` ≥ serious), débranchement en option, durée ; à la fin, capot fermé (`AppleClamshellState`), le Mac est endormi. L'assistant rétablit la veille à son lancement et dès que Notchkit se déconnecte (vérifié par un plantage simulé, `NOTCHKIT_AWAKE_PROBE=install|status|toggle|crash`). Ne jamais appeler `sleepNow` dans un essai automatisé capot ouvert.
- **Partage** : `NotchkitProfile` (fichier `.notchkit` : widgets, disposition, apparence, mascotte ; type `com.andeolchenaux.notchkit.profile` déclaré dans `project.yml`), exporté et importé depuis Disposition, ou ouvert d'un double clic (`AppDelegate.application(_:open:)`). « Filmer l'encoche » (menu de la barre des menus) : `NotchClipRecorder`, H.264, 30 s au plus, zone `NotchLayout.clipRegion`, dans Vidéos › Notchkit.
- **Réglages** : `AppSettings` (généraux) ; un réglage propre à un module vit dans le module (`UserDefaults`, clé `module.<id>.<nom>`). Fenêtre : `UI/Settings/SettingsView.swift` (onglets `SettingsTab`, `SettingsRouter`, icônes `SidebarIcon` lues dans `AppleIconAppearanceTheme`).
- **Debug** : `App/Debug/` — captures (`SnapshotRenderer`) et mode démo (`NOTCHKIT_DEMO=scenario.json`, `DemoDirector`) qui joue un scénario sur la vraie encoche et la filme (utilisé par la skill `notch-video`).
- **Tests** : mise en page et bulles dans `ModuleManagerTests` (`NotchLayoutTests`) et `BubbleControlsTests`.

## Comportements et pièges connus

Leçons apprises : **ne pas réessayer** ce qui est marqué comme tel.

- **Glisser-déposer** : le serveur de fenêtres ne livre pas le glisser à une fenêtre de l'espace SkyLight. `DropCatcher` (fenêtre invisible du bureau ordinaire, même cadre) le reçoit et héberge le contenu le temps du glisser. Déplacer la fenêtre vers le bureau courant (`SLSGetActiveSpace`) n'a aucun effet : ne pas réessayer. Un fichier glissé hors de l'encoche passe par `NSItemProvider.file(at:)` (sinon le Finder crée « Image PNG.png »). Les glissers internes sont refusés, sauf la source `AcceptedInternalDragSource` (tutoriel).
- **Liquid Glass** : net seulement dans la fenêtre clé. L'encoche devient fenêtre clé à l'ouverture et la rend à la fermeture (`NotchWindowController.updateKeyStatus`) ; ne pas poser `becomesKeyOnlyIfNeeded`. Le propriétaire veut le verre de macOS, jamais un verre dessiné. Au-dessus de l'écran verrouillé, aucun verre ni flou ne voit le fond : ne pas réessayer `glassEffect`, `NSGlassEffectView`, `NSVisualEffectView`.
- **Fond Verre** : noir en haut, dégradé vers un Liquid Glass `.clear`, congés 20 pt et coins 36 pt (`NotchLayout.earRadius` / `cornerRadii`, aussi pour le fond Noir, qui garde son contour). Fonds disponibles : Noir et Verre. À faire : revoir certains widgets pensés pour une carte noire (contrastes, débordements).
- **Taille de l'encoche ouverte** : suit les widgets de la page (`NotchLayout.expandedHeight(sizes:)` : 150 / 190 / 222 pt ; largeur `NotchLayout.pageSize` : 140 pt par unité de poids, 4 unités au plus). Lecteur de musique toujours en première page, hors disposition (`playerPage`, `MusicPlayerStyle` Grand 456 × 200 ou Compact 384 × 168).
- **Pages** : balayage géré à la main (`PageSwipe`) — le défilement par pages de SwiftUI restait bloqué, ne pas y revenir. Plus d'indicateur de pages (pas la place à côté de la caméra) : ne pas le remettre.
- **Largeur repliée** : la largeur de la musique sert partout, sauf volume / luminosité (`levelIndicatorSideWidth`), alertes qui écrivent un mot (`NotchAlert.withTextSides()`, 90 pt), rappels de Santé (120 pt) et images par seconde du mode jeu (`frameRateSideWidth`). Une alerte garde sa largeur en partant et a sa propre identité (`.id(alert.id)`).
- **Priorités** : la musique en lecture (`media`) passe devant les activités en cours ; seule une info urgente (`high`, minuteur qui sonne) la relègue en bulle. Une demande d'autorisation de Claude Code reste dans une bulle cerclée d'ambre (Autoriser / Refuser au survol, ouverture au clic) et n'ouvre pas l'encoche. Une nouvelle question (AskUserQuestion) l'ouvre sur la page Agents (`AgentsModule.opensForQuestion`).
- **Bulles** : la colonne des bulles ne doit pas avoir de `contentShape` (elle limiterait les clics des commandes qui débordent).
- **Écran verrouillé** : `NotchViewModel.isScreenLocked` ; seules les activités repliées restent visibles, sans aucune interaction — toute nouvelle interaction doit respecter ce verrou. Seule exception : le lecteur (`LockScreenPlayer.swift` : « Grand lecteur » par défaut, fenêtre `LockScreenMediaWindow` ; « Dans l'encoche », qui s'élargit sans descendre ; ou « Aucun »). Un lecteur sorti de « À l'écoute » en pause (Deezer, navigateurs) ne reçoit plus de commande : « lecture » par MediaRemote ouvre Apple Music, ne pas réessayer ; ses boutons sont grisés.
- **Changement de bureau** : au balayage du trackpad, macOS gèle l'affichage de l'encoche ~1 s (limite de macOS, non corrigeable ; `activeSpaceDidChange` arrive à la fin). Une alerte affichée est prolongée de 1,1 s. Les vidéos Face ID / Touch ID passent par une couche ordinaire (`VideoHostView`) : une AVPlayerLayer décroche au changement de bureau.
- **Fenêtres réglages et tutoriel** : icône dans le Dock tant qu'elles sont ouvertes (`setActivationPolicy(.regular)`), `moveToActiveSpace`, fenêtre clé réclamée jusqu'à l'obtenir (`WindowActivation`). La fenêtre des réglages reçoit son titre à la création et retient son cadre (`NSWindow Frame NotchkitSettings`).
- **Étagère et convertisseur** : fichier gardé 5 minutes (`ShelfModule.retention`), redéposé = repart en tête ; un dépôt sur le convertisseur s'ajoute aux fichiers de la même famille (`ConverterModule.merged`). Après un dépôt sur « Convertir », `expand(showing:)` choisit la page lui-même, et une sortie de survol annoncée par AppKit pendant que le pointeur est encore sur la fenêtre est ignorée.
- **Volume et luminosité** : le niveau glisse vers le cran suivant en 0,2 s (`LevelRamp`) ; la barre se remplit proportionnellement (`NotchLayout.barFillWidth`).
- **Tutoriel** (`App/Onboarding/`) : démos animées par images clés (`TimelineView`, une seule horloge ; avec `PhaseAnimator`, les éléments se décalaient). Un contenu retiré pendant que l'encoche de démo rétrécit laisse un rectangle fantôme : superposer les contenus plutôt que les retirer. Essai guidé sur la vraie encoche (`OnboardingTrialTask`).
- **Haptique** (`Haptics`) : `.tap` (geste), `.step` (cran), `.snap` (alignement). Les alertes ne vibrent pas.
- **Accessibilité (HIG)** : texte de 10 pt au moins, opacité 0,55 au moins sur noir, `.accessibilityLabel` sur chaque bouton à icône seule, boucles décoratives arrêtées si `NotchAccessibility.reduceMotion`. Les boutons qui précèdent une demande d'autorisation système s'appellent « Demander l'accès… ».
- **Abandonné, ne pas refaire** : discussion avec la mascotte (19/10/2026), intégration à Siri par App Intents (21/10/2026), ancrage des fenêtres, widgets Git / GitHub / Ollama, services Vercel / Stripe, True Tone et notifications avec réponse (API privées). Le module assistant IA est masqué (code dans `Modules/Assistant`).
- **Limites** : pas de suivi des téléversements des autres apps ; convertisseur sans sortie MP3 ni WebP, sans lecture WebM ni MKV, PDF sans les images intégrées.

## Conventions de code

- **Modules** : une classe `<Nom>Module` conforme à `NotchModule`, avec un `descriptor` statique (`id` en minuscules, ex. `"music"`), enregistrée dans `ModuleRegistry.allModules`. Vues : `<Nom>ExpandedView`, `<Nom>MiniView`, `<Nom>SettingsView`. Drapeaux du descripteur :
  - `providesWidget = false` : module sans widget ;
  - `contextual = true` + `hasContextualContent` : tourne toujours et s'affiche en dernière page tant qu'il a du contenu (Étagère, Captures) ;
  - `backgroundEvents = true` : animations venues du système, tourne même widget désactivé (Batterie, AirPods, HUD) ;
  - nouveaux widgets masqués par défaut (`defaultEnabled: false`).
- **Tailles de widget** : `WidgetSize` `.mini` / `.small` / `.medium` / `.large` (poids 0,5 / 1 / 1,5 / 2), lu avec `@Environment(\.widgetSize)`. Les vues tiennent dans toutes les tailles, à leur propre largeur ; préférer `ViewThatFits` aux cadres fixes. Aucun texte coupé par « … ».
- **Constantes de mise en page et ressorts** : dans `NotchLayout`, en fonctions statiques pures et testées. Pas de nombres magiques dans les vues.
- **Style StandBy** : `.buttonStyle(.standBy(size, active:, circle:))`, `StandByBar`, `StandBySlider`, `StandBy.surface/amber/defaultAccent`, `.notchCard()`. L'accent vient de `.tint`, le texte posé dessus de `@Environment(\.onAccent)`. L'ambre est réservé aux états qui demandent l'attention.
- **Localisation** : sept langues depuis le 05/11/2026 (français source `sourceLanguage: fr`, anglais, espagnol, allemand, japonais, chinois simplifié `zh-Hans`, portugais du Brésil `pt-BR`). Les builds en ligne de commande ne synchronisent pas le catalogue : ajouter chaque clé dans toutes les langues via `scripts/add-strings.py fichier.json` (objet `{ "français": { "en": …, "es": …, "de": …, "ja": …, "zh-Hans": …, "pt-BR": … } }` ; `--catalog Notchkit/Resources/InfoPlist.xcstrings` pour Info.plist). `LocalizationTests` échoue s'il manque une langue. Attention aux textes anglais partagés par deux clés françaises (« Location » = Emplacement et Localisation) : traduire depuis le français.
- **Exécutions automatisées** : tout ce qui sollicite l'utilisateur (capture audio, presse-papiers, mises à jour) est ignoré quand `AutomatedRun.isActive`.
- **Tests** : structs Swift Testing, noms en phrases françaises en camelCase (`bullesZoneSepareeDeLEncoche`). Extraire la logique en fonctions pures.
- **Réglages** : tout nouveau réglage a une valeur par défaut et un décodage tolérant (`decodeIfPresent` + repli) ; `AppSettings` décode chaque clé avec `try?`.

## Commandes fréquentes

À lancer depuis la racine du dépôt avec `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
xcodegen generate                                   # après toute modification de project.yml ou ajout/suppression de fichiers

xcodebuild build -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'

xcodebuild test -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'   # chercher « TEST SUCCEEDED »

sh scripts/stress.sh                                # stress test (Debug) : 200 cycles, affiche STRESS-OK

# Captures (Debug) : rend l'UI en PNG puis quitte ; les vues AppKit passent par `saveWindow`
NOTCHKIT_SNAPSHOT=/chemin/vers/dossier build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit

# Banc d'essai visuel sur la vraie encoche (mode démo, Notchkit quitté) : scenarios, record, analyze, spaces…
python3 scripts/visual-matrix.py <commande>       # voir l'en-tête du script

# Journal de l'espace SkyLight (/usr/bin/log : sous zsh, « log » est une commande interne)
/usr/bin/log show --last 10m --predicate 'subsystem == "com.andeolchenaux.notchkit" AND category == "espace"'

# Forcer une langue : ajouter  -AppleLanguages "(en)"
```

### Publication

1. Augmenter `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, `xcodegen generate`, tests et stress test, committer `Version x.y.z`. Si Xcode a réécrit les `.xcstrings` (métadonnées seulement), les committer à part (« Sync string catalogs with Xcode ») ou les mettre de côté pendant la publication (`git stash push -- Notchkit/Resources/*.xcstrings`).
2. Build universel :
   `xcodebuild -project Notchkit.xcodeproj -scheme Notchkit -configuration Release -derivedDataPath build.noindex/Release -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO build`
3. Vérifier `codesign -dvv <app>` (Authority=Notchkit Self-Signed), puis **lancer l'app Release** (`<app>/Contents/MacOS/Notchkit`) et vérifier qu'elle tourne encore après quelques secondes (les tests passent par le Debug et ne voient pas un échec de chargement propre au Release ; 1.0.1 et 1.0.2 ont été publiées cassées). Puis `scripts/make-dmg.sh <app> build.noindex/dist`.
4. Notes de version en anglais dans `build.noindex/dist/notes-x.y.z.md`, puis `scripts/add-to-appcast.sh build.noindex/dist/Notchkit-x.y.z.dmg <app> <notes.md>` (signe le DMG avec la clé EdDSA du trousseau et ajoute l'entrée en tête de `appcast.xml`).
5. Mettre `appcast.xml` de côté (`git stash push -- appcast.xml`), `git push`, `git tag -a vx.y.z`, pousser le tag, `gh release create vx.y.z <dmg> --verify-tag --latest --notes-file <notes.md>` (en cas d'erreur 408, la release peut disparaître : la recréer avec `--verify-tag`), puis `git stash pop`, committer « Add x.y.z to the appcast » et pousser. Flux : `https://raw.githubusercontent.com/Mycate39/Notchkit/main/appcast.xml`.

**Bêta / RC** : `MARKETING_VERSION` `x.y.z-beta.N` ou `x.y.z-rc.N`, `gh release create … --prerelease --latest=false`. `add-to-appcast.sh` la met dans le canal Sparkle « beta », proposé seulement à qui a activé « Recevoir les versions bêta » (Réglages > Général). Les versions finales, sans canal, vont à tout le monde.

**Clés à ne jamais perdre** : le certificat « Notchkit Self-Signed » (le remplacer ferait perdre aux utilisateurs leurs autorisations à la mise à jour) et la clé privée Sparkle (« Private key for signing Sparkle updates », remplacée au build 12 : les entrées sont marquées informatives pour les builds 11 et antérieurs). Sauvegarde chiffrée `Notchkit-sauvegarde.dmg` dans iCloud Drive › NotchKit et ailleurs ; mots de passe dans l'app Mots de passe. À refaire si l'un d'eux change.

## État (10 novembre 2026)

- Dernière version : **3.1.0** (`v3.1.0`, build 36, 10/11/2026), gratuite ; l'abonnement viendra plus tard. L'historique détaillé est dans les releases GitHub et `git log`.
- 3.0 : design Verre, encoche à la taille de ses widgets, lecteur de musique en première page, grand lecteur de l'écran verrouillé, traducteur, canal bêta. 3.0.1 : barre du volume proportionnelle. 3.0.2 : vignettes arrondies, alertes qui partent entières. 3.0.3 : l'encoche s'ouvre sur une question de Claude Code.
- 3.1.0 : agents Codex, Gemini CLI et Cursor, commande `notchkit`, partage de configuration, « Filmer l'encoche », cinq nouvelles langues (espagnol, allemand, japonais, chinois simplifié, portugais du Brésil).
- Vérifiés seulement par tests et captures, pas en usage réel : lecture AX, détection de projet Terminal.
- Animations de déverrouillage : « Apple Face ID » (Mau Ali) et « Fingerprint Touch ID » (Himanshu Patel), Lottie Simple License (usage commercial permis), créditées dans le README.

## Vidéos de présentation

Tout est dans `.claude/skills/notch-video/projet.md` (projet, films, musique, diffusion) ; méthode de tournage dans la skill `notch-video`.
