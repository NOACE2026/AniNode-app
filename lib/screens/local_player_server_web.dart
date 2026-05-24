// Web stub — no HTTP server on web; the embed URL is loaded directly.
class LocalPlayerServer {
  static int? port = 0; // sentinel: web mode active
  static int _refCount = 0;

  static Future<void> start() async {
    _refCount++;
    port = 0;
  }

  static void stop() {
    _refCount = (_refCount - 1).clamp(0, 999);
    if (_refCount == 0) port = 0;
  }
}
