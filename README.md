# Musicap

A cross-platform music player built with Flutter. Features queue management, playlist creation, search, downloads, and a polished UI with mini player.

## Features

- **Playback controls** — Play, pause, next, previous, shuffle, repeat
- **Queue management** — Add, remove, and reorder tracks in the queue
- **Playlists** — Create, rename, delete playlists; add/remove tracks
- **Search** — Search through tracks and playlists
- **Downloads** — Download tracks for offline listening with progress tracking
- **Mini player** — Persistent bottom bar with playback controls and navigation
- **Settings** — Theme toggle, playback speed, clear downloads, in-app updates
- **In-app updates** — Check for updates and install new versions right from Settings
- **Responsive UI** — Works on web, mobile, and desktop

## Install (Android)

No Play Store needed — install the APK directly from GitHub Releases:

1. **Download the APK**
   - Open the [Releases page](https://github.com/AspiringDeveloperCapu/Musicap/releases)
   - On the latest release, download the `Musicap-vX.X.X.apk` asset

2. **Allow installs from your browser**
   - Android will warn the first time you install outside the Play Store
   - When prompted, tap **Settings** → enable **Allow from this source**
   - (or: Settings → Apps → Special access → Install unknown apps → allow your browser)

3. **Install**
   - Open the downloaded APK and tap **Install**
   - Or run `adb install -r Musicap-vX.X.X.apk` from a computer

### Existing users

Already have Musicap installed? You don't need GitHub:

- Open **Settings → Check for updates** — Musicap detects a new version on GitHub Releases, downloads it in-app, and hands it to the Android installer automatically
- Cached update files can be removed anytime via **Settings → Clear update cache**

### Build from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install):

```bash
git clone https://github.com/AspiringDeveloperCapu/Musicap.git
cd Musicap
flutter pub get
flutter run          # run on a connected device/emulator
flutter build apk    # or build a release APK yourself
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart) |
| State Management | Flutter Riverpod |
| Audio Playback | just_audio |
| Background Audio | audio_service |
| HTTP Client | dio |
| Unique IDs | uuid |

## Project Structure

```
lib/
├── main.dart                          # App entry, dashboard, settings
├── audio_handler.dart                 # Background audio service
├── models/
│   └── track.dart                     # Track & Playlist models
├── providers/
│   ├── music_provider.dart            # Music data & search
│   ├── playlist_manager.dart          # Playlist CRUD
│   └── download_manager.dart          # Download management
└── features/
    ├── player/
    │   ├── player_controller.dart     # Audio playback & queue logic
    │   ├── player_page.dart           # Full player screen
    │   ├── mini_player.dart           # Persistent mini player bar
    │   └── download_bar.dart          # Download panel
    ├── search/
    │   └── search_page.dart           # Search functionality
    ├── playlist/
    │   ├── playlist_page.dart         # Library tab
    │   └── playlist_detail_page.dart  # Playlist detail view
    └── downloads/
        └── downloads_page.dart        # Downloads tab
```

## Author

**Aaron Jacob Capulong**
- GitHub: [AspiringDeveloperCapu](https://github.com/AspiringDeveloperCapu)

## Disclaimer

This project was developed with AI assistance.
