import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class JikanEpisode {
  final String number;
  final String? title;
  final bool isFiller;
  final bool isRecap;

  const JikanEpisode({
    required this.number,
    this.title,
    this.isFiller = false,
    this.isRecap = false,
  });
}

/// Fetches episode list (number, title, filler, recap) from Jikan/MAL.
///
/// - Paginates automatically (100 eps per page, 450 ms between pages).
/// - Calls [onPage] after every page so the UI can update progressively.
/// - Results are cached in memory; concurrent requests for the same MAL id
///   share a single in-flight Future.
class JikanService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  static final Map<int, List<JikanEpisode>> _cache = {};
  static final Map<int, Future<List<JikanEpisode>>> _inflight = {};

  static Future<List<JikanEpisode>> fetchEpisodes(
    int malId, {
    void Function(List<JikanEpisode> accumulated)? onPage,
  }) {
    final cached = _cache[malId];
    if (cached != null) {
      if (onPage != null) onPage(cached);
      return Future.value(cached);
    }
    final inflight = _inflight[malId];
    if (inflight != null) return inflight;
    final f = _fetch(malId, onPage: onPage);
    _inflight[malId] = f;
    return f.whenComplete(() => _inflight.remove(malId));
  }

  static Future<List<JikanEpisode>> _fetch(
    int malId, {
    void Function(List<JikanEpisode>)? onPage,
  }) async {
    final all = <JikanEpisode>[];
    var page = 1;

    while (page <= 50) {
      try {
        final resp = await _dio.get(
          'https://api.jikan.moe/v4/anime/$malId/episodes',
          queryParameters: {'page': page},
          options: Options(validateStatus: (s) => s != null && s < 600),
        );
        if (resp.statusCode == 429) {
          await Future.delayed(const Duration(seconds: 2));
          continue;
        }
        if (resp.statusCode != 200) break;

        final body = resp.data is String
            ? jsonDecode(resp.data as String) as Map
            : resp.data as Map;

        final list = (body['data'] as List?) ?? const [];
        if (list.isEmpty) break;

        for (final e in list.whereType<Map>()) {
          final num = (e['mal_id'] ?? '').toString();
          if (num.isEmpty) continue;
          all.add(JikanEpisode(
            number: num,
            title: e['title'] as String?,
            isFiller: (e['filler'] as bool?) ?? false,
            isRecap: (e['recap'] as bool?) ?? false,
          ));
        }

        onPage?.call(List.unmodifiable(all));

        final hasNext =
            (body['pagination']?['has_next_page'] as bool?) ?? false;
        if (!hasNext) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 450));
      } catch (e) {
        debugPrint('[Jikan] episodes p$page error: $e');
        break;
      }
    }

    debugPrint('[Jikan] malId=$malId → ${all.length} episodes');
    _cache[malId] = all;
    return all;
  }
}
