import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── Result Models ────────────────────────────────────────────────────────

class AnimeResult {
  final int apiId;
  final String id;
  final String title;
  final String url;
  final String imageUrl;
  final String? rating;
  final String? airDate;
  final String? description;
  final List<String> genres;
  final String? bannerImage;
  final int? aniId;
  final int? malId;
  final String? status;
  final int? year;
  final int? totalEpisodes;
  final double? score;

  // Cached episodes — populated after first fetch so the details screen and
  // player share the same Episode objects (each carries sub/dub URLs).
  List<Episode>? _episodes;

  AnimeResult({
    required this.apiId,
    required this.id,
    required this.title,
    required this.url,
    required this.imageUrl,
    this.rating,
    this.airDate,
    this.description,
    this.genres = const [],
    this.bannerImage,
    this.aniId,
    this.malId,
    this.status,
    this.year,
    this.totalEpisodes,
    this.score,
  });

  Future<List<Episode>> getEpisodes() async {
    if (_episodes != null) return _episodes!;
    final eps = await AnikotoProvider().fetchEpisodes(apiId);
    _episodes = eps;
    return eps;
  }

  @override
  String toString() => 'AnimeResult(id: $apiId, title: $title)';
}

class Episode {
  final String id;
  final String number;
  final String title;
  final String url;
  final String? subUrl;
  final String? dubUrl;
  final String? thumbnail;

  Episode({
    required this.id,
    required this.number,
    required this.title,
    required this.url,
    this.subUrl,
    this.dubUrl,
    this.thumbnail,
  });

  Future<List<Source>> getSources() async {
    final sources = <Source>[];
    if (subUrl != null && subUrl!.isNotEmpty) {
      sources.add(Source(id: 'sub-$id', name: 'SUB', url: subUrl!));
    }
    if (dubUrl != null && dubUrl!.isNotEmpty) {
      sources.add(Source(id: 'dub-$id', name: 'DUB', url: dubUrl!));
    }
    return sources;
  }

  @override
  String toString() => 'Episode(id: $id, number: $number)';
}

class Source {
  final String id;
  final String name;
  final String url;
  final String quality;
  final List<Subtitle> subtitles;

  Source({
    required this.id,
    required this.name,
    required this.url,
    this.quality = 'Unknown',
    this.subtitles = const [],
  });

  Map<String, String> toMap() => {
        'name': name,
        'url': url,
        'quality': quality,
        'id': id,
      };

  @override
  String toString() => 'Source(id: $id, name: $name)';
}

class Subtitle {
  final String language;
  final String label;
  final String url;

  Subtitle({required this.language, required this.label, required this.url});
}

// ── Anikoto Provider ─────────────────────────────────────────────────────

class AnikotoProvider {
  static const String baseUrl = 'https://anikototv.to';
  static const String apiUrl = 'https://anikotoapi.site';

  // /recent-anime is paginated; we cache fetched pages to support
  // multi-page client-side filtering without re-hitting the API.
  static final List<Map<String, dynamic>> _recentAnimeCache = [];
  static DateTime? _cacheTime;
  static int _lastFetchedPage = 0;

  late final Dio _dio;

  AnikotoProvider() {
    _dio = Dio();
    _dio.options.headers = {
      'Accept': 'application/json',
      'User-Agent': 'AniNodeMobile/1.0',
    };
    _dio.options.connectTimeout = const Duration(seconds: 10);
    _dio.options.receiveTimeout = const Duration(seconds: 15);
  }

  /// Search by fetching pages of /recent-anime and filtering client-side.
  ///
  /// The API has no search endpoint, but a single page already covers most
  /// in-season shows. We pull up to 3 pages (~150 anime) so the catalog is
  /// wide enough to be useful while staying well under the rate limit.
  Future<List<AnimeResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      await _ensureRecentCache();

      final results = <AnimeResult>[];
      final q = query.toLowerCase();
      for (final item in _recentAnimeCache) {
        final hit = _matchesQuery(item, q);
        if (!hit) continue;
        final mapped = _toAnimeResult(item);
        if (mapped != null) results.add(mapped);
        if (results.length >= 30) break;
      }
      debugPrint('[Anikoto] search "$query" → ${results.length} hits');
      return results;
    } catch (e) {
      debugPrint('[Anikoto] search error: $e');
      return [];
    }
  }

  /// Return the most recently updated anime as AnimeResults.
  Future<List<AnimeResult>> recent({int page = 1, int perPage = 30}) async {
    try {
      final resp = await _dio.get(
        '$apiUrl/recent-anime',
        queryParameters: {'page': page, 'per_page': perPage},
        options: Options(validateStatus: (s) => s != null && s < 600),
      );
      if (resp.statusCode != 200 || resp.data is! Map) return [];
      final list = ((resp.data as Map)['data'] as List?) ?? [];
      return list
          .whereType<Map>()
          .map((m) => _toAnimeResult(Map<String, dynamic>.from(m)))
          .whereType<AnimeResult>()
          .toList();
    } catch (e) {
      debugPrint('[Anikoto] recent error: $e');
      return [];
    }
  }

  /// Fetch a full episode list for a series by its numeric API id.
  Future<List<Episode>> fetchEpisodes(int seriesId) async {
    try {
      final resp = await _dio.get(
        '$apiUrl/series/$seriesId',
        options: Options(validateStatus: (s) => s != null && s < 600),
      );
      if (resp.statusCode != 200 || resp.data is! Map) {
        debugPrint('[Anikoto] series $seriesId → ${resp.statusCode}');
        return [];
      }
      final data = (resp.data as Map)['data'];
      if (data is! Map) return [];
      final eps = (data['episodes'] as List?) ?? [];
      return eps.whereType<Map>().map((e) {
        final embed = (e['embed_url'] as Map?) ?? const {};
        final num = (e['number'] ?? '').toString();
        return Episode(
          id: (e['id'] ?? e['episode_embed_id'] ?? num).toString(),
          number: num,
          title: (e['title'] ?? 'Episode $num').toString(),
          url: '$baseUrl/watch/${data['anime']?['slug'] ?? ''}?ep=${e['id']}',
          subUrl: embed['sub']?.toString(),
          dubUrl: embed['dub']?.toString(),
        );
      }).toList();
    } catch (e) {
      debugPrint('[Anikoto] fetchEpisodes error: $e');
      return [];
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _ensureRecentCache() async {
    final now = DateTime.now();
    final fresh = _cacheTime != null && now.difference(_cacheTime!).inMinutes < 10;
    if (fresh && _recentAnimeCache.isNotEmpty) return;

    _recentAnimeCache.clear();
    _lastFetchedPage = 0;
    // Pull 3 pages of 50 — gives ~150 shows, well under the 60req/120s budget.
    for (int page = 1; page <= 3; page++) {
      try {
        final resp = await _dio.get(
          '$apiUrl/recent-anime',
          queryParameters: {'page': page, 'per_page': 50},
          options: Options(validateStatus: (s) => s != null && s < 600),
        );
        if (resp.statusCode != 200 || resp.data is! Map) break;
        final list = ((resp.data as Map)['data'] as List?) ?? [];
        if (list.isEmpty) break;
        _recentAnimeCache.addAll(
          list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)),
        );
        _lastFetchedPage = page;
        final pag = (resp.data as Map)['pagination'];
        if (pag is Map && page >= (pag['total_pages'] as int? ?? page)) break;
      } catch (e) {
        debugPrint('[Anikoto] recent page $page error: $e');
        break;
      }
    }
    _cacheTime = now;
    debugPrint('[Anikoto] cached ${_recentAnimeCache.length} anime (pages 1-$_lastFetchedPage)');
  }

  bool _matchesQuery(Map item, String q) {
    bool has(Object? v) => v != null && v.toString().toLowerCase().contains(q);
    return has(item['title']) ||
        has(item['alternative']) ||
        has(item['native']) ||
        has(item['titles']);
  }

  AnimeResult? _toAnimeResult(Map<String, dynamic> item) {
    final id = item['id'];
    final title = item['title']?.toString() ?? '';
    final slug = item['slug']?.toString() ?? '';
    if (id is! int || title.isEmpty) return null;

    final terms = item['terms_by_type'];
    final genres = <String>[];
    if (terms is Map && terms['genre'] is List) {
      genres.addAll((terms['genre'] as List).map((g) => g.toString()));
    }

    final cleanDesc = item['description']
        ?.toString()
        .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '')
        .trim();

    int? toInt(Object? v) {
      if (v is int) return v;
      if (v is String) return int.tryParse(v);
      return null;
    }

    double? toDouble(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return AnimeResult(
      apiId: id,
      id: slug.isNotEmpty ? slug : id.toString(),
      title: title,
      url: slug.isNotEmpty ? '$baseUrl/watch/$slug' : '',
      imageUrl: item['poster']?.toString() ?? '',
      rating: item['rating']?.toString(),
      airDate: item['aired']?.toString(),
      description: (cleanDesc?.isEmpty ?? true) ? null : cleanDesc,
      genres: genres,
      bannerImage: item['background_image']?.toString(),
      aniId: toInt(item['ani_id']),
      malId: toInt(item['mal_id']),
      status: item['status']?.toString(),
      year: toInt(item['year']),
      totalEpisodes: toInt(item['episodes']),
      score: toDouble(item['score']),
    );
  }

  // ── Stream URL builders ──────────────────────────────────────────────────

  /// Build the megaplay embed URL for an episode by its catalog embed id.
  static String streamUrlByEmbedId(String embedId, {String lang = 'sub'}) =>
      'https://megaplay.buzz/stream/s-2/$embedId/$lang';

  /// Build the megaplay embed URL by AniList id + episode number.
  /// Lets the player play even when we can't resolve an Anikoto catalog id.
  static String streamUrlByAniList(int aniId, int epNum, {String lang = 'sub'}) =>
      'https://megaplay.buzz/stream/ani/$aniId/$epNum/$lang';

  /// Build the megaplay embed URL by MAL id + episode number.
  static String streamUrlByMal(int malId, int epNum, {String lang = 'sub'}) =>
      'https://megaplay.buzz/stream/mal/$malId/$epNum/$lang';

  void close() {
    _dio.close();
  }
}
