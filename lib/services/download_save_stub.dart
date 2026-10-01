/// Non-web fallback: nothing can be persisted.
Future<String?> saveFile(List<int> bytes, String filename) async => null;

bool fileExists(String path) => false;

Future<void> deleteFile(String path) async {}
