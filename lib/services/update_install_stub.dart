/// Platform-specific tail of the in-app update flow.
///
/// Default implementations for platforms without APK installs
/// (web/desktop): the io variant does the real work on Android.
library;

import 'package:music_player/services/app_updater.dart';

/// Downloads and opens Android's installer for [release]'s APK.
///
/// Progress is reported through [onProgress] (0.0..1.0) while the APK
/// is downloading; the returned future completes directly after the
/// installer prompt has been launched, before the user finishes in it.
///
/// Returns true when the download succeeded and the installer prompt
/// launched; false when the platform can't install updates, the
/// download failed, or the served file wasn't a plausible APK.
Future<bool> downloadAndPromptApk(
  RemoteRelease release, {
  void Function(double)? onProgress,
}) async {
  return false;
}

/// Total bytes of the cached update APK files (0 when none).
Future<int> updateApkCacheSize() async => 0;

/// Deletes every cached update APK file. Returns the bytes freed.
Future<int> clearUpdateApkCache() async => 0;
