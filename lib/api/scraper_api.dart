import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/parser.dart' as parser;

class ScraperApi {
  static const String baseUrl = 'https://anitaku.to';
  static const String userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0';

  final Dio _dio = Dio(BaseOptions(
    headers: {
      'User-Agent': userAgent,
    },
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // GogoCDN Keys (kept for fallback if some episodes still use old CDN)
  final _keys = {
    'key': '37911490979715163134003223491201',
    'secondKey': '54674138327930866480207815084989',
    'iv': '3134003223491201',
  };

  Future<List<Map<String, dynamic>>> search(String query, {String mode = 'sub'}) async {
    try {
      final response = await _dio.get('$baseUrl/search.html?keyword=${Uri.encodeComponent(query)}');
      final document = parser.parse(response.data);
      final List<Map<String, dynamic>> results = [];

      final items = document.querySelectorAll('div.last_episodes > ul > li');
      for (var item in items) {
        final a = item.querySelector('p.name > a');
        final img = item.querySelector('div.img > a > img');

        final id = a?.attributes['href']?.split('/').last ?? '';
        final title = a?.attributes['title'] ?? '';
        final image = img?.attributes['src'] ?? '';

        if (id.isEmpty) continue;

        results.add({
          "id": id,
          "name": title,
          "englishName": title,
          "thumbnail": image,
          "episodes": 0,
        });
      }
      return results;
    } catch (e) {
      print('Search error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchTrending({String mode = 'sub'}) async {
    try {
      // Correct URL — recent releases are at the root, not /ajax
      final response = await _dio.get('$baseUrl/page-recent-release.html?page=1&type=1');
      final document = parser.parse(response.data);
      final List<Map<String, dynamic>> results = [];

      final items = document.querySelectorAll('div.last_episodes > ul > li');
      for (var item in items) {
        final a = item.querySelector('p.name > a');
        final img = item.querySelector('div.img > a > img');
        final epText = item.querySelector('p.episode')?.text.trim() ?? '';

        // Episode links are like /name-episode-1. ID is "name".
        final href = a?.attributes['href'] ?? '';
        final id = href.split('/').last.split('-episode-').first;
        final title = a?.attributes['title'] ?? '';
        final image = img?.attributes['src'] ?? '';

        if (id.isEmpty) continue;

        results.add({
          "id": id,
          "name": title,
          "englishName": title,
          "thumbnail": image,
          "episodes": int.tryParse(epText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        });
      }

      // If recent release page fails or is empty, fall back to search page results
      if (results.isEmpty) {
        return await _fetchPopularFallback();
      }

      return results;
    } catch (e) {
      print('Trending error: $e');
      return await _fetchPopularFallback();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPopularFallback() async {
    try {
      final response = await _dio.get('$baseUrl/popular.html');
      final document = parser.parse(response.data);
      final List<Map<String, dynamic>> results = [];

      final items = document.querySelectorAll('div.last_episodes > ul > li');
      for (var item in items) {
        final a = item.querySelector('p.name > a');
        final img = item.querySelector('div.img > a > img');
        final id = a?.attributes['href']?.split('/').last ?? '';
        final title = a?.attributes['title'] ?? '';
        final image = img?.attributes['src'] ?? '';
        if (id.isEmpty) continue;
        results.add({
          "id": id,
          "name": title,
          "englishName": title,
          "thumbnail": image,
          "episodes": 0,
        });
      }
      return results;
    } catch (e) {
      print('Popular fallback error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getShowDetails(String showId) async {
    try {
      final url = showId.startsWith('http') ? showId : '$baseUrl/category/$showId';
      final response = await _dio.get(url);
      final document = parser.parse(response.data);

      final title = document.querySelector('div.anime_info_body_bg > h1')?.text.trim() ?? '';
      final image = document.querySelector('div.anime_info_body_bg > img')?.attributes['src'] ?? '';
      final description = document.querySelector('div.anime_info_body_bg > p:nth-child(5)')?.text.replaceFirst('Plot Summary: ', '').trim() ?? '';
      final status = document.querySelector('div.anime_info_body_bg > p:nth-child(8) > a')?.text.trim() ?? 'Unknown';
      final type = document.querySelector('div.anime_info_body_bg > p:nth-child(4) > a')?.text.trim() ?? 'TV';

      final genres = document.querySelectorAll('div.anime_info_body_bg > p:nth-child(6) > a')
          .map((e) => e.text.trim())
          .toList();

      return {
        "_id": showId,
        "name": title,
        "englishName": title,
        "thumbnail": image,
        "description": description,
        "genres": genres,
        "status": status,
        "type": type,
        "score": "N/A",
      };
    } catch (e) {
      print('Details error: $e');
      return null;
    }
  }

  Future<List<String>> getEpisodesList(String showId, {String mode = 'sub'}) async {
    try {
      final url = '$baseUrl/category/$showId';
      final response = await _dio.get(url);
      final document = parser.parse(response.data);

      final eps = document.querySelectorAll('a[href^="/$showId-episode-"]')
          .map((e) => RegExp(r'\d+').firstMatch(e.text)?.group(0) ?? '')
          .where((e) => e.isNotEmpty)
          .toList();

      // Convert to Set to remove duplicates, then sort numerically
      final uniqueEps = eps.toSet().toList();
      uniqueEps.sort((a, b) => double.parse(a).compareTo(double.parse(b)));
      return uniqueEps;
    } catch (e) {
      print('Episodes error: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> getSources(String showId, String epNumber, {String mode = 'sub'}) async {
    try {
      final epId = '$showId-episode-$epNumber';
      final response = await _dio.get('$baseUrl/$epId');
      final document = parser.parse(response.data);

      final serverLinks = document.querySelectorAll('.server-video');
      String? targetUrl;

      // Prefer vibeplayer.site as it exposes direct m3u8
      for (var link in serverLinks) {
        final videoUrl = link.attributes['data-video'];
        if (videoUrl != null && videoUrl.contains('vibeplayer.site')) {
          targetUrl = videoUrl;
          break;
        }
      }

      // Fallback to any first server
      if (targetUrl == null && serverLinks.isNotEmpty) {
        targetUrl = serverLinks.first.attributes['data-video'];
      }

      if (targetUrl == null) return [];

      final fullIframeUrl = targetUrl.startsWith('http') ? targetUrl : 'https:$targetUrl';

      if (fullIframeUrl.contains('vibeplayer.site')) {
        final uri = Uri.parse(fullIframeUrl);
        // Extract the video ID from path — filter out empty segments and "embed"
        final id = uri.pathSegments.lastWhere(
          (s) => s.isNotEmpty && s != 'embed',
          orElse: () => '',
        );
        if (id.isEmpty) return [];
        final masterUrl = 'https://vibeplayer.site/public/stream/$id/master.m3u8';
        return [{'name': 'Auto (VibePlayer)', 'url': masterUrl}];
      }

      // Fallback to legacy GogoCDN decryption for other servers
      final videoSources = await _extractGogoCDN(fullIframeUrl);
      return videoSources.map((s) => {
        "name": s['quality'] ?? "Default",
        "url": s['url'] ?? ""
      }).where((s) => s['url']!.isNotEmpty).toList();
    } catch (e) {
      print('Sources error: $e');
      return [];
    }
  }

  Future<List<Map<String, String>>> _extractGogoCDN(String iframeUrl) async {
    try {
      final uri = Uri.parse(iframeUrl);
      final id = uri.queryParameters['id'];
      if (id == null) return [];

      final response = await _dio.get(iframeUrl);
      final document = parser.parse(response.data);

      final key = enc.Key.fromUtf8(_keys['key']!);
      final iv = enc.IV.fromUtf8(_keys['iv']!);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

      final encryptedId = encrypter.encrypt(id, iv: iv).base64;

      final scriptValue = document.querySelector("script[data-name='episode']")?.attributes['data-value'];
      if (scriptValue == null) return [];

      final decryptedToken = encrypter.decrypt(enc.Encrypted.fromBase64(scriptValue), iv: iv);

      final ajaxParams = 'id=$encryptedId&alias=$id&$decryptedToken';
      final ajaxRes = await _dio.get(
        '${uri.scheme}://${uri.host}/encrypt-ajax.php?$ajaxParams',
        options: Options(headers: {'X-Requested-With': 'XMLHttpRequest'})
      );

      final secondKey = enc.Key.fromUtf8(_keys['secondKey']!);
      final secondEncrypter = enc.Encrypter(enc.AES(secondKey, mode: enc.AESMode.cbc));

      final encryptedData = ajaxRes.data['data'];
      final decryptedData = secondEncrypter.decrypt(enc.Encrypted.fromBase64(encryptedData), iv: iv);
      final decoded = json.decode(decryptedData);

      final List<Map<String, String>> sources = [];
      if (decoded['source'] != null) {
        for (var s in decoded['source']) {
          sources.add({"url": s['file'], "quality": "HLS (Auto)"});
        }
      }
      if (decoded['source_bk'] != null) {
        for (var s in decoded['source_bk']) {
          sources.add({"url": s['file'], "quality": "Backup"});
        }
      }
      return sources;
    } catch (e) {
      print('GogoCDN extraction error: $e');
      return [];
    }
  }

  Future<String?> resolveSource(String url) async => url;
}
