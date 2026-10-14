/// Web stub for [StreamProxy]: there is no loopback server on the web —
/// stream URLs come from the backend there, which handles ranges itself.
class StreamProxy {
  StreamProxy._();

  static final StreamProxy instance = StreamProxy._();

  Future<String> relay(String url, {String? key}) async => url;
}
