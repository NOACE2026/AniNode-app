import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Looks up filler episode numbers for an anime title.
///
/// Strategy:
///   1. Try animefillerlist.com — one HTTP request, full episode list in HTML.
///      Fast (<1s) when the slug maps cleanly.
///   2. Fall back to Jikan (MyAnimeList) — N paginated requests by MAL id.
///      Slower but works for shows whose slug we can't infer.
///
/// In-memory cache only — no on-disk persistence.
class FillerService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  static final Map<String, Set<String>> _cache = {};
  static final Map<String, Future<Set<String>>> _inflight = {};

  static Future<Set<String>> fillerForTitle(String title) {
    final key = title.trim().toLowerCase();
    if (key.isEmpty) return Future.value(const {});
    final mem = _cache[key];
    if (mem != null) return Future.value(mem);
    final inflight = _inflight[key];
    if (inflight != null) return inflight;
    final f = _fetch(key, title);
    _inflight[key] = f;
    return f.whenComplete(() => _inflight.remove(key));
  }

  static Future<Set<String>> _fetch(String key, String title) async {
    // Fast path: animefillerlist.com
    final fast = await _fetchFromAnimeFillerList(title);
    if (fast != null) {
      debugPrint('[Filler] "$title" → ${fast.length} via animefillerlist');
      return _cache[key] = fast;
    }
    // Slow fallback: Jikan
    final slow = await _fetchFromJikan(title);
    debugPrint('[Filler] "$title" → ${slow.length} via jikan');
    return _cache[key] = slow;
  }

  /// Build animefillerlist.com slug candidates from a title.
  /// Most anime are reachable as e.g. "one-piece", "naruto-shippuden".
  static List<String> _slugCandidates(String title) {
    final lower = title.toLowerCase();
    // Strip common decorations
    var cleaned = lower
        .replaceAll(RegExp(r'\(.*?\)'), '') // (TV), (2023)
        .replaceAll(':', ' ')
        .replaceAll('!', '')
        .replaceAll('?', '')
        .replaceAll('.', '')
        .replaceAll(',', '')
        .replaceAll("'", '')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final hyphenated = cleaned.replaceAll(' ', '-');
    final candidates = <String>{hyphenated};
    // Some shows are listed without trailing season qualifiers
    final stripped = hyphenated
        .replaceAll(RegExp(r'-(season-\d+|part-\d+|\d{4})$'), '');
    if (stripped.isNotEmpty) candidates.add(stripped);
    return candidates.toList();
  }

  static Future<Set<String>?> _fetchFromAnimeFillerList(String title) async {
    for (final slug in _slugCandidates(title)) {
      try {
        final resp = await _dio.get(
          'https://www.animefillerlist.com/shows/$slug',
          options: Options(
            validateStatus: (s) => s != null && s < 600,
            responseType: ResponseType.plain,
          ),
        );
        if (resp.statusCode != 200 || resp.data is! String) continue;
        final html = resp.data as String;
        final eps = _parseFillerHtml(html);
        if (eps != null) return eps;
      } catch (_) {/* try next candidate */}
    }
    return null;
  }

  /// Parse the animefillerlist.com page. The filler episodes live in a section
  /// where rows reference `/shows/<slug>/<num>`. We scope by the "Filler"
  /// container heading to avoid pulling canon/manga numbers.
  static Set<String>? _parseFillerHtml(String html) {
    // Locate the filler block.
    final idx = html.indexOf(RegExp(r'id="filler"|class="filler"',
        caseSensitive: false));
    if (idx == -1) return null;
    // Take a chunk from the heading to the next section heading.
    final tail = html.substring(idx);
    final endIdx = tail.indexOf(RegExp(
        r'class="(?:manga[-_ ]?canon|anime[-_ ]?canon|mixed[-_ ]?canon)"',
        caseSensitive: false));
    final section = endIdx == -1 ? tail : tail.substring(0, endIdx);
    // Pull all episode numbers — links like /shows/one-piece/279 or anchor text
    // numbers inside <td>NN</td>.
    final numbers = <String>{};
    final hrefRegex = RegExp(r'/shows/[a-z0-9\-]+/(\d+)', caseSensitive: false);
    for (final m in hrefRegex.allMatches(section)) {
      final g = m.group(1);
      if (g != null) numbers.add(g);
    }
    if (numbers.isEmpty) return null;
    return numbers;
  }

  static Future<Set<String>> _fetchFromJikan(String title) async {
    try {
      final searchResp = await _dio.get(
        'https://api.jikan.moe/v4/anime',
        queryParameters: {'q': title, 'limit': 1},
        options: Options(validateStatus: (s) => s != null && s < 600),
      );
      if (searchResp.statusCode != 200) return {};
      final data = (searchResp.data is String
              ? jsonDecode(searchResp.data as String)
              : searchResp.data) as Map?;
      final hits = (data?['data'] as List?) ?? const [];
      if (hits.isEmpty) return {};
      final malId = (hits.first as Map)['mal_id'];
      if (malId is! int) return {};

      final filler = <String>{};
      var page = 1;
      while (page <= 30) {
        final epResp = await _dio.get(
          'https://api.jikan.moe/v4/anime/$malId/episodes',
          queryParameters: {'page': page},
          options: Options(validateStatus: (s) => s != null && s < 600),
        );
        if (epResp.statusCode != 200) break;
        final epData = (epResp.data is String
                ? jsonDecode(epResp.data as String)
                : epResp.data) as Map?;
        final list = (epData?['data'] as List?) ?? const [];
        if (list.isEmpty) break;
        for (final e in list.whereType<Map>()) {
          if (e['filler'] == true) {
            final n = (e['mal_id'] ?? '').toString();
            if (n.isNotEmpty) filler.add(n);
          }
        }
        final hasNext = (epData?['pagination']?['has_next_page'] as bool?) ?? false;
        if (!hasNext) break;
        page++;
        await Future.delayed(const Duration(milliseconds: 400));
      }
      return filler;
    } catch (e) {
      debugPrint('[Filler] jikan error: $e');
      return {};
    }
  }
}
