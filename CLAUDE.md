# Notchkit

Native macOS app that turns the notch (or a floating pill on Macs without one) into a live area:
music, timers, battery, weather, calendar, clipboard, file shelf, Claude Code activity, video downloads.
Menu bar app (`LSUIElement`), distributed outside the Mac App Store, not sandboxed.

## Tech stack

| Item | Version |
|---|---|
| Swift | 6.0 language mode (`SWIFT_VERSION: "6.0"`), compiler 6.2.4 |
| Xcode | 26.3 (17C528) — set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (`xcode-select` points to the Command Line Tools) |
| UI | SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Observation (`@Observable`) |
| Minimum macOS | 14.0 (Liquid Glass background only on macOS 26) |
| Project generation | XcodeGen 2.44.1 — `project.yml` is the source of truth, never edit `Notchkit.xcodeproj` by hand |
| Tests | Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`) |
| Dependencies | Sparkle 2.10.0 (SPM, MIT) for automatic updates; MediaRemoteAdapter (vendored in `ThirdParty/`, BSD 3-Clause) |
| Architectures | Universal (x86_64 + arm64); dev machine is an Intel MacBook Pro 2017 without a notch |
| Signing | Ad hoc (`CODE_SIGN_IDENTITY: "-"`) with Hardened Runtime; not notarized |

## Hard rules

- **No GPL code** (e.g. Boring Notch, FaceMac): inspiration only, never copy.
- **Public APIs only**, except the private APIs already accepted: MediaRemote (via MediaRemoteAdapter) and DisplayServices (built-in display brightness). Ask before adding any other private API.
- **HomeKit is out** (`HMHomeManager` is unavailable on native macOS). Home control, if ever, goes through the Shortcuts app (`shortcuts run`).
- **Never kill every Notchkit process** (`pkill -x Notchkit`): the owner runs an instance from Xcode. Only stop test instances under `build.noindex/DerivedData/Build/Products`.
- Test instances share the real `UserDefaults` domain (`com.andeolchenaux.notchkit`): clean up any key a test writes.
- Commit only after the build, the tests **and** the stress test pass. Commit messages in English; the repository owner is the sole author (no co-author trailers).
- Everything on GitHub is in English (README, release notes, commits). Code comments are in French.

## Folder architecture

```
Notchkit/
  App/            Entry point, AppDelegate, menu bar menu, Updater (Sparkle), Debug/ (snapshot renderer)
  Core/
    Modules/      NotchModule protocol, ModuleDescriptor, ModuleManager, ModuleRegistry (list of modules)
    State/        NotchViewModel (expand/collapse, hover, bubbles), NotchLayout (all sizes and springs), NotchAlert
    Window/       NotchPanel, NotchWindowController, NotchHostingView (hover zones), ScreenLocator, MenuBarAvoidance
    Layout/       WidgetLayout (pages, sizes), LayoutPresets
    Settings/     AppSettings, NotchAppearance, SettingsStore (tolerant decoding), LaunchAtLogin
    Drop/ Licensing/ Utilities/ (AutomatedRun, Haptics, ObservationTracking)
  Modules/<Name>/ One folder per module: <Name>Module.swift (+ <Name>Views.swift, helpers)
  UI/             NotchContainerView, NotchShape, NotchStyle (StandBy buttons, bars, slider, cards),
                  Glyphs, ModuleIcon, Settings/ (settings window and tabs)
  Resources/      Localizable.xcstrings, InfoPlist.xcstrings, Assets.xcassets (AppIcon), entitlements,
                  Info.plist (generated from project.yml)
NotchkitTests/    Swift Testing suites, one file per area
ThirdParty/       MediaRemoteAdapter (see PROVENANCE.md)
scripts/          AppIcon.swift (draws the icon), make-dmg.sh, add-to-appcast.sh
appcast.xml       Sparkle update feed (read by the app from the main branch)
build.noindex/    Build output, git-ignored; ".noindex" keeps Spotlight from listing the Debug app
```

## Code conventions

- **Modules**: a class `<Name>Module` conforming to `NotchModule`, with a static `descriptor` (lowercase `id` such as `"music"`, `"activities"`), `compactPriority`, `compactLeading()/compactTrailing()`, `expandedView()`, `miniView()`, `settingsView()`. Register it in `ModuleRegistry.allModules`. Views are named `<Name>ExpandedView`, `<Name>MiniView`, `<Name>SettingsView`. A background-only module sets `descriptor.providesWidget = false`.
- **Widget sizes**: `WidgetSize` is `.mini`, `.small`, `.medium`, `.large` (weights 0.5 / 1 / 1.5 / 2), read with `@Environment(\.widgetSize)`. Views must fit every size and every notch size (`NotchAppearance.Size`); prefer `ViewThatFits` to fixed frames.
- **Layout constants and springs** live in `NotchLayout` as pure, tested static functions. Do not scatter magic numbers in views.
- **Style**: StandBy look — `.buttonStyle(.standBy(size, active:, circle:))`, `StandByBar`, `StandBySlider`, `StandBy.surface/amber/onAccent`, `.notchCard()`. The accent color (default amber) comes from `.tint`.
- **Localization**: source strings are French (`sourceLanguage: fr`), English is the development language. Command-line builds do **not** sync the catalog: add every new key to `Localizable.xcstrings` by hand with **both** `en` and `fr` (`state: translated`). `LocalizationTests` fails if the two tables differ.
- **Automated runs**: anything that could prompt the user (audio capture, clipboard, updates) is skipped when `AutomatedRun.isActive`.
- **Tests**: Swift Testing structs; test names are French camelCase sentences (`bullesZoneSepareeDeLEncoche`). Extract logic into pure functions so it can be tested without UI.
- **Settings**: new settings get a default and tolerant decoding (`decodeIfPresent` + fallback) so older settings files keep loading.

## Frequent commands

Run from the repository root with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
xcodegen generate                                   # after any change to project.yml or new/removed files

xcodebuild build -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'

xcodebuild test -project Notchkit.xcodeproj -scheme Notchkit \
  -derivedDataPath build.noindex/DerivedData -destination 'platform=macOS'   # look for "TEST SUCCEEDED"

# Stress test (Debug only): 200 expand/collapse cycles, prints STRESS-OK in the log
NOTCHKIT_STRESS=1 build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit \
  -module.claude.port 52799

# Snapshots (Debug only): renders the UI to PNG files, then quits
NOTCHKIT_SNAPSHOT=/path/to/folder build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit

# Force a language: append  -AppleLanguages "(en)"
```

### Release

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen generate`, test, commit `Version x.y.z`.
2. Universal build:
   `xcodebuild -project Notchkit.xcodeproj -scheme Notchkit -configuration Release -derivedDataPath build.noindex/Release -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO build`
3. `scripts/make-dmg.sh build.noindex/Release/Build/Products/Release/Notchkit.app <out-dir>`
4. `scripts/add-to-appcast.sh <out-dir>/Notchkit-x.y.z.dmg <app> <notes.md>` — signs the DMG with the EdDSA private key stored in the login Keychain ("Private key for signing Sparkle updates"; never delete it) and prepends the item to `appcast.xml`. Commit `appcast.xml`.
5. `git push`, `git tag -a vx.y.z`, push the tag, `gh release create vx.y.z <dmg> --prerelease --notes-file <notes.md>`.
   The feed URL is `https://raw.githubusercontent.com/Mycate39/Notchkit/main/appcast.xml`.

## Status (October 2026, version 0.1.6)

### Working
- Notch window on any screen: real notch, simulated notch, or floating pill; stays put across Spaces; shifts right so it never covers the active app's menus (needs Accessibility permission).
- Compact activities (Dynamic Island style for the pill), mini notches for other activities, stacked menu that unfolds on hover, separate hover zones, Dynamic Island–style outline while an activity is shown or the notch is expanded.
- Expanded notch with pages and widgets in four sizes, layout editor, ready-made layouts, custom notch size, StandBy-style controls, accent color, Liquid Glass background (macOS 26).
- Modules: Music (MediaRemote + Music/Spotify fallback, reactive equalizer, AirPlay), Clock, Battery, Calendar, Weather (Open-Meteo), Claude Code (live activity, messages, usage, reply from the notch), Shelf + AirDrop, AirPods/Bluetooth battery, Live Activities (timers, downloads, tasks, `notchkit://` URLs), Clipboard, Volume/Brightness HUD, Unlock animations, Video downloads (yt-dlp installed on demand).
- English and French, following the Mac's language.
- Automatic updates with Sparkle, DMG distribution, app icon.

### Not verified yet / known limits
- First real Sparkle update (0.1.5 → next version) has not happened yet.
- Real AX menu reading, Liquid Glass rendering and some animations were only checked through snapshots, not on a real notch.
- App is not notarized (users must right-click > Open the first time).
- The AI assistant module is hidden (code kept in `Modules/Assistant`, re-enable in `ModuleRegistry`).

### Roadmap (v0.2, proposed order)
1. Performance: signposts around expand/collapse, Instruments (SwiftUI, Animation Hitches, Energy); suspects are the materialize blur, the shadow during resizing, and window resizing during the spring.
2. Third-party widgets: declarative `widget.json` + script folder in Application Support, rendered with the StandBy components (no dynamic Swift code loading).
3. Home control through the Shortcuts app.
