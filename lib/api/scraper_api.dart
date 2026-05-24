import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'providers/anikoto_provider.dart';

// ── Subtitle Track Info ──────────────────────────────────────────────────

class SubtitleTrackInfo {
  final String label;
  final String language;
  final String url;
  const SubtitleTrackInfo({
    required this.label,
    required this.language,
    required this.url,
  });
}

// ── Resolved Source ──────────────────────────────────────────────────────

class ResolvedSource {
  final String? streamUrl;
  final String? referer;
  final List<SubtitleTrackInfo> subtitles;

  const ResolvedSource({
    this.streamUrl,
    this.referer,
    this.subtitles = const [],
  });

  bool get hasStream => streamUrl != null && streamUrl!.isNotEmpty;
}

// ── Scraper API ──────────────────────────────────────────────────────────

class ScraperApi {
  static final AnikotoProvider anikoto = AnikotoProvider();
  static final Dio _dio = Dio()..options.connectTimeout = const Duration(seconds: 10);

  // Static caches for API objects
  static final Map<String, dynamic> _streamResultCache = {};
  static final Map<String, List<dynamic>> _episodeListCache = {};
  static final Map<String, dynamic> _episodeObjectCache = {};

  // ── Cache Access Methods ─────────────────────────────────────────────────

  static String extractResultId(dynamic result, String provider) {
    try {
      final id = result.id?.toString();
      if (id != null && id.isNotEmpty) return '${provider}_$id';
    } catch (_) {}
    return '${provider}_${result.hashCode}';
  }

  static void cacheStreamResult(String id, dynamic result) {
    _streamResultCache[id] = result;
  }

  static dynamic getCachedStreamResult(String id) => _streamResultCache[id];

  static String extractEpNum(dynamic epObj, int fallbackIndex) {
    try {
      final n = epObj.number;
      if (n is int) return n.toString();
      if (n is String && n.isNotEmpty) return n;
    } catch (_) {}
    return '${fallbackIndex + 1}';
  }

  static void cacheEpisodeObjects(String showId, List<dynamic> episodes) {
    for (int i = 0; i < episodes.length; i++) {
      final key = '${showId}_${extractEpNum(episodes[i], i)}';
      _episodeObjectCache[key] = episodes[i];
    }
  }

  static dynamic getCachedEpisode(String showId, String epNum) =>
      _episodeObjectCache['${showId}_$epNum'];

  // ── Metadata Search (Kuroiru compatibility) ──────────────────────────────

  Future<List<dynamic>> searchMetadata(String query) async {
    try {
      if (query.trim().isEmpty) return [];
      
      const String url = 'https://graphql.anilist.co';
      const String graphqlQuery = r'''
        query ($search: String) {
          Page (page: 1, perPage: 30) {
            media (search: $search, type: ANIME) {
              id
              idMal
              title {
                romaji
                english
                native
              }
              coverImage {
                extraLarge
                large
                medium
              }
              bannerImage
              description
              averageScore
              genres
              format
              episodes
              status
              duration
              seasonYear
              studios(isMain: true) {
                nodes {
                  name
                }
              }
            }
          }
        }
      ''';

      final response = await _dio.post(
        url,
        data: {
          'query': graphqlQuery,
          'variables': {'search': query},
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data['data']?['Page']?['media'] as List?;
        if (data != null) {
          return data
              .whereType<Map<String, dynamic>>()
              .map((m) => AnilistMedia.fromJson(m))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('Metadata search error: $e');
      return [];
    }
  }

  Future<dynamic> getMetadataDetails(String id) async {
    try {
      // Metadata details not available for custom scraper
      return null;
    } catch (e) {
      debugPrint('Metadata details error: $e');
      return null;
    }
  }

  // ── Stream Search (Anikoto) ────────────────────────────────────────────

  Future<List<dynamic>> searchStreams(String query,
      {String provider = 'anikoto'}) async {
    try {
      // All requests go through anikoto provider
      return await anikoto.search(query);
    } catch (e) {
      debugPrint('Stream search error: $e');
      return [];
    }
  }

  // ── Episodes ─────────────────────────────────────────────────────────────

  Future<List<dynamic>> getEpisodes(dynamic streamResult,
      {String resultId = ''}) async {
    try {
      final key = resultId.isNotEmpty ? resultId : streamResult.hashCode.toString();
      if (_episodeListCache.containsKey(key)) {
        return _episodeListCache[key]!;
      }

      final episodes = await streamResult.getEpisodes();
      _episodeListCache[key] = episodes ?? [];
      return _episodeListCache[key]!;
    } catch (e) {
      debugPrint('Episodes error: $e');
      return [];
    }
  }

  // ── Source Resolution ────────────────────────────────────────────────────

  Future<List<Map<String, String>>> getSources(dynamic episode) async {
    try {
      final sources = await episode.getSources();
      if (sources == null || sources.isEmpty) return [];

      return List<Map<String, String>>.from(
        sources.asMap().entries.map((e) {
          final s = e.value;
          String url = '';
          String name = 'Server ${e.key + 1}';
          try {
            url = s.url?.toString() ?? s.toString();
          } catch (_) {
            url = s.toString();
          }
          try {
            name = s.name?.toString() ?? s.quality?.toString() ?? name;
          } catch (_) {}
          return {'name': name, 'url': url};
        }),
      );
    } catch (e) {
      debugPrint('Sources error: $e');
      return [];
    }
  }

  Future<ResolvedSource> resolveSource(String url) async {
    try {
      if (url.isEmpty) return const ResolvedSource();

      return ResolvedSource(
        streamUrl: url.isNotEmpty ? url : null,
        referer: 'https://anikoto.cz/',
      );
    } catch (e) {
      debugPrint('Resolve error: $e');
      return const ResolvedSource();
    }
  }

  void cleanup() {
    anikoto.close();
  }
}

// ── AniList Models ──────────────────────────────────────────────────────────

class AnilistTitle {
  final String preferred;
  final String? english;
  final String? romaji;
  final String? native;

  const AnilistTitle({
    required this.preferred,
    this.english,
    this.romaji,
    this.native,
  });

  @override
  String toString() => preferred;
}

class AnilistCoverImage {
  final String? extraLarge;
  final String? large;
  final String? medium;

  const AnilistCoverImage({this.extraLarge, this.large, this.medium});
}

class AnilistStudioNode {
  final String name;
  const AnilistStudioNode({required this.name});
}

class AnilistMedia {
  final int id;
  final AnilistTitle title;
  final AnilistCoverImage? coverImage;
  final String? bannerImage;
  final String? description;
  final int? averageScore;
  final List<String> genres;
  final String? format;
  final int? episodes;
  final String? status;
  final int? duration;
  final int? seasonYear;
  final int? malId;
  final List<AnilistStudioNode>? studios;

  const AnilistMedia({
    required this.id,
    required this.title,
    this.coverImage,
    this.bannerImage,
    this.description,
    this.averageScore,
    this.genres = const [],
    this.format,
    this.episodes,
    this.status,
    this.duration,
    this.seasonYear,
    this.malId,
    this.studios,
  });

  // Getters for search compatibility with AnimeResult
  String get imageUrl => coverImage?.large ?? coverImage?.extraLarge ?? '';
  String? get rating => averageScore != null ? '$averageScore' : null;

  factory AnilistMedia.fromJson(Map<String, dynamic> json) {
    final titleJson = json['title'] as Map<String, dynamic>? ?? {};
    final romaji = titleJson['romaji'] as String?;
    final english = titleJson['english'] as String?;
    final native = titleJson['native'] as String?;
    final preferred = english ?? romaji ?? native ?? 'Unknown';

    final coverJson = json['coverImage'] as Map<String, dynamic>? ?? {};
    final extraLarge = coverJson['extraLarge'] as String?;
    final large = coverJson['large'] as String?;
    final medium = coverJson['medium'] as String?;

    final studiosJson = json['studios'] as Map<String, dynamic>? ?? {};
    final nodesList = (studiosJson['nodes'] as List?) ?? [];
    final nodes = nodesList
        .whereType<Map<String, dynamic>>()
        .map((n) => AnilistStudioNode(name: n['name'] as String? ?? ''))
        .toList();

    return AnilistMedia(
      id: json['id'] as int? ?? 0,
      title: AnilistTitle(
        preferred: preferred,
        english: english,
        romaji: romaji,
        native: native,
      ),
      coverImage: AnilistCoverImage(
        extraLarge: extraLarge,
        large: large,
        medium: medium,
      ),
      bannerImage: json['bannerImage'] as String?,
      description: json['description'] as String?,
      averageScore: json['averageScore'] as int?,
      genres: List<String>.from((json['genres'] as List?) ?? []),
      format: json['format'] as String?,
      episodes: json['episodes'] as int?,
      status: json['status'] as String?,
      duration: json['duration'] as int?,
      seasonYear: json['seasonYear'] as int?,
      malId: json['idMal'] as int?,
      studios: nodes,
    );
  }
}
