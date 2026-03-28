import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/music_request.dart';
import '../services/search_service.dart';

class RequestsNotifier extends AsyncNotifier<List<MusicRequest>> {
  @override
  Future<List<MusicRequest>> build() {
    return ref.read(searchServiceProvider).getRequests();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(searchServiceProvider).getRequests(),
    );
  }
}

final requestsProvider =
    AsyncNotifierProvider<RequestsNotifier, List<MusicRequest>>(
  RequestsNotifier.new,
);
