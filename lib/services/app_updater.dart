import 'dart:convert';

import 'package:dio/dio.dart';

/// In-app update check against the app's GitHub Releases.
///
/// The app is fully serverless, so GitHub doubles as the distribution
/// channel: publish a release on GitHub (tag + release notes + the built
/// APK) and every installed copy can detect it, download the new APK
/// and hand it to Android's installer - no backend required.
///
/// The network check lives here in portable Dart so it can be imported
/// everywhere; the download/open-installer step is platform-specific
/// and comes in through update_install.dart's conditional import.
class AppUpdater {
  AppUpdater._();

  static const _repo = 'AspiringDeveloperCapu/Musicap';

  static const currentVersion = '1.1.0';

  /// A semver-ish comparison: "1.2" / "1.2.0" / "v1.2.1" all parse.
  /// Returns true when [candidate] is strictly newer than [current].
  static bool isNewer(String candidate, String current) {
    final a = _semver(candidate);
    final b = _semver(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] > b[i]) return true;
      if (a[i] < b[i]) return false;
    }
    return false;
  }

  static List<int> _semver(String v) {
    final cleaned =
        v.trim().replaceFirst(RegExp('^v', caseSensitive: false), '');
    final parts = cleaned.split(RegExp(r'[.\-+]'));
    return [
      for (var i = 0; i < 3; i++)
        i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    ];
  }

  /// Tag minus the leading v: "v1.2.3" -> "1.2.3".
  static String semverNormalized(String tag) =>
      tag.trim().replaceFirst(RegExp('^v', caseSensitive: false), '');

  /// Asks GitHub for the latest (non-prerelease) release. Returns null
  /// when the check couldn't run (offline, rate limited, no releases).
  static Future<RemoteRelease?> checkLatest() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/vnd.github+json'},
      ));
      final response = await dio
          .get('https://api.github.com/repos/$_repo/releases/latest')
          .timeout(const Duration(seconds: 15));
      final data = (response.data is String)
          ? jsonDecode(response.data as String) as Map<String, dynamic>
          : response.data as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) return null;

      // The APK asset to offer the user (ignore other attachments).
      String? apkUrl;
      String? apkName;
      int? apkSize;
      for (final asset in (data['assets'] as List<dynamic>? ?? const [])) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String?;
        if (url != null && name.toLowerCase().endsWith('.apk')) {
          apkUrl = url;
          apkName = name;
          apkSize = (asset['size'] as num?)?.toInt();
          break;
        }
      }
      return RemoteRelease(
        tag: tag,
        version: semverNormalized(tag),
        name: data['name'] as String? ?? tag,
        notes: _cleanNotes(data['body'] as String? ?? ''),
        apkUrl: apkUrl,
        apkName: apkName,
        apkSize: apkSize,
        pageUrl: data['html_url'] as String? ??
            'https://github.com/$_repo/releases',
      );
    } catch (_) {
      return null;
    }
  }

  /// Release notes minus GitHub's noise lines; truncated for a dialog.
  static String _cleanNotes(String body) {
    final lines = body
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.contains('full changelog'))
        .map((l) => l.trim())
        .toList();
    final text = lines.join('\n').trim();
    if (text.length <= 400) return text;
    return '${text.substring(0, 400)}...';
  }
}

/// The latest release as GitHub reports it.
class RemoteRelease {
  const RemoteRelease({
    required this.tag,
    required this.version,
    required this.name,
    required this.notes,
    required this.apkUrl,
    required this.apkName,
    required this.apkSize,
    required this.pageUrl,
  });

  final String tag;
  final String version;
  final String name;
  final String notes;
  final String? apkUrl;
  final String? apkName;

  /// Size in bytes of the release APK, as reported by GitHub; used to
  /// verify that a previously downloaded copy is still the real asset.
  final int? apkSize;
  final String pageUrl;

  bool hasApk() => apkUrl != null;
}
