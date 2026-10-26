# Notchkit

Turn your Mac's notch into a living space: music, timers, battery, weather, calendar,
clipboard, a file shelf, and live Claude Code activity, right at your cursor. No notch?
Notchkit shows a floating pill instead, or simulates a notch.

> Found a bug or have an idea? Please open an issue in the *Issues* tab.

https://github.com/user-attachments/assets/e3e6bf6a-735d-4323-a4ff-8d78ff44c057

## Features

**Music and media**
- **Music**: the current track (Apple Music, Spotify, Deezer, and most players, including in
  the browser), artwork, controls, and bars that react to the sound, in an iPhone Live Activity
  style. When nothing plays, the player stays in place with dimmed controls.
- **Music on the lock screen**: when your Mac is locked, the notch widens with the current
  song, its artwork, the sound bars and playback controls.
- **Volume and brightness**: an indicator in the notch instead of the macOS one, including
  changes from the Touch Bar and Control Center, with a sound center: output, microphone,
  and the volume of each app.
- **AirPods and Bluetooth**: an animation on connect, and the battery of each device.
- **Webcam**: a quick mirror to check how you look before a meeting.
- **Full-screen videos**: the notch hides while a video plays in full screen (YouTube,
  Netflix, QuickTime…), then comes back.

**Live Activities, like on iPhone**
- The current activity sits around the notch, outlined in its color. Other activities become
  bubbles next to it: hover a bubble to control it without opening the notch (play, pause,
  next track, pause or stop a timer).
- **Timers** set with a ruler, like on iOS, with a haptic tick at every minute, plus a
  stopwatch, alarms, Pomodoro, downloads and task progress.

**System**
- **Game Mode**: when a game goes full screen, the notch steps aside and only shows the
  frame rate.
- **Quick Toggles**: Dark Mode, stay awake, hide desktop icons, and a keyboard lock to clean it.
- **System Monitor**: CPU per core, GPU, memory, disk, network speed, battery health, and heavy processes.
- **Battery**: percentage, time remaining, and while charging, the time left until full and
  when it will be full (optionally as a live activity next to the notch).

**Files and clipboard**
- **Shelf and AirDrop**: drop files or text on the notch to keep them for 5 minutes, send
  them with AirDrop, compress them, or copy them to iCloud Drive.
- **Convert**: drop images, audio, videos, documents or PDFs on the notch to change their format.
- **Screenshots**: the screenshots and screen recordings of your session, ready to drag anywhere.
- **Clipboard**: searchable history and pinned items.

**Time and organization**
- **Calendar, weather** (Open-Meteo) **and clock**.
- **Reminders**: check off and add reminders from the notch.
- **Notes**: a scratchpad one hover away.
- **Day progress**: how far along your workday you are.
- **Dashboard**: your favorite apps and your Mac at a glance.
- **Screen Time** and **Health**: time spent per app, break and hydration reminders, and
  activity rings, all measured on your Mac only.
- **Translation**: French ↔ English, on device (macOS 15 or later).

**For developers**
- **Agents**: a full page that follows Claude Code live, with its steps, the file it edits
  and the terminal. Answer its permission requests and questions right from the notch. A
  mascot, chosen among 33, keeps it company.

**And more**
- **Video downloads** (with yt-dlp, installed on demand): pick any resolution the video
  offers, up to 4K, and get an MP4 that plays in QuickTime on every Mac. Most YouTube videos
  need [ffmpeg](https://ffmpeg.org): `brew install ffmpeg deno`.
- **Face ID and Touch ID animations** when your Mac unlocks or asks for Touch ID, like the
  Dynamic Island.
- **Trackpad haptics**, following Apple's guidelines.
- **Customization**: widgets in several sizes, pages, ready-made layouts, notch size,
  animations, colors, and background (including Liquid Glass on macOS 26). New widgets
  are off by default: turn them on in Settings.
- **Made for the real notch**: it matches the hardware notch exactly, keeps the active app's
  menus visible around it, and stays out of the way when you move to the menu bar.
- **Accessible**: readable text, VoiceOver labels, and calmer animations with Reduce Motion.
- **A guided tutorial** on first launch, which ends with a short trial on your real notch.

Everything is free and runs on your Mac: no account, no paid service.

Notchkit is available in English and French, following your Mac's language.

## Installation

1. Download `Notchkit-x.y.z.dmg` from the [Releases](../../releases) page and open it.
2. Drag **Notchkit.app** onto the **Applications** shortcut.
3. First launch: Notchkit isn't notarized by Apple yet, so macOS blocks it once.
   **Right-click the app > Open**, or go to **System Settings > Privacy & Security** and
   click **Open Anyway**.

Notchkit updates itself: it checks for a new version once a day and installs it with your approval (you can also use **Check for Updates…** in its menu).

> **Coming from Notchkit 1.0.2 or earlier?** Those versions can't update themselves to the
> current one (Notchkit is now signed with new keys): download the latest DMG once and
> replace the app. From 1.0.0 or earlier, also give the **Accessibility** permission again.

Notchkit lives in the menu bar (no Dock icon). Open the settings from its menu bar icon or
from the gear in the notch. You can hide the menu bar icon: open Notchkit again from the
Finder to get back to the settings.

### Requirements

- macOS 14 Sonoma or later (Liquid Glass: macOS 26).
- Apple silicon or Intel Mac, with or without a notch, one or more displays.

### Permissions

Notchkit only asks for a permission when a feature needs it:

- **Accessibility**: volume and brightness keys, and keeping the notch clear of the active
  app's menus.
- **Calendars** and **Reminders**, **Location** (weather), **Camera** (Webcam widget),
  **System Audio Recording** (music-reactive bars), **Screen Recording** (Game Mode frame
  rate; nothing is recorded), and **Automation** (controlling Music and Spotify, Dark Mode).

Notchkit has no account and no analytics. It only goes online for weather (Open-Meteo),
update checks (GitHub), and the yt-dlp tool and videos you choose to download.

## Building from source

Requirements: Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Notchkit.xcodeproj
```

## Notes

Some features rely on unofficial macOS interfaces (reading the current track from any app,
built-in display brightness, staying visible on the lock screen). A macOS update may break
them; Notchkit then falls back to public interfaces.

## License

© 2026 Andéol Chenaux. All rights reserved: the source code is published for viewing only
(see [LICENSE](LICENSE)). The app is free for personal use.
Third-party components: [MediaRemoteAdapter](ThirdParty/MediaRemoteAdapter) (BSD 3-Clause).
