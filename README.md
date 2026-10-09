# Musicap

A cross-platform music player built with Flutter. Features queue management, playlist creation, search, downloads, and a polished UI with mini player.

## Features

- **Playback controls** — Play, pause, next, previous, shuffle, repeat
- **Queue management** — Add, remove, and reorder tracks in the queue
- **Playlists** — Create, rename, delete playlists; add/remove tracks
- **Search** — Search through tracks and playlists
- **Downloads** — Download tracks for offline listening with progress tracking
- **Mini player** — Persistent bottom bar with playback controls and navigation
- **Settings** — Theme toggle, playback speed, clear downloads
- **Responsive UI** — Works on web, mobile, and desktop

## Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart) |
| State Management | Flutter Riverpod |
| Audio Playback | just_audio |
| Background Audio | audio_service |
| HTTP Client | dio |
| Unique IDs | uuid |

## Getting Started

### Prerequisites
- Flutter SDK
- Dart SDK ^3.13.2

### Run the app
```bash
flutter pub get
flutter run -d chrome    # for web
flutter run              # for desktop/mobile
```

### Build for web
```bash
flutter build web
```

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
