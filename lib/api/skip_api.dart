import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class SkipApi {
  final Dio _dio = Dio();
  static const String baseUrl = 'https://api.aniskip.com/v2/skip-times';
  // Standard test client ID for AniSkip 
  static const String clientId = 'ZGfO0sMF3eCwLYf8yMSCJjlynwNGRXWE';

  Future<List<Map<String, dynamic>>> getSkipTimes(int malId, String episodeNumber, double episodeLength) async {
    // 1. Try Strict Match (with episodeLength)
    final strictResults = await _fetch(malId, episodeNumber, episodeLength);
    if (strictResults.isNotEmpty) {
      debugPrint('AniNode: Strict match found for MAL ID: $malId');
      return strictResults;
    }

    // 2. Try Fuzzy Match (without episodeLength) as fallback
    debugPrint('AniNode: Strict match failed for $malId, retrying with fuzzy match...');
    final fuzzyResults = await _fetch(malId, episodeNumber, null);
    if (fuzzyResults.isNotEmpty) {
      debugPrint('AniNode: Fuzzy match found for MAL ID: $malId');
      return fuzzyResults;
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> _fetch(int malId, String episodeNumber, double? episodeLength) async {
    try {
      final double? epNum = double.tryParse(episodeNumber);
      if (epNum == null) return [];

      final String url = '$baseUrl/$malId/${epNum.toInt()}';
      
      final Map<String, dynamic> queryParams = {
        'types': ['op', 'ed', 'recap', 'mixed-op', 'mixed-ed'],
      };
      if (episodeLength != null) {
        queryParams['episodeLength'] = episodeLength;
      }

      final response = await _dio.get(
        url,
        queryParameters: queryParams,
        options: Options(
          headers: {
            'X-Client-ID': clientId,
          },
          // Format types=op&types=ed instead of types[]=op
          listFormat: ListFormat.multi,
        ),
      );

      if (response.statusCode == 200) {
        final List results = response.data['results'] ?? [];
        return results.map((r) => {
          'type': r['skipType'],
          'start': r['interval']['startTime'].toDouble(),
          'end': r['interval']['endTime'].toDouble(),
        }).toList();
      }
    } catch (e) {
      if (e is DioException) {
        if (e.response?.statusCode != 404) {
          debugPrint('AniNode: Skip API Error: ${e.response?.statusCode}');
        }
      }
    }
    return [];
  }
}
