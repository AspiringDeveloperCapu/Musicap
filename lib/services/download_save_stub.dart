/// Non-web fallback: nothing can be persisted.
Future<String?> saveFile(List<int> bytes, String filename) async => null;

Future<String?> saveArtFile(List<int> bytes, String filename) async => null;

bool fileExists(String path) => false;

Future<void> deleteFile(String path) async {}

/// No directory picker on this platform.
bool get directoryPickerSupported => false;

Future<String?> pickDirectory() async => null;

Future<void> ensureDirectoryForDownload() async {}

Future<String?> directoryLabel() async => null;
