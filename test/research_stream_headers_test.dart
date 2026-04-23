import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../lib/api/scraper_api.dart';

void main() {
  test('Research Stream Headers', () async {
    final api = ScraperApi();
    final dio = Dio();
    
    print('Searching and resolving a source...');
  final search = await api.search('One Piece');
  final id = search.first['id'];
  final eps = await api.getEpisodesList(id);
  final sources = await api.getSources(id, eps.last);
  
  if (sources.isEmpty) return;
  
  final source = sources.first;
  print('Resolving source URL: ${source['url']}');
  
  if (source['url']!.contains('streaming.php') || source['url']!.contains('load.php')) {
    final res = await Dio().get(source['url']!);
    print('Iframe HTML snippet: ${res.data.toString().substring(0, 500)}');
  }

  final resolved = await api.resolveSource(source['url']!);
  final url = resolved['url'];
  final referer = resolved['referer'];
  print('Resolved URL: $url');
  
  if (url == null) return;

  try {
    print('Checking headers for the resolved URL...');
    final response = await dio.head(
      url,
      options: Options(headers: {
        'User-Agent': ScraperApi.userAgent,
        'Referer': referer ?? ScraperApi.baseUrl,
      }),
    );
    print('Content-Type: ${response.headers.value('content-type')}');
    print('Content-Length: ${response.headers.value('content-length')}');
  } catch (e) {
    print('HEAD request failed: $e');
    try {
      print('Retrying with GET (some servers block HEAD)...');
      final response = await dio.get(
        url,
        options: Options(
          headers: {
            'User-Agent': ScraperApi.userAgent,
            'Referer': ScraperApi.baseUrl,
          },
          responseType: ResponseType.stream, // Don't download the whole thing
        ),
      );
      print('Content-Type: ${response.headers.value('content-type')}');
      response.data.stream.listen((_) {}).cancel(); // Close stream
    } catch (e2) {
      print('GET request failed: $e2');
    }
    }
  });
}
