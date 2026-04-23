import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart';

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
      
      // Better description extraction
      String description = '';
      final infoBody = document.querySelector('.anime_info_body_bg');
      final pTags = infoBody?.querySelectorAll('p.type') ?? [];
      
      for (var p in pTags) {
        final text = p.text.trim();
        if (text.toLowerCase().contains('plot summary')) {
          description = text.replaceFirst(RegExp(r'Plot Summary:?\s*', caseSensitive: false), '').trim();
          
          if (description.isEmpty) {
            // Check next element for the actual summary
            var next = p.nextElementSibling;
            if (next != null && (next.localName == 'p' || next.localName == 'div')) {
              description = next.text.trim();
            }
          }
          break;
        }
      }

      // If still empty, check for div.description specifically
      if (description.isEmpty) {
        description = infoBody?.querySelector('div.description')?.text.trim() ?? '';
      }
      
      // Final fallback: any p that is not a 'type' class and is long
      if (description.isEmpty) {
        final allPs = infoBody?.querySelectorAll('p') ?? [];
        for (var p in allPs) {
          if (!p.classes.contains('type') && p.text.trim().length > 100) {
            description = p.text.trim();
            break;
          }
        }
      }
      
      String getVal(String label) {
        final p = pTags.where((p) => p.text.contains(label)).firstOrNull;
        return p?.text.replaceFirst(label, '').trim() ?? 'N/A';
      }

      final status = getVal('Status:');
      final type = getVal('Type:');
      final episodes = getVal('Episodes:');
      final otherNames = getVal('Other name:');
      final premiered = getVal('Premiered:');
      final released = getVal('Released:');
      final duration = getVal('Duration:');
      final studios = getVal('Studios:');
      final producers = getVal('Producers:');

      final genres = pTags.where((p) => p.text.contains('Genre:')).firstOrNull?.querySelectorAll('a')
          .map((e) => e.text.trim().replaceAll(',', ''))
          .toList() ?? [];

      if (description.isEmpty) {
        for (var p in pTags) {
          final t = p.text.trim();
          if (t.length > 100 && !t.contains(':')) {
            description = t;
            break;
          }
        }
      }
      
      return {
        "_id": showId,
        "name": title,
        "englishName": title,
        "thumbnail": image,
        "description": description,
        "genres": genres,
        "status": status,
        "type": type,
        "episodes": episodes,
        "otherNames": otherNames,
        "premiered": premiered,
        "released": released,
        "duration": duration,
        "studios": studios,
        "producers": producers,
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
      // Ensure we have a clean ID
      final cleanShowId = showId.split('/').last.split('-episode-').first;
      final epId = '$cleanShowId-episode-$epNumber';
      final response = await _dio.get('$baseUrl/$epId');
      final document = parser.parse(response.data);

      final List<Map<String, String>> sources = [];
      final Set<String> seenUrls = {};
      final Set<String> seenNames = {};

      // 1. Try common GogoAnime/Anitaku selectors
      final serverLinks = document.querySelectorAll('.anime_muti_link ul li a, .server-video li a, .list-server-items li a');
      
      for (var a in serverLinks) {
        final name = a.text.trim().replaceAll('Choose this server', '').trim();
        final videoUrl = a.attributes['data-video'];
        if (videoUrl != null && name.isNotEmpty) {
          final fullUrl = videoUrl.startsWith('http') ? videoUrl : 'https:$videoUrl';
          // Deduplicate by URL AND Name to be safe
          if (!seenUrls.contains(fullUrl) && !seenNames.contains(name.toLowerCase())) {
            sources.add({
              'name': name,
              'url': fullUrl,
            });
            seenUrls.add(fullUrl);
            seenNames.add(name.toLowerCase());
          }
        }
      }

      // 2. Fallback to any element with data-video if still empty
      if (sources.isEmpty) {
        final dataVideoElements = document.querySelectorAll('[data-video]');
        for (var el in dataVideoElements) {
          final videoUrl = el.attributes['data-video'];
          if (videoUrl != null && videoUrl.contains('http')) {
            final name = el.text.trim().isEmpty ? "Server ${sources.length + 1}" : el.text.trim();
            if (!seenUrls.contains(videoUrl) && !seenNames.contains(name.toLowerCase())) {
              sources.add({
                'name': name,
                'url': videoUrl,
              });
              seenUrls.add(videoUrl);
              seenNames.add(name.toLowerCase());
            }
          }
        }
      }

      return sources;
    } catch (e) {
      print('Sources error: $e');
      return [];
    }
  }

  /// Resolves a raw iframe URL into a playable stream URL
  /// Returns a map with 'url' and 'referer'
  Future<Map<String, String?>> resolveSource(String iframeUrl) async {
    try {
      if (iframeUrl.isEmpty) return {'url': null, 'referer': null};
      
      // Handle protocol-relative URLs
      String url = iframeUrl.startsWith('//') ? 'https:$iframeUrl' : iframeUrl;
      debugPrint('AniNode: Resolving source: $url');

      // --- VibePlayer (HD-1, HD-2) ---
      if (url.contains('vibeplayer.site')) {
        return await _resolvePlayerPage(url, baseUrl);
      }

      // --- VidHide / OtakuHG / OtakuVid (same engine) ---
      if (url.contains('otakuhg.site') || 
          url.contains('otakuvid.online') || 
          url.contains('vidhide') ||
          url.contains('vidhidevip')) {
        return await _resolveVidHide(url);
      }

      // --- GogoCDN / Vidstreaming / Gogo Server ---
      if (url.contains('gogocdn.com') || 
          url.contains('streaming.php') || 
          url.contains('load.php') ||
          url.contains('embed.php') ||
          url.contains('taku') ||
          url.contains('embtaku')) {
        final gogoSources = await _extractGogoCDN(url);
        if (gogoSources.isNotEmpty) {
          debugPrint('AniNode: Decrypted GogoCDN source: ${gogoSources.first['url']}');
          return {
            'url': gogoSources.first['url'],
            'referer': url
          };
        }
        // Fallback: try to extract m3u8 from page HTML
        return await _resolvePlayerPage(url, url);
      }

      // --- Doodstream ---
      if (url.contains('dood') || url.contains('d0000d') || url.contains('doodrive')) {
        return await _resolveDoodstream(url);
      }

      // --- Streamwish / Streameast / Swish ---
      if (url.contains('streamwish') || url.contains('swish') || url.contains('wishembed')) {
        return await _resolvePlayerPage(url, url);
      }

      // --- Mp4upload ---
      if (url.contains('mp4upload')) {
        return await _resolvePlayerPage(url, url);
      }

      // --- Filemoon ---
      if (url.contains('filemoon') || url.contains('filemooon')) {
        return await _resolvePlayerPage(url, url);
      }

      // --- Direct stream link ---
      if (url.contains('.m3u8') || url.contains('.mp4')) {
        return {'url': url, 'referer': url};
      }

      // --- Generic fallback: fetch any iframe page and look for stream URL ---
      if (url.startsWith('http')) {
        final generic = await _resolvePlayerPage(url, url);
        if (generic['url'] != null) return generic;
      }

      return {'url': null, 'referer': null};
    } catch (e) {
      debugPrint('AniNode: Resolve error: $e');
      return {'url': null, 'referer': null};
    }
  }

  /// Generic: fetch a player page and extract any .m3u8 or .mp4 URL from its HTML/JS
  Future<Map<String, String?>> _resolvePlayerPage(String pageUrl, String referer) async {
    try {
      final response = await _dio.get(
        pageUrl,
        options: Options(headers: {
          'User-Agent': userAgent,
          'Referer': referer,
        })
      );
      final html = response.data as String;

      // Look for stream URLs: const src = "...", file: "...", etc.
      final patterns = [
        RegExp(r'(?:const\s+src|file)\s*[=:]\s*"([^"]+\.m3u8[^"]*)"'),
        RegExp(r'"file"\s*:\s*"([^"]+\.m3u8[^"]*)"'),
        RegExp(r'source\s*:\s*"([^"]+\.m3u8[^"]*)"'),
        RegExp(r'https?://[^\s"]+\.m3u8[^\s"]*'),
        RegExp(r'https?://[^\s"]+\.mp4[^\s"]*'),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final streamUrl = (match.groupCount >= 1 && match.group(1) != null)
              ? match.group(1)!
              : match.group(0)!;
          debugPrint('AniNode: Extracted from player page: $streamUrl');
          return {'url': streamUrl, 'referer': pageUrl};
        }
      }
    } catch (e) {
      debugPrint('AniNode: Player page fetch error ($pageUrl): $e');
    }
    return {'url': null, 'referer': null};
  }

  /// VidHide engine (OtakuHG, OtakuVid, VidHide) 
  /// These sites pack JS but expose the token in the URL and CDN info in the script
  Future<Map<String, String?>> _resolveVidHide(String pageUrl) async {
    try {
      // Extract the video token from URL path
      final uri = Uri.parse(pageUrl);
      final token = uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      if (token.isEmpty) return {'url': null, 'referer': null};

      // Fetch the page to find the CDN subdomain from the packed JS
      final response = await _dio.get(
        pageUrl,
        options: Options(headers: {
          'User-Agent': userAgent,
          'Referer': pageUrl,
        })
      );
      final html = response.data as String;

      // The packed JS contains the CDN info. Look for the CDN domain after 'dramiyos' or similar
      // Pattern in the key array: 'cdn|dramiyos', 'hls4', token pattern
      final cdnMatch = RegExp(r"'([a-z0-9]+)\.dramiyos\.com'").firstMatch(html);
      if (cdnMatch != null) {
        final cdnSub = cdnMatch.group(1)!;
        final streamUrl = 'https://$cdnSub.dramiyos.com/hls4/${token}_o/$token.m3u8';
        debugPrint('AniNode: VidHide CDN URL: $streamUrl');
        return {'url': streamUrl, 'referer': pageUrl};
      }
      
      // Fallback: try the standard pattern with the token
      // The packed JS key array typically contains: tqcjvlkmh41z_o pattern
      final tokenMatch = RegExp('${token}_o').hasMatch(html);
      if (tokenMatch) {
        // Use a known CDN prefix - try dramiyos first
        final streamUrl = 'https://pix.dramiyos.com/hls4/${token}_o/$token.m3u8';
        return {'url': streamUrl, 'referer': pageUrl};
      }

      // Last resort: use generic page extractor 
      return await _resolvePlayerPage(pageUrl, pageUrl);
    } catch (e) {
      debugPrint('AniNode: VidHide error: $e');
      return {'url': null, 'referer': null};
    }
  }

  /// Doodstream requires a two-step request to get a token-signed URL
  Future<Map<String, String?>> _resolveDoodstream(String pageUrl) async {
    try {
      final response = await _dio.get(pageUrl, options: Options(headers: {'User-Agent': userAgent}));
      final pageHtml = response.data as String;

      // Extract the pass_md5 path
      final passMatch = RegExp(r'/pass_md5/[^"]+').firstMatch(pageHtml);
      if (passMatch == null) return {'url': null, 'referer': null};
      
      final passMd5Path = passMatch.group(0)!;
      final uri = Uri.parse(pageUrl);
      final md5Url = '${uri.scheme}://${uri.host}$passMd5Path';

      final md5Res = await _dio.get(
        md5Url,
        options: Options(headers: {
          'Referer': pageUrl,
          'User-Agent': userAgent,
        })
      );
      
      final token = DateTime.now().millisecondsSinceEpoch;
      final streamUrl = '${md5Res.data}zoa?token=$token&expiry=$token';
      debugPrint('AniNode: Doodstream URL: $streamUrl');
      return {'url': streamUrl, 'referer': pageUrl};
    } catch (e) {
      debugPrint('AniNode: Doodstream error: $e');
      return {'url': null, 'referer': null};
    }
  }

  Future<List<Map<String, String>>> _extractGogoCDN(String iframeUrl) async {
    try {
      final uri = Uri.parse(iframeUrl);
      final id = uri.queryParameters['id'];
      if (id == null) return [];

      // Fetch iframe with referer
      final response = await _dio.get(
        iframeUrl,
        options: Options(headers: {
          'Referer': baseUrl,
          'User-Agent': userAgent,
        })
      );
      final document = parser.parse(response.data);

      // Known key sets used by various mirrors
      final List<Map<String, String>> keySets = [
        {
          'key': '37911490979715163134003223491201',
          'secondKey': '54674138327930866480207815084989',
          'iv': '3134003223491201',
        },
        {
          'key': '38343935333835363239333237323134',
          'secondKey': '54674138327930866480207815084989',
          'iv': '3132333435363738',
        },
        {
          'key': '32313531323331323531323531323531',
          'secondKey': '54674138327930866480207815084989',
          'iv': '3132333132333132',
        }
      ];

      for (var keys in keySets) {
        try {
          final key = enc.Key.fromUtf8(keys['key']!);
          final iv = enc.IV.fromUtf8(keys['iv']!);
          final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));

          final encryptedId = encrypter.encrypt(id, iv: iv).base64;

          // Some mirrors use different script selectors
          final scriptElement = document.querySelector("script[data-name='episode']") ?? 
                              document.querySelector("script[data-value]");
          
          final scriptValue = scriptElement?.attributes['data-value'];
          if (scriptValue == null) continue;

          String decryptedToken;
          try {
            decryptedToken = encrypter.decrypt(enc.Encrypted.fromBase64(scriptValue), iv: iv);
          } catch (e) {
            continue; // Try next key set
          }

          final ajaxParams = 'id=$encryptedId&alias=$id&$decryptedToken';
          
          final List<String> ajaxEndpoints = ['/encrypt-ajax.php', '/ajax.php', '/encrypt.php'];
          dynamic ajaxData;

          for (var endpoint in ajaxEndpoints) {
            try {
              final res = await _dio.get(
                '${uri.scheme}://${uri.host}$endpoint?$ajaxParams',
                options: Options(headers: {
                  'X-Requested-With': 'XMLHttpRequest',
                  'Referer': iframeUrl,
                  'User-Agent': userAgent,
                })
              );
              if (res.data != null && res.data['data'] != null) {
                ajaxData = res.data['data'];
                break;
              }
            } catch (_) {}
          }

          if (ajaxData == null) continue;

          final secondKey = enc.Key.fromUtf8(keys['secondKey']!);
          final secondEncrypter = enc.Encrypter(enc.AES(secondKey, mode: enc.AESMode.cbc));

          String decryptedData;
          try {
            decryptedData = secondEncrypter.decrypt(enc.Encrypted.fromBase64(ajaxData), iv: iv);
          } catch (e) {
            continue;
          }
          
          final decoded = json.decode(decryptedData);

          final List<Map<String, String>> sources = [];
          if (decoded['source'] != null) {
            for (var s in decoded['source']) {
              sources.add({
                "url": s['file'], 
                "quality": s['label'] ?? "HLS (Auto)",
                "referer": iframeUrl
              });
            }
          }
          if (decoded['source_bk'] != null) {
            for (var s in decoded['source_bk']) {
              sources.add({
                "url": s['file'], 
                "quality": "Backup",
                "referer": iframeUrl
              });
            }
          }
          
          if (sources.isNotEmpty) return sources;
        } catch (e) {
          debugPrint('AniNode: Key set decryption failed: $e');
        }
      }

      return [];
    } catch (e) {
      debugPrint('AniNode: GogoCDN extraction error: $e');
      return [];
    }
  }

  
  Future<String?> getDownloadPageUrl(String showId, String epNumber) async {
    try {
      final epId = '$showId-episode-$epNumber';
      final response = await _dio.get('$baseUrl/$epId');
      final document = parser.parse(response.data);
      final downloadBtn = document.querySelector('li.dowloads > a');
      String? url = downloadBtn?.attributes['href'];
      if (url == null) return null;
      if (url.startsWith('//')) url = 'https:$url';
      if (!url.startsWith('http')) url = '$baseUrl$url';
      return url;
    } catch (e) {
      print('Download page error: $e');
      return null;
    }
  }

  Future<List<Map<String, String>>> getDirectDownloadTable(String downloadPageUrl) async {
    try {
      final response = await _dio.get(downloadPageUrl);
      final document = parser.parse(response.data);
      final List<Map<String, String>> links = [];

      // Support multiple GogoAnime download page structures
      final downloadLinks = document.querySelectorAll('div.dowload > a, .download-link > a, .cf-download > a');
      for (var a in downloadLinks) {
        final text = a.text.trim();
        String? url = a.attributes['href'];
        if (url != null && url.isNotEmpty) {
          if (url.startsWith('//')) url = 'https:$url';
          // No need to prepend baseUrl as these are usually external CDN links or absolute
          links.add({
            'name': text.replaceAll('Download', '').trim(),
            'url': url,
          });
        }
      }
      return links;
    } catch (e) {
      print('Direct download table error: $e');
      return [];
    }
  }
}
