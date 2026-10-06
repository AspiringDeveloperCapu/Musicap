import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kSaveDirKey = 'downloads.saveDir';

/// User-chosen save directory, persisted across launches.
Future<String?> _preferredDir() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kSaveDirKey);
}

/// Default folder inside the app documents directory.
Future<String> _defaultDirPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'Musicap');
}

/// IO implementation: writes the file into the chosen save directory
/// (or the default app folder when the user hasn't picked one).
Future<String?> saveFile(List<int> bytes, String filename) async {
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

/// Folder picker available on Android, Windows, macOS, Linux, iOS.
bool get directoryPickerSupported => true;

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
Future<String?> directoryLabel() async =>
    await _preferredDir() ?? await _defaultDirPath();
