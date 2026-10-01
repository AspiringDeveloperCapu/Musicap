import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:music_player/models/track.dart';
import 'package:music_player/providers/settings_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track serialization', () {
    test('toJson/fromJson round trip preserves fields', () {
      const track = Track(
        id: 'abc123',
        title: 'Test Song',
        artist: 'Test Artist',
        imageUrl: 'https://example.com/art.jpg',
        audioUrl: 'http://localhost:5000/api/stream/abc123',
        videoId: 'abc123',
      );

      final restored = Track.fromJson(track.toJson());

      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.imageUrl, track.imageUrl);
      expect(restored.audioUrl, track.audioUrl);
      expect(restored.videoId, track.videoId);
    });
  });

  group('Playlist serialization', () {
    test('toJson/fromJson round trip preserves tracks', () {
      const playlist = Playlist(
        id: 'p1',
        name: 'My Mix',
        tracks: [
          Track(
            id: 'a',
            title: 'One',
            artist: 'Artist A',
            audioUrl: 'http://localhost:5000/api/stream/a',
            videoId: 'a',
          ),
          Track(
            id: 'b',
            title: 'Two',
            artist: 'Artist B',
            audioUrl: 'http://localhost:5000/api/stream/b',
            videoId: 'b',
          ),
        ],
      );

      final restored = Playlist.fromJson(playlist.toJson());

      expect(restored.id, playlist.id);
      expect(restored.name, playlist.name);
      expect(restored.tracks.length, 2);
      expect(restored.tracks[0].title, 'One');
      expect(restored.tracks[1].videoId, 'b');
    });
  });

  group('Settings persistence', () {
    test('defaults are US/en/system/1.0', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = SettingsController();
      await Future.delayed(Duration.zero);

      final state = controller.state;
      expect(state.loaded, isTrue);
      expect(state.region, 'US');
      expect(state.language, 'en');
      expect(state.themeMode, ThemeMode.system);
      expect(state.playbackSpeed, 1.0);
    });

    test('values persist across controller instances', () async {
      SharedPreferences.setMockInitialValues({});

      final first = SettingsController();
      await Future.delayed(Duration.zero);
      await first.setThemeMode(ThemeMode.dark);
      await first.setRegion('PH');
      await first.setLanguage('ja');
      await first.setPlaybackSpeed(1.5);

      // Simulate app restart with a fresh controller.
      final second = SettingsController();
      await Future.delayed(Duration.zero);

      expect(second.state.themeMode, ThemeMode.dark);
      expect(second.state.region, 'PH');
      expect(second.state.language, 'ja');
      expect(second.state.playbackSpeed, 1.5);
    });
  });
}
