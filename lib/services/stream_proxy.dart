import 'dart:async';
import 'dart:io';

/// Loopback relay that normalizes byte-range requests for YouTube's CDN.
///
/// googlevideo rejects open-ended ranges (`bytes=start-`) and requests
/// without a Range header with HTTP 403, while ExoPlayer/just_audio emit
/// exactly those for loading and seeking. The player therefore streams
/// through this local server, which converts every incoming request into a
/// bounded range (`bytes=start-end`, end taken from the URL's `clen`
/// parameter) before forwarding it upstream.
class StreamProxy {
  StreamProxy._();

  static final StreamProxy instance = StreamProxy._();

  HttpServer? _server;
  bool _listening = false;
  final Map<String, String> _entries = {};
  int _nextToken = 0;

  static const _maxEntries = 512;
  static const _maxRedirects = 6;
  static final _clenPattern = RegExp(r'[?&]clen=(\d+)');

  /// Registers [url] and returns a loopback URL that streams it. [key]
  /// keeps the mapping stable across re-resolutions of the same video.
  Future<String> relay(String url, {String? key}) async {
    try {
      final server = _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      if (_listening == false) {
        _listening = true;
        server.listen(
          _serve,
          onError: (_) {},
          cancelOnError: false,
        );
      }
      final token = key ?? 't${_nextToken++}';
      _entries.remove(token);
      if (_entries.length >= _maxEntries) {
        _entries.remove(_entries.keys.first);
      }
      _entries[token] = url;
      return 'http://127.0.0.1:${server.port}/$token';
    } catch (_) {
      // Binding failed — fall back to the direct URL rather than breaking.
      return url;
    }
  }

  Future<void> _serve(HttpRequest req) async {
    final token = req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.first;
    final url = _entries[token];
    if (url == null) {
      req.response.statusCode = HttpStatus.notFound;
      await _closeQuietly(req.response);
      return;
    }
    if (req.method != 'GET' && req.method != 'HEAD') {
      req.response.statusCode = HttpStatus.methodNotAllowed;
      await _closeQuietly(req.response);
      return;
    }

    final clen = int.tryParse(_clenPattern.firstMatch(url)?.group(1) ?? '');

    // Incoming player range: none, `bytes=a-`, or `bytes=a-b`.
    var start = 0;
    int? end;
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final m = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(range.trim());
      if (m != null) {
        start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
      }
    }
    if (clen != null) {
      end = end == null || end >= clen ? clen - 1 : end;
    }
    final bounded = 'bytes=$start-${end ?? ''}';

    final client = HttpClient()..autoUncompress = false;
    try {
      var current = Uri.parse(url);
      HttpClientResponse? upstream;
      for (var hop = 0; hop <= _maxRedirects; hop++) {
        final request = await client.getUrl(current);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.rangeHeader, bounded);
        final resp = await request.close();
        final code = resp.statusCode;
        if (code == 301 || code == 302 || code == 303 || code == 307 || code == 308) {
          final location = resp.headers.value(HttpHeaders.locationHeader);
          await resp.drain<void>();
          if (location == null) break;
          current = current.resolve(location);
          continue;
        }
        upstream = resp;
        break;
      }
      if (upstream == null) {
        req.response.statusCode = HttpStatus.badGateway;
        await _closeQuietly(req.response);
        return;
      }

      req.response.statusCode = upstream.statusCode;
      for (final header in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers.value(header);
        if (value != null) req.response.headers.set(header, value);
      }
      if (req.method == 'HEAD') {
        await upstream.drain<void>();
        await _closeQuietly(req.response);
        return;
      }
      await upstream.pipe(req.response);
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await _closeQuietly(req.response);
      } catch (_) {}
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _closeQuietly(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {}
  }
}
