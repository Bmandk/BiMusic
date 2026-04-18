import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged.map( // coverage:ignore-line
    (results) =>
        results.isEmpty ? ConnectivityResult.none : results.first,
  );
});
