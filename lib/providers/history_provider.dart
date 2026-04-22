import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  };

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
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
  }) async {
    final key = '${showId}_$episode';
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
    );

    // Update state safely
    final currentState = state.value ?? {};
    final newState = {...currentState, key: progress};
    
    Future.microtask(() {
      state = AsyncValue.data(newState);
    });

    // Persist
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(
      newState.map((k, v) => MapEntry(k, v.toJson())),
    ));
  }

  Future<void> resetProgress(String showId, String episode) async {
    final key = '${showId}_$episode';
    final currentState = state.value ?? {};
    if (currentState.containsKey(key)) {
      final newState = {...currentState}..remove(key);
      
      Future.microtask(() {
        state = AsyncValue.data(newState);
      });

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
