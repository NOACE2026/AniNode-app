import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One stream entry as persisted in history. Mirrors EpisodeStream but kept
/// here so this file has no dependency on web_player_screen.dart.
class SavedStream {
  final String number;
  final String? subUrl;
  final String? dubUrl;
  const SavedStream({required this.number, this.subUrl, this.dubUrl});

  Map<String, dynamic> toJson() =>
      {'number': number, 'subUrl': subUrl, 'dubUrl': dubUrl};

  factory SavedStream.fromJson(Map<String, dynamic> j) => SavedStream(
        number: j['number']?.toString() ?? '',
        subUrl: j['subUrl']?.toString(),
        dubUrl: j['dubUrl']?.toString(),
      );
}

class WatchProgress {
  final String animeId; // Previously AniList ID, now Scraper ID or stringified int
  final String showId; // Scraper ID
  final String episode;
  final String title;
  final String? imageUrl;
  final String mode; // sub or dub
  final int position;
  final int duration;
  final DateTime updatedAt;
  // Full per-episode stream list captured at play-time. When present, resume
  // can rebuild the player without re-fetching from the API.
  final List<SavedStream>? streams;

  WatchProgress({
    required this.animeId,
    required this.showId,
    required this.episode,
    required this.title,
    this.imageUrl,
    required this.mode,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.streams,
  });

  Map<String, dynamic> toJson() => {
    'animeId': animeId,
    'showId': showId,
    'episode': episode,
    'title': title,
    'imageUrl': imageUrl,
    'mode': mode,
    'position': position,
    'duration': duration,
    'updatedAt': updatedAt.toIso8601String(),
    'streams': streams?.map((s) => s.toJson()).toList(),
  };

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
    final rawStreams = json['streams'];
    List<SavedStream>? streams;
    if (rawStreams is List) {
      streams = rawStreams
          .whereType<Map>()
          .map((m) => SavedStream.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }
    return WatchProgress(
      animeId: json['animeId']?.toString() ?? '',
      showId: json['showId']?.toString() ?? '',
      episode: json['episode']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Unknown',
      imageUrl: json['imageUrl']?.toString(),
      mode: json['mode']?.toString() ?? 'sub',
      position: json['position'] is int ? json['position'] : int.tryParse(json['position']?.toString() ?? '') ?? 0,
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      streams: streams,
    );
  }

  double get percent => duration > 0 ? position / duration : 0;
}

class HistoryNotifier extends AsyncNotifier<Map<String, WatchProgress>> {
  static const String _prefKey = 'aninode_watch_history';

  @override
  FutureOr<Map<String, WatchProgress>> build() async {
    return _loadHistory();
  }

  Future<Map<String, WatchProgress>> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_prefKey);
    if (data == null) return {};

    try {
      final Map<String, dynamic> decoded = jsonDecode(data);
      return decoded.map((key, value) => MapEntry(
        key, 
        WatchProgress.fromJson(Map<String, dynamic>.from(value)),
      ));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveProgress({
    required String animeId,
    required String showId,
    required String episode,
    required String title,
    String? imageUrl,
    required String mode,
    required Duration position,
    required Duration duration,
    List<SavedStream>? streams,
  }) async {
    final key = '${showId}_$episode';
    // Preserve the streams list from any existing entry if the caller doesn't
    // pass one — episode time-events shouldn't drop the stored URLs.
    final priorStreams = state.value?[key]?.streams;
    final progress = WatchProgress(
      animeId: animeId,
      showId: showId,
      episode: episode,
      title: title,
      imageUrl: imageUrl,
      mode: mode,
      position: position.inMilliseconds,
      duration: duration.inMilliseconds,
      updatedAt: DateTime.now(),
      streams: streams ?? priorStreams,
    );

    // Make sure the initial load has finished before merging — otherwise
    // state.value would be null and we'd overwrite prefs with just this entry.
    final currentState = await future;
    final newState = {...currentState, key: progress};
    state = AsyncValue.data(newState);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(
      newState.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  Future<void> resetProgress(String showId, String episode) async {
    final key = '${showId}_$episode';
    final currentState = await future;
    if (currentState.containsKey(key)) {
      final newState = {...currentState}..remove(key);
      state = AsyncValue.data(newState);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(
        newState.map((k, v) => MapEntry(k, v.toJson())),
      ));
    }
  }
}

final historyProvider = AsyncNotifierProvider<HistoryNotifier, Map<String, WatchProgress>>(() {
  return HistoryNotifier();
});

final recentHistoryProvider = Provider<List<WatchProgress>>((ref) {
  final historyMap = ref.watch(historyProvider).value ?? {};
  
  // Group by animeId and keep the most recent entry for each
  final Map<String, WatchProgress> uniqueHistory = {};
  for (final progress in historyMap.values) {
    final existing = uniqueHistory[progress.animeId];
    if (existing == null || progress.updatedAt.isAfter(existing.updatedAt)) {
      uniqueHistory[progress.animeId] = progress;
    }
  }
  
  final list = uniqueHistory.values.toList();
  // Sort by updatedAt descending to show most recently watched first
  list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return list;
});
