import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

Future<void> probe(
  YoutubeExplode yt,
  String id,
  String label, {
  bool browserUa = false,
  bool identity = false,
  bool referer = false,
  bool origin = false,
}) async {
  final m = await yt.videos.streamsClient.getManifest(id);
  final a = m.audioOnly;
  final u = a.where((s) => !s.isThrottled);
  final p = (u.isNotEmpty ? u : a).withHighestBitrate();
  final url = p.url.toString();
  final client = HttpClient()..autoUncompress = false;
  try {
    var current = Uri.parse(url);
    int? code;
    for (var hop = 0; hop <= 6; hop++) {
      final req = await client.getUrl(current);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-999999999');
      if (browserUa) req.headers.set(HttpHeaders.userAgentHeader, ua);
      if (identity) {
        req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      }
      if (referer) req.headers.set(HttpHeaders.refererHeader, 'https://www.youtube.com/');
      if (origin) req.headers.set('Origin', 'https://www.youtube.com');
      final resp = await req.close();
      code = resp.statusCode;
      if (code >= 300 && code < 400) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        await resp.drain<void>();
        if (loc == null) break;
        current = current.resolve(loc);
        continue;
      }
      await resp.drain<void>();
      break;
    }
    print('$label -> $code');
  } finally {
    client.close(force: true);
  }
}

Future<void> main() async {
  final yt = YoutubeExplode();
  const id = 'fuSzR-wmC1M';
  await probe(yt, id, 'baseline (Dart UA)');
  await probe(yt, id, 'browser UA', browserUa: true);
  await probe(yt, id, 'UA + identity', browserUa: true, identity: true);
  await probe(yt, id, 'UA + identity + referer + origin',
      browserUa: true, identity: true, referer: true, origin: true);
  await probe(yt, id, 'identity only', identity: true);
  yt.close();
}
