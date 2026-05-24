// Stub for dart:io types used in connectivity_provider.dart on web.
class InternetAddress {
  final List<int> rawAddress;
  const InternetAddress({this.rawAddress = const []});
  static Future<List<InternetAddress>> lookup(String host) async => [];
}

class SocketException implements Exception {
  final String message;
  const SocketException([this.message = '']);
}
