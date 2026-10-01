import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web implementation: triggers a real browser download (Blob + anchor).
/// Returns null because the browser saves the file (no app-side path).
Future<String?> saveFile(List<int> bytes, String filename) async {
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
  web.URL.revokeObjectURL(url);
  return null;
}

bool fileExists(String path) => false;

Future<void> deleteFile(String path) async {}
