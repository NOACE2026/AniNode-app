import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ConnectivityStatus { online, offline, loading }

final connectivityProvider = StreamProvider<ConnectivityStatus>((ref) async* {
  final connectivity = Connectivity();
  
  // Get initial status
  final initial = await connectivity.checkConnectivity();
  if (initial.contains(ConnectivityResult.none)) {
    yield ConnectivityStatus.offline;
  } else {
    yield ConnectivityStatus.online;
  }

  // Monitor changes
  await for (final results in connectivity.onConnectivityChanged) {
    if (results.contains(ConnectivityResult.none)) {
       yield ConnectivityStatus.offline;
    } else {
       yield ConnectivityStatus.online;
    }
  }
});
