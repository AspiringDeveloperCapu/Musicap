/// Web stub for [probeUrl]: no dart:io client exists on the web, and
/// stream URLs there come from the backend, which validates ranges
/// itself — report every URL as alive so probing stays a no-op.
Future<bool> probeUrl(String url) async {
  return true;
}
