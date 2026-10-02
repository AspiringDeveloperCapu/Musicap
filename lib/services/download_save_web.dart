import 'dart:js_interop';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

/// `window.showDirectoryPicker` — not yet exposed by package:web.
@JS('window.showDirectoryPicker')
external JSPromise<web.FileSystemDirectoryHandle> _showDirectoryPicker();

/// Property read used to feature-detect the API without calling it
/// (reading an undefined JS property yields null instead of throwing).
@JS('window.showDirectoryPicker')
external JSFunction? _showDirectoryPickerProperty;

const _kDirLabel = 'downloads.dirLabel';

/// Directory granted for this browser session.
web.FileSystemDirectoryHandle? _directory;

/// Whether we already prompted for a folder this session (cancel sticks
/// until restart so we don't nag on every download).
bool _askedThisSession = false;

/// Whether the File System Access API is available (Chromium browsers).
bool get directoryPickerSupported => _showDirectoryPickerProperty != null;

/// Ensures a save directory is available before the first download of the
/// session, opening the folder picker if needed. If the user cancels,
/// downloads continue to the browser's default download folder.
Future<void> ensureDirectoryForDownload() async {
  if (_directory != null || _askedThisSession) return;
  _askedThisSession = true;
  await pickDirectory();
}

/// Opens the system folder picker. Returns the folder name, or null when
/// the user cancels or the API isn't available.
Future<String?> pickDirectory() async {
  if (!directoryPickerSupported) return null;
  try {
    final handle = await _showDirectoryPicker().toDart;
    _directory = handle;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDirLabel, handle.name);
    return handle.name;
  } catch (_) {
    // Cancelled (AbortError) or unsupported — caller falls back.
    return null;
  }
}

/// Display name of the chosen folder. Persisted for display across
/// sessions; the write permission itself lasts for the session, so a fresh
/// pick is requested on the first download after a reload.
Future<String?> directoryLabel() async {
  if (_directory != null) return _directory!.name;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kDirLabel);
}

/// Web implementation: writes the file directly into the user-chosen
/// directory (File System Access API). Falls back to a normal browser
/// download when no directory is granted. Returns the in-folder path label
/// on success, null for the browser-download fallback.
Future<String?> saveFile(List<int> bytes, String filename) async {
  final dir = _directory;
  if (dir != null) {
    try {
      final fileHandle = await dir
          .getFileHandle(filename, web.FileSystemGetFileOptions(create: true))
          .toDart;
      final writable = await fileHandle.createWritable().toDart;
      await writable.write(Uint8List.fromList(bytes).toJS).toDart;
      await writable.close().toDart;
      return '${dir.name}/$filename';
    } catch (_) {
      // Permission lost or write failed — fall through to a browser download.
      _directory = null;
    }
  }

  final jsBytes = Uint8List.fromList(bytes).toJS;
  final blob = web.Blob(
    [jsBytes].toJS,
    web.BlobPropertyBag(type: 'audio/mpeg'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Delay revoking so the browser has time to start the download.
  Future.delayed(const Duration(seconds: 10), () {
    web.URL.revokeObjectURL(url);
  });
  return null;
}

/// The browser can't stat files — trust the persisted download history.
bool fileExists(String path) => true;

Future<void> deleteFile(String path) async {}
