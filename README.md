# Anigen

**Anigen** is an ad-free anime client for Android, Windows and macOS, built with Flutter. Its scraping logic is ported from [`ani-cli`](https://github.com/pystardust/ani-cli). Titles, artwork and tracking come from [AniList](https://anilist.co).

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
  <img src="https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="macOS" />
</p>

> [!IMPORTANT]
> Anigen does not host, store, upload or distribute any video files or other media. Read the [disclaimer](#disclaimer) before using it.

---

## Features

- **Browse**: a hero carousel, the top 10, continue watching, airing now, new this season, most popular, top movies, coming soon and genre categories.
- **Search**: results as you type, with filters for sort, format, status, year and genres.
- **Title pages**: synopsis, score, genres, studio, recommendations and the full episode list, with AniList status, progress and score editing.
- **My list**: favourites and watch progress saved on your device, with resume from where you left off.
- **AniList sync**: sign in with AniList to view your lists and update your progress as you watch.
- **Player**: built on MPV via [media_kit](https://github.com/media-kit/media-kit). It has subtitles, playback speed, double-tap seeking, hold to speed up, and autoplay of the next episode.
- **Skip intro**: opening and ending timestamps from [AniSkip](https://api.aniskip.com).
- **Remote scraper config**: the source site's settings load from this repo, so a site change can be fixed without a new release.
- **Large screens**: layouts for tablets and desktop windows.
- **Updates**: the app tells you when a new release is out. Android installs it from inside the app; on Windows and macOS the notice opens the release page.
- **No ads, no accounts required, no tracking.**

---

## Install

Download the latest build from [Releases](https://github.com/ruck-syu/Anigen/releases/latest).

| Platform | File | Notes |
| --- | --- | --- |
| Android | `Anigen-vX.Y.Z-arm64-v8a.apk` | For 64-bit ARM phones and tablets. Allow installs from unknown sources. Later updates can be installed from settings. |
| Windows | `Anigen-vX.Y.Z-windows-x64-setup.exe` | SmartScreen may warn that the app isn't recognised. Choose **More info → Run anyway**. |
| macOS | `Anigen-vX.Y.Z-macos.dmg` | Universal build (Apple silicon and Intel). Drag the app to Applications. The app isn't notarised, so the first launch is blocked: open **System Settings → Privacy & Security** and choose **Open Anyway**. |

---

## Building from source

Requirements:

- Flutter **3.44.2**, pinned in `.fvmrc`. Use [fvm](https://fvm.app) or install that version yourself.
- For Android: Java 17 and the Android SDK.
- For Windows: Visual Studio with the "Desktop development with C++" workload.
- For macOS: Xcode.

```bash
git clone --recurse-submodules https://github.com/ruck-syu/Anigen.git
cd Anigen
fvm flutter pub get

fvm flutter run                                              # debug, on a connected device
fvm flutter build apk --release --target-platform=android-arm64
fvm flutter build windows --release
fvm flutter build macos --release
```

### Android signing (optional)

Android only installs an update if it is signed with the same key as the installed app. Without a key, release builds use the debug key. To use your own key, create `android/key.properties`:

```properties
storeFile=release.jks          # relative to android/
storePassword=...
keyAlias=...
keyPassword=...
```

`key.properties` and the keystore are gitignored. **Never commit them.** Keep a backup: if the key is lost, installed copies can't be updated.

### Releases

Every push to `main` runs [`.github/workflows/release.yml`](.github/workflows/release.yml). It builds Android, Windows and macOS and publishes them as a single GitHub release.

- The version is `vMAJOR.MINOR.PATCH`. `MAJOR.MINOR` comes from `pubspec.yaml`, and the patch is one more than the newest tag in that series.
- To start a new series, bump the minor (or major) version in `pubspec.yaml`.
- The Android versionCode is derived from the version (`1.6.2` → `1060002`), so it always increases.
- CI signs Android builds with the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` repository secrets.

---

## Tech stack

- [Flutter](https://flutter.dev) and Dart
- [media_kit](https://github.com/media-kit/media-kit): MPV-based playback
- [AniList GraphQL API](https://docs.anilist.co): metadata, lists and tracking
- [AniSkip API](https://api.aniskip.com): intro and outro timestamps
- `http` and `html`: scraping
- `shared_preferences` and `flutter_secure_storage`: local library and AniList sign-in

---

## Credits

- **[ani-cli](https://github.com/pystardust/ani-cli)**: the inspiration, and the scraping logic Anigen ports.
- **[AniList](https://anilist.co)**: anime metadata, artwork and list tracking.
- **[AniSkip](https://github.com/lexesjan/typescript-aniskip-extension)**: community intro and outro timestamps.
- **[media_kit](https://github.com/media-kit/media-kit)**: the playback engine.
- **[JetBrains Mono](https://www.jetbrains.com/lp/mono/)** and **[Bebas Neue](https://github.com/dharmatype/Bebas-Neue)**: fonts, bundled under the SIL Open Font License (see `assets/fonts`).

Anigen is not affiliated with, endorsed by or sponsored by any of the projects, services or sites above.

---

## Disclaimer

**Anigen does not host any content.** No video files, subtitles or other media are hosted, stored, uploaded, cached or distributed by Anigen or its developers, on this repository or anywhere else.

- **How it works.** Like a web browser or a search engine, Anigen only finds and plays links that third-party websites already make publicly available on the internet. Streams load directly from those sites to your device. Anigen has no control over what those sites host, and can't verify whether they are licensed.
- **Copyright.** All anime, artwork, titles, logos and trademarks belong to their respective copyright owners. Metadata and artwork come from AniList and remain the property of their owners.
- **No affiliation.** Anigen is an independent, non-commercial, open-source project. It is not affiliated with any anime studio, publisher, distributor, streaming service, AniList or the sites it links to.
- **Your responsibility.** You are responsible for how you use Anigen and for complying with the copyright laws where you live. If accessing such content is not legal in your country, don't use this app. The developers accept no liability for misuse.
- **Copyright holders / DMCA.** Anigen hosts no files, so there is nothing to take down here. Send takedown notices to the websites and hosting providers that actually host the content. For any other concern about this repository, [open an issue](https://github.com/ruck-syu/Anigen/issues).
- **Purpose.** This project is for educational and personal use. It is provided "as is", without any warranty.

**Please support the creators.** If you enjoy a show, watch it on an official, licensed service and buy official merchandise and releases.
