import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/scraper_api.dart';

// ── State Notifiers for mutable state ────────────────────────────────────

class SelectedModeNotifier extends Notifier<String> {
  @override
  String build() => 'sub';
  void setMode(String m) => state = m;
}

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

class EpisodeSearchNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

// ── Providers ────────────────────────────────────────────────────────────

final selectedModeProvider = NotifierProvider<SelectedModeNotifier, String>(
  SelectedModeNotifier.new,
);

final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

final episodeSearchProvider = NotifierProvider<EpisodeSearchNotifier, String>(
  EpisodeSearchNotifier.new,
);

// ── Episode Provider Parameters ──────────────────────────────────────────

typedef EpisodesParams = ({String showId, String title, String mode});

// ── Search and Episode Providers ─────────────────────────────────────────

final searchMetadataProvider = FutureProvider.family<List<dynamic>, String>(
  (ref, query) async {
    if (query.trim().isEmpty) return [];
    return ScraperApi().searchMetadata(query.trim());
  },
);

final searchStreamsProvider = FutureProvider.family<List<dynamic>, String>(
  (ref, query) async {
    if (query.trim().isEmpty) return [];
    return ScraperApi().searchStreams(query.trim());
  },
);

final episodesProvider = FutureProvider.family<List<dynamic>, EpisodesParams>(
  (ref, params) async {
    var cached = ScraperApi.getCachedStreamResult(params.showId);
    if (cached == null && params.title.isNotEmpty) {
      // Cold start / history resume: re-search by title
      final List<dynamic> results = await ScraperApi().searchStreams(params.title);
      if (results.isNotEmpty) {
        // Find the exact search result whose extracted ID matches showId to prevent mismatches (e.g. movies/spinoffs)
        dynamic match = results.first;
        for (final res in results) {
          if (ScraperApi.extractResultId(res, 'anikoto') == params.showId) {
            match = res;
            break;
          }
        }
        final id = ScraperApi.extractResultId(match, 'anikoto');
        ScraperApi.cacheStreamResult(id, match);
        cached = match;
      }
    }
    if (cached == null) return [];
    return ScraperApi().getEpisodes(cached, resultId: params.showId);
  },
);

final sourcesProvider = FutureProvider.family<List<Map<String, String>>, dynamic>(
  (ref, episode) async {
    return ScraperApi().getSources(episode);
  },
);

// ── Recently Updated ─────────────────────────────────────────────────────

final recentAnimeProvider = FutureProvider<List<dynamic>>((ref) async {
  return ScraperApi.anikoto.recent(perPage: 24);
});

// ── Infinite "Browse All" feed ───────────────────────────────────────────

class BrowseAllNotifier extends AsyncNotifier<List<dynamic>> {
  static const int _perPage = 30;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  @override
  Future<List<dynamic>> build() async {
    _page = 1;
    final first = await ScraperApi.anikoto.recent(page: 1, perPage: _perPage);
    _hasMore = first.length >= _perPage;
    return first;
  }

  Future<void> loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    // Ping listeners so the footer sliver can show a spinner. The list itself
    // is unchanged.
    state = AsyncValue.data(state.value ?? []);
    try {
      final next = await ScraperApi.anikoto
          .recent(page: _page + 1, perPage: _perPage);
      if (next.isEmpty) {
        _hasMore = false;
      } else {
        _page++;
        final current = state.value ?? const [];
        state = AsyncValue.data([...current, ...next]);
        if (next.length < _perPage) _hasMore = false;
      }
    } catch (_) {
      // Leave state as-is; user can scroll again to retry.
    } finally {
      _loadingMore = false;
      // Settle state so listeners get notified that loadingMore flipped.
      state = AsyncValue.data(state.value ?? const []);
    }
  }
}

final browseAllProvider =
    AsyncNotifierProvider<BrowseAllNotifier, List<dynamic>>(BrowseAllNotifier.new);
