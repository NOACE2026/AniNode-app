import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityStatus { online, offline, loading }

final connectivityProvider = StreamProvider<ConnectivityStatus>((ref) async* {
  final connectivity = Connectivity();

  Future<ConnectivityStatus> resolveStatus(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.none)) {
      return ConnectivityStatus.offline;
    }

    try {
      final lookup = await InternetAddress.lookup('example.com').timeout(
        const Duration(seconds: 3),
      );
      if (lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty) {
        return ConnectivityStatus.online;
      }
    } on SocketException {
      return ConnectivityStatus.offline;
    } on TimeoutException {
      return ConnectivityStatus.offline;
    }

    return ConnectivityStatus.offline;
  }

  yield await resolveStatus(await connectivity.checkConnectivity());

  await for (final results in connectivity.onConnectivityChanged) {
    yield await resolveStatus(results);
  }
});
