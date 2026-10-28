/// Android implementation of the update-install flow: download the
/// release APK into the app cache, then hand the file to Android's
/// package installer (OpenFilex builds the ACTION_VIEW install intent
/// with a FileProvider so the URI is openable by the system installer).
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'package:music_player/services/app_updater.dart';

Future<bool> downloadAndPromptApk(
  RemoteRelease release, {
  void Function(double)? onProgress,
}) async {
  final apkUrl = release.apkUrl;
  if (apkUrl == null) return false;
  File? file;
  try {
    final dir = await getTemporaryDirectory();
    file = File(
      '${dir.path}/update_${release.version.replaceAll('.', '_')}.apk',
    );
    // An already downloaded copy of this release's APK is reused whole,
    // so retrying an update (cancelled install prompt, failed open)
    // goes straight to the installer instead of re-downloading ~50MB.
    if (await file.exists()) {
      final cachedLength = await file.length();
      final sizeOk = (release.apkSize == null)
          ? cachedLength >= 512 * 1024
          : cachedLength == release.apkSize;
      if (sizeOk) {
        if (onProgress != null) onProgress(1.0);
        final result = await OpenFilex.open(
          file.path,
          type: 'application/vnd.android.package-archive',
        );
        return result.type == ResultType.done;
      }
      // Stale/partial copy from another attempt - re-download.
      try {
        await file.delete();
      } catch (_) {}
    }
    final dio = Dio();
    await dio.download(
      apkUrl,
      file.path,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
    final length = await file.length();
    // Anything under half a megabyte is not a real APK - most likely an
    // HTML error page from a misconfigured release. Refuse + clean up.
    if (length < 512 * 1024) {
      await file.delete();
      file = null;
      return false;
    }
    if (onProgress != null) onProgress(1.0);
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    return result.type == ResultType.done;
  } catch (_) {
    // A partially downloaded file is never useful.
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {}
    }
    return false;
  }
}
