import 'dart:io';

/// Checks whether [url] is actually being served.
///
/// YouTube's CDN sometimes answers 403 for stream URLs it has silently
/// revoked: the manifest still returns them, but playback fails at the
/// network layer and shows up as a track that "resolved" fine yet never
/// produces sound. An open-ended ranged GET (capuTune-style) asks for
/// the response headers only — no body is consumed — so the probe is a
/// handful of bytes instead of any real stream data.
///
/// Explicit failures (403/404/410, i.e. the server answered and said
/// no) make the URL dead; transport errors (timeouts, drops) do NOT —
/// if the network were actually down playback would fail regardless,
/// and re-extracting the manifest on every flaky connection would turn
/// a transient glitch into an unnecessary YouTube request.
Future<bool> probeUrl(String url) async {
  HttpClient? client;
  try {
    client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    final request = await client.openUrl('GET', Uri.parse(url));
    request.headers.set('Range', 'bytes=0-');
    final response = await request.close();
    await response.listen(null).cancel();
    final status = response.statusCode;
    return status == 200 || status == 206;
  } catch (_) {
    // Network trouble, or a URL scheme dart:io can't open (backend
    // relative paths) — give the URL the benefit of the doubt.
    return true;
  } finally {
    client?.close();
  }
}
