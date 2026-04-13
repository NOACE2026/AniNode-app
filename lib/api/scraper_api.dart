import 'package:dio/dio.dart';

class ScraperApi {
  static const String baseUrl = 'https://allmanga.to';
  static const String apiUrl = 'https://api.allanime.day/api';
  static const String referer = 'https://allmanga.to';
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36';

  final Dio _dio = Dio(BaseOptions(
    headers: {
      'Referer': referer,
      'User-Agent': userAgent,
      'Content-Type': 'application/json',
    },
  ));

  static final Map<String, String> _decryptMap = {
    "79": "A",
    "7a": "B",
    "7b": "C",
    "7c": "D",
    "7d": "E",
    "7e": "F",
    "7f": "G",
    "70": "H",
    "71": "I",
    "72": "J",
    "73": "K",
    "74": "L",
    "75": "M",
    "76": "N",
    "77": "O",
    "68": "P",
    "69": "Q",
    "6a": "R",
    "6b": "S",
    "6c": "T",
    "6d": "U",
    "6e": "V",
    "6f": "W",
    "60": "X",
    "61": "Y",
    "62": "Z",
    "59": "a",
    "5a": "b",
    "5b": "c",
    "5c": "d",
    "5d": "e",
    "5e": "f",
    "5f": "g",
    "50": "h",
    "51": "i",
    "52": "j",
    "53": "k",
    "54": "l",
    "55": "m",
    "56": "n",
    "57": "o",
    "48": "p",
    "49": "q",
    "4a": "r",
    "4b": "s",
    "4c": "t",
    "4d": "u",
    "4e": "v",
    "4f": "w",
    "40": "x",
    "41": "y",
    "42": "z",
    "08": "0",
    "09": "1",
    "0a": "2",
    "0b": "3",
    "0c": "4",
    "0d": "5",
    "0e": "6",
    "0f": "7",
    "00": "8",
    "01": "9",
    "15": "-",
    "16": ".",
    "67": "_",
    "46": "~",
    "02": ":",
    "17": "/",
    "07": "?",
    "1b": "#",
    "63": "[",
    "65": "]",
    "78": "@",
    "19": "!",
    "1c": r"$",
    "1e": "&",
    "10": "(",
    "11": ")",
    "12": "*",
    "13": "+",
    "14": ",",
    "03": ";",
    "05": "=",
    "1d": "%",
  };

  String decryptId(String encrypted) {
    String decrypted = "";
    for (int i = 0; i < encrypted.length; i += 2) {
      if (i + 2 > encrypted.length) break;
      String hex = encrypted.substring(i, i + 2);
      decrypted += _decryptMap[hex] ?? "?";
    }
    return decrypted.replaceAll("/clock", "/clock.json");
  }

  Future<List<Map<String, dynamic>>> search(String query, {String mode = 'sub'}) async {
    const String gqlQuery = r'''
      query( $search: SearchInput $limit: Int $page: Int $translationType: VaildTranslationTypeEnumType $countryOrigin: VaildCountryOriginEnumType ) { 
        shows( search: $search limit: $limit page: $page translationType: $translationType countryOrigin: $countryOrigin ) { 
          edges { _id name availableEpisodes __typename } 
        } 
      }
    ''';

    final variables = {
      "search": {"allowAdult": false, "allowUnknown": false, "query": query},
      "limit": 40,
      "page": 1,
      "translationType": mode,
      "countryOrigin": "ALL"
    };

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": variables,
      });

      final List edges = response.data['data']['shows']['edges'];
      return edges.map((edge) => {
        "id": edge['_id'],
        "name": edge['name'],
        "episodes": edge['availableEpisodes'][mode] ?? 0,
      }).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> getEpisodesList(String showId, {String mode = 'sub'}) async {
    const String gqlQuery = r'''
      query ($showId: String!) { 
        show( _id: $showId ) { _id availableEpisodesDetail } 
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": {"showId": showId},
      });

      final List episodes = response.data['data']['show']['availableEpisodesDetail'][mode] ?? [];
      List<String> sortedEps = episodes.map((e) => e.toString()).toList();
      sortedEps.sort((a, b) => double.parse(a).compareTo(double.parse(b)));
      return sortedEps;
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, String>>> getSources(String showId, String epNumber, {String mode = 'sub'}) async {
    const String gqlQuery = r'''
      query ($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) { 
        episode( showId: $showId translationType: $translationType episodeString: $episodeString ) { 
          episodeString sourceUrls 
        } 
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": {
          "showId": showId,
          "translationType": mode,
          "episodeString": epNumber
        },
      });

      final List sources = response.data['data']['episode']['sourceUrls'] ?? [];
      List<Map<String, String>> resolvedSources = [];

      for (var s in sources) {
        String url = s['sourceUrl'];
        if (url.startsWith('--')) {
          String encrypted = url.substring(2);
          String decrypted = decryptId(encrypted);
          resolvedSources.add({
            "name": s['sourceName'],
            "url": decrypted.startsWith('http') ? decrypted : "https://allanime.day$decrypted"
          });
        } else {
          resolvedSources.add({
            "name": s['sourceName'],
            "url": url
          });
        }
      }

      // Sort to prioritize "S-mp4" and "Yt-mp4" which are usually direct.
      final preferred = ['S-mp4', 'Yt-mp4', 'Luf-mp4'];
      resolvedSources.sort((a, b) {
        int aLevel = preferred.indexWhere((p) => a['name']!.contains(p));
        int bLevel = preferred.indexWhere((p) => b['name']!.contains(p));
        if (aLevel == -1) aLevel = 99;
        if (bLevel == -1) bLevel = 99;
        return aLevel.compareTo(bLevel);
      });

      return resolvedSources;
    } catch (e) {
      return [];
    }
  }

  Future<String?> resolveSource(String url) async {
    if (url.contains('mp4upload.com') || url.contains('doodstream.com')) {
      // These are currently embeds we don't handle directly yet.
      return null;
    }

    if (!url.contains('/clock.json')) return url;

    try {
      final response = await _dio.get(url);
      final List links = response.data['links'] ?? [];
      if (links.isNotEmpty) {
        // Return the first valid link or src
        return links.first['link'] ?? links.first['src'];
      }
    } catch (e) {
      // Fallback to original URL if resolution fails
    }
    return url;
  }
}
