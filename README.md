<p align="center">
  <a href="https://cisum.studio"><img src="https://www.cisum.studio/app.jpg" alt="cisum" width="120"></a>
</p>
<h1 align="center">cisum</h1>
<p align="center">
  <b>The music app your phone needs.</b> Ad-free, open source, with vinyl at the heart of its design.
  <br/><br/>
  <a href="https://cisum.studio"><b>cisum.studio</b></a> ·
  <a href="https://testflight.apple.com/join/xDWsYvE1">TestFlight (iOS)</a> ·
  <a href="https://discord.gg/Mb4F9Gmuex">Discord</a>
</p>

<!-- Screenshots: add docs/screenshots/{ios,macos,android}.png, then remove this comment wrapper.
<table>
  <tr>
    <th>iOS</th>
    <th>macOS</th>
    <th>Android</th>
  </tr>
  <tr>
    <td><img src="docs/screenshots/ios.png" width="220"></td>
    <td><img src="docs/screenshots/macos.png" width="420"></td>
    <td><img src="docs/screenshots/android.png" width="220"></td>
  </tr>
</table>
-->

## Why cisum

- **Bring your own library.** Connect Spotify, Apple Music, Tidal, Deezer or Qobuz.
- **Bit-perfect, highest-quality audio.**
- **Offline-first playback.**
- **Fast.** Cold tap-to-audio dropped from 1.2s+ to under 500 ms, and cached tracks start in about 200 ms.
- **No ads, free and open source.**
- **300+ users** so far.

## Features

- Search, Home and Discover, plus Albums, Artists, Playlists and your Library
- Radio
- Lyrics, with a Lock Screen **Live Activity**
- **cisum Rechords**, your listening recap
- **Plugins**: install sources from a registry, so new providers don't need an app update
- A **vinyl-record shell** on macOS

## Architecture

The Apple app is a set of Swift packages, and each package's job fits in one sentence:

```
Modules/
  Core/        composition root: wires providers, plugins and playback together
  Features/    one package per screen or capability (Player, PlaybackCore, Plugins, Search, Rechords, …)
  Shared/      Models, Networking, Caching, Catalog, Aesthetics (UI components), Utilities
Packages/
  StreamingKit (submodule)
```

- **Enforced boundaries.** `scripts/check-boundaries.sh` fails the build when a package imports something it shouldn't. For example, the Player can't know that plugins exist, and plugins can't compose the playback chain. Core is the only place where things get wired together.
- **Playback resolution.** For each track, `PlaybackResolver` collects candidate streams from the available sources, ranks them, and works down a fallback ladder within a time budget.
- **Swift Concurrency throughout.** Plugin storage and the registry client are actors.
- Built on my own SDKs: [StreamingKit](https://github.com/cisumapp/StreamingKit), [SpotifySDK](https://github.com/cisumapp/SpotifySDK), [LyricsKit](https://github.com/cisumapp/LyricsKit), [RadioKit](https://github.com/cisumapp/RadioKit), [AirbudsKit](https://github.com/cisumapp/AirbudsKit) and [YouTubeSDK](https://github.com/atpugvaraa/YouTubeSDK).

## Building (iOS 17+ / macOS 14+)

```sh
git clone --recurse-submodules https://github.com/cisumapp/cisum.git
open cisum.xcworkspace
```
