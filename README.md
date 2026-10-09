# Notchkit

Turn your Mac's notch into a living space: music, timers, battery, weather, calendar,
clipboard, a file shelf, and live Claude Code activity, right at your cursor. No notch?
Notchkit shows a floating pill instead, or simulates a notch.

> Found a bug or have an idea? Please open an issue in the *Issues* tab.

https://github.com/user-attachments/assets/805f5594-03e0-49f6-a223-b9498daf1901

## Features

- **Music**: the current track (Apple Music, Spotify, and most players, including in the
  browser), artwork, controls, bars that react to the sound, and a Dynamic Island–style look.
- **Volume and brightness**: an indicator in the notch instead of the macOS one.
- **AirPods and headphones**: an animation on connect, and the battery of Bluetooth devices.
- **Timers**: any duration, iPhone-style.
- **Battery, clock, weather** (Open-Meteo), and **calendar**.
- **Clipboard**: searchable history and pinned items.
- **Shelf and AirDrop**: drop files on the notch to keep them or send them.
- **Claude Code**: what Claude is doing and saying, live, remaining usage, and the ability
  to write to Claude from the notch.
- **Video downloads** (with yt-dlp, installed on demand).
- **Unlock animations** and trackpad haptic feedback.
- **Customization**: widgets in several sizes, pages, ready-made layouts, notch size,
  animations, colors, and background (including Liquid Glass on macOS 26).

Notchkit is available in English and French, following your Mac's language.

## Installation

1. Download `Notchkit-x.y.z.dmg` from the [Releases](../../releases) page and open it.
2. Drag **Notchkit.app** onto the **Applications** shortcut.
3. First launch: Notchkit isn't notarized by Apple yet, so macOS blocks it once.
   **Right-click the app > Open**, or go to **System Settings > Privacy & Security** and
   click **Open Anyway**.

Notchkit updates itself: it checks for a new version once a day and installs it with your approval (you can also use **Check for Updates…** in its menu).

Notchkit lives in the menu bar (no Dock icon). Open the settings from its menu bar icon or
from the gear in the notch.

### Requirements

- macOS 14 Sonoma or later (Liquid Glass: macOS 26).
- Apple silicon or Intel Mac, with or without a notch, one or more displays.

### Permissions

Notchkit only asks for a permission when a feature needs it: Accessibility (volume and
brightness keys), Calendars, Location (weather), and System Audio Recording (music-reactive
bars). Nothing is sent over the internet, except weather requests (Open-Meteo) and the
yt-dlp download if you install it.

## Building from source

Requirements: Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Notchkit.xcodeproj
```

## Notes

Some features rely on unofficial macOS interfaces (reading the current track from any app,
built-in display brightness). A macOS update may break them; Notchkit then falls back to
public interfaces.

## License

© 2026 Andéol Chenaux. All rights reserved: the source code is published for viewing only
(see [LICENSE](LICENSE)). The app is free for personal use.
Third-party components: [MediaRemoteAdapter](ThirdParty/MediaRemoteAdapter) (BSD 3-Clause).
