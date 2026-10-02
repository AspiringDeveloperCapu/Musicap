# Android Support

Branch: `android-support`

This document describes the changeset that makes Musicap shippable as an
Android APK with background playback, plus the related fixes bundled into
the same branch.

## 1. Android platform support

### Manifest (`android/app/src/main/AndroidManifest.xml`)

| Change | Why |
|---|---|
| `INTERNET` permission | Required for all backend/media traffic on Android. |
| `android:usesCleartextTraffic="true"` | The backend is plain HTTP on the LAN (`http://192.168.1.11:5000`); Android blocks cleartext by default. |
| `android:label="Musicap"` | App name. |
| `WAKE_LOCK` permission | `audio_service`'s `AudioService.enterPlayingState()` acquires a partial wake lock before `startForeground()`. The package ships an **empty** `AndroidManifest.xml`, so apps must declare it themselves. Without it, a `SecurityException` killed the foreground transition and the media notification never appeared. |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK` | Required to run the media playback foreground service on API 34+. |

### MainActivity (`android/app/src/main/kotlin/.../MainActivity.kt`)

`MainActivity` now extends `com.ryanheise.audioservice.AudioServiceActivity`.
Using the plain `FlutterActivity` made `AudioServicePlugin` throw
`wrongEngineDetected` during `AudioService.init`, which aborted `main()` before
`runApp` — the app hung on the splash screen.

### Background playback / media notification

`audio_service` was initialized but never connected to actual playback, so
Android showed no notification and audio died in the background. The handler's
player is now the app's real player:

- **`lib/audio_handler.dart`**
  - Top-level `musicAudioHandler` holds the handler returned by
    `AudioService.init` (null on web/Windows/desktop, where nothing changes).
  - Playback events are piped into `playbackState` (drives the system media
    session / notification controls).
  - The current `MediaItem` is re-synced from the playing track's tag on both
    `sequenceStream` and `currentIndexStream` — either can fire first during a
    load; relying on `currentIndexStream` alone silently dropped the metadata
    (notification showed "Musicap is running / null").
  - Defensive tag read: tags that are not `MediaItem`s become `null` instead
    of throwing a cast error.
- **`lib/features/player/player_controller.dart`**
  - `AudioPlayerController` now uses `musicAudioHandler?.player ?? AudioPlayer()`
    so the UI, queue logic, and the media session all drive one player.
  - A `_ownsPlayer` flag guards `dispose()` — the handler's shared player is
    never disposed by the controller.
  - `AudioSource` tags are full `MediaItem`s (id/title/artist/duration/artUri)
    instead of bare track-id strings, which is what the notification renders.
- **`lib/main.dart`**
  - `AudioService.init` runs inside try/catch — a failure degrades to "no
    notification" instead of bricking startup.
  - Config: channel `Musicap`, `androidNotificationOngoing: true`,
    `androidStopForegroundOnPause: true` (service leaves the foreground when
    paused, stays alive while playing).

### Release-build resource keep rules (`android/app/src/main/res/raw/keep.xml`)

The resource shrinker strips `audio_service_*` drawables because they are only
referenced from Dart-side strings (`'drawable/audio_service_stop'`), which the
shrinker cannot see. In release builds every `setState()` then crashed with
`IllegalArgumentException: You must specify an icon resource id to build a
CustomAction`, killing the notification entirely (debug builds were unaffected).
`keep.xml` adds `tools:keep="@drawable/audio_service_*"`.

## 2. Backend server configuration (LAN usage)

- **`lib/services/music_api.dart`** — hardcoded `baseUrl` replaced by
  `defaultServerUrl`:
  - web: `http://<page-host>:5000` (works for localhost dev, the PC's LAN IP
    when opened from a phone, and the backend-served production build),
  - Android: `http://192.168.1.11:5000` (the PC on the LAN),
  - desktop: `http://localhost:5000`.
  - `musicApi.setServerUrl()` normalizes input (adds scheme, strips trailing
    slashes).
- **`lib/providers/settings_provider.dart`** — the chosen URL is persisted
  (`settings.serverUrl`) and re-applied on native startup (web derives the host
  from the page URL instead).
- **`lib/main.dart`** — Settings gains a **Server** section with a
  **Backend Address** dialog (hidden on web).

## 3. Genre detail content

- **`lib/models/genre.dart`** — new `GenreContent` (directly playable songs +
  playlists to browse) replaces the playlists-only model.
- **`lib/providers/music_provider.dart`** — `genrePlaylistsProvider` →
  `genreContentProvider` backed by `musicApi.getGenreContent()`.
- **`lib/features/genres/genre_detail_page.dart`** — renders playable songs
  and playlist rows for a genre/mood.

## 4. Web download folder picker

- **`lib/services/download_save_web.dart`** — `pickDirectory()` /
  `directoryLabel()` / `ensureDirectoryForDownload()` using the File System
  Access API; the first download of a session can prompt for a folder, with a
  fallback to a plain browser download when the user cancels or permission is
  lost.
- **`lib/services/download_save_io.dart` / `download_save_stub.dart`** —
  matching counterparts for desktop/other platforms.
- **`lib/providers/download_manager.dart`** — triggers the folder prompt before
  the first download of a session.

## 5. Shared horizontal row widget

- **`lib/widgets/horizontal_row.dart` (new)** — extracted section widget with
  title, edge chevron buttons and an always-visible scrollbar so content past
  the right edge stays reachable with a mouse (wheel scrolling alone only moves
  vertically on the web).

## 6. Formatting-only changes

Parts of `playlist_detail_page.dart`, `downloads_page.dart`, and related files
are re-wrapped by `dart format`; no behavior change.

## Verification

- `flutter analyze` — 0 errors (80 pre-existing info-level notes).
- `flutter test` — 4/4 passing.
- `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`
  (~54.5 MB, signed with the debug key — fine for sideloading).
- Emulator end-to-end (release build):
  - search and playback through the LAN backend (`/api/search`, `/api/stream` 200/206),
  - media notification with track metadata (MediaStyle, 3 transport actions,
    `startForegroundCount=1`),
  - background playback verified via HOME key — position keeps advancing and
    the notification persists,
  - Settings → Server shows the Backend Address tile,
  - no exceptions in logcat.
