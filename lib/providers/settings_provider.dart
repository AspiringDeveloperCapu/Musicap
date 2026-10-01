import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Immutable app settings. Persisted to shared_preferences so they survive
/// app restarts.
class SettingsState {
  final ThemeMode themeMode;
  final double playbackSpeed;
  final String region;
  final String language;
  final bool loaded;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.playbackSpeed = 1.0,
    this.region = 'US',
    this.language = 'en',
    this.loaded = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    double? playbackSpeed,
    String? region,
    String? language,
    bool? loaded,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      region: region ?? this.region,
      language: language ?? this.language,
      loaded: loaded ?? this.loaded,
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController() : super(const SettingsState()) {
    _load();
  }

  static const _kTheme = 'settings.themeMode';
  static const _kSpeed = 'settings.playbackSpeed';
  static const _kRegion = 'settings.region';
  static const _kLanguage = 'settings.language';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      themeMode: _themeFromString(prefs.getString(_kTheme)),
      playbackSpeed: prefs.getDouble(_kSpeed) ?? 1.0,
      region: prefs.getString(_kRegion) ?? 'US',
      language: prefs.getString(_kLanguage) ?? 'en',
      loaded: true,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, mode.name);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    state = state.copyWith(playbackSpeed: speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSpeed, speed);
  }

  Future<void> setRegion(String region) async {
    state = state.copyWith(region: region);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRegion, region);
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, language);
  }

  static ThemeMode _themeFromString(String? value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  return SettingsController();
});
