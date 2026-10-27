import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSaveDirKey = 'downloads.saveDir';

/// Method channel to MainActivity's MediaStore save path.
const _channel = MethodChannel('music_player/local_audio');

/// User-chosen save directory, persisted across launches.
Future<String?> _preferredDir() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSaveDirKey);
}

/// Default folder inside the app documents directory (desktop fallback).
Future<String> _defaultDirPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'Musicap');
}

String _mimeTypeFor(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.mp3')) return 'audio/mpeg';
  if (lower.endsWith('.m4a')) return 'audio/mp4';
  if (lower.endsWith('.ogg')) return 'audio/ogg';
  if (lower.endsWith('.flac')) return 'audio/flac';
  if (lower.endsWith('.wav')) return 'audio/wav';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

/// IO implementation: on Android writes into the public Download/Musicap
/// folder via MediaStore (visible to file managers, no scoped-storage
/// denial). On desktop writes into the chosen save directory (or the
/// default app folder when the user hasn't picked one).
Future<String?> saveFile(List<int> bytes, String filename) async {
  if (Platform.isAndroid) {
    try {
      return await _channel.invokeMethod<String>('saveToDownloads', {
        'filename': filename,
        'bytes': Uint8List.fromList(bytes),
        'mimeType': _mimeTypeFor(filename),
      });
    } catch (_) {
      // MediaStore failed (device quirk) — fall through to the private
      // app folder so the download itself still succeeds.
    }
  }
  final base = await _preferredDir() ?? await _defaultDirPath();
  final dir = Directory(base);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Cover art is written next to the audio file in the same save directory.
Future<String?> saveArtFile(List<int> bytes, String filename) =>
    saveFile(bytes, filename);

bool fileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

Future<void> deleteFile(String path) async {
  try {
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (_) {
    // Best effort — file may already be gone.
  }
}

/// Folder picker: Android's scoped storage makes picked raw paths
/// unwritable, so the picker is desktop-only. Android always uses
/// the fixed public Download/Musicap folder.
bool get directoryPickerSupported => !Platform.isAndroid;

Future<String?> pickDirectory() async {
  try {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose download folder',
    );
    if (dir == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSaveDirKey, dir);
    return dir;
  } catch (_) {
    // Unsupported surface or picker error — caller keeps the current folder.
    return null;
  }
}

Future<void> ensureDirectoryForDownload() async {}

/// The folder downloads are written to (shown in Settings).
Future<String?> directoryLabel() async {
  if (Platform.isAndroid) return 'Download/Musicap';
  return await _preferredDir() ?? await _defaultDirPath();
}
