import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// IO implementation: writes the file into the app documents directory.
Future<String?> saveFile(List<int> bytes, String filename) async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'Musicap'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

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

/// Desktop uses the fixed app folder — no directory picker needed.
bool get directoryPickerSupported => false;

Future<String?> pickDirectory() async => null;

Future<void> ensureDirectoryForDownload() async {}

/// The folder downloads are written to (shown in Settings).
Future<String?> directoryLabel() async {
  final docs = await getApplicationDocumentsDirectory();
  return p.join(docs.path, 'Musicap');
}
