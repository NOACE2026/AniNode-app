import 'dart:io';
import 'package:flutter/foundation.dart';

class LocalPlayerServer {
  static HttpServer? _server;
  static int? port;
  static int _refCount = 0;

  static Future<void> start() async {
    _refCount++;
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      port = _server!.port;
      debugPrint('LocalPlayerServer started on port $port');

      _server!.listen((HttpRequest request) async {
        if (request.uri.path == '/play') {
          final url = request.uri.queryParameters['url'] ?? '';
          final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      background-color: black;
      overflow: hidden;
    }
    iframe {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      border: 0;
    }
  </style>
</head>
<body>
  <iframe src="$url" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen="true" webkitallowfullscreen="true" mozallowfullscreen="true"></iframe>
</body>
</html>
''';
          request.response
            ..headers.contentType = ContentType.html
            ..write(html);
          await request.response.close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found');
          await request.response.close();
        }
      }, onError: (err) {
        debugPrint('LocalPlayerServer error: $err');
      });
    } catch (e) {
      debugPrint('Error starting LocalPlayerServer: $e');
    }
  }

  static void stop() {
    _refCount = (_refCount - 1).clamp(0, 999);
    if (_refCount > 0) return;
    try {
      _server?.close(force: true);
    } catch (_) {}
    _server = null;
    port = null;
  }
}
