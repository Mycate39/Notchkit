# MediaRemoteAdapter (third-party code)

- Source: https://github.com/ungive/mediaremote-adapter
- Commit: 29718252613a5b0e210bdc64de0bd944ab379706 (September 30, 2026)
- License: BSD 3-Clause (see `LICENSE.txt`), compatible with commercial use.
- Included: `bin/mediaremote-adapter.pl`, `include/`, `src/` (in `src/test`, only `NowPlayingTest.h` is kept because `test.m` includes it). No modifications.

## Purpose

Reads the current track (macOS "Now Playing") and controls playback in any app
(Deezer, browsers…) through the private MediaRemote framework.
Since macOS 15.4, only an entitled system binary (`/usr/bin/perl`) can use it:
the script loads the framework into Perl and writes updates as JSON to its output.

⚠️ Private API: Apple may break this mechanism with any macOS update.
Notchkit then automatically falls back to Music and Spotify (public APIs).

## Updating

Replace `bin/`, `include/`, and `src/` with the new version (in `src/test`, keep only `NowPlayingTest.h`),
update the commit above, then run `xcodegen generate`.
