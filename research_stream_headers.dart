import 'package:dio/dio.dart';
import 'lib/api/scraper_api.dart';

void main() async {
  final api = ScraperApi();
  final dio = Dio();
  
  print('Searching and resolving a source...');
  final search = await api.search('One Piece');
  final id = search.first['id'];
  final eps = await api.getEpisodesList(id);
  final sources = await api.getSources(id, eps.last);
  
  if (sources.isEmpty) return;
  
  final source = sources.first;
  final url = await api.resolveSource(source['url']!);
  print('Resolved URL: $url');
  
  if (url == null) return;

  try {
    print('Checking headers for the resolved URL...');
    final response = await dio.head(
      url,
      options: Options(headers: {
        'User-Agent': ScraperApi.userAgent,
        'Referer': ScraperApi.baseUrl,
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
}
