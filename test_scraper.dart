import 'lib/api/scraper_api.dart';

void main() async {
  final api = ScraperApi();
  print('Searching for "Dorohedoro Season 2"...');
  final results = await api.search('Dorohedoro Season 2');
  
  if (results.isEmpty) {
    print('No results found.');
    return;
  }
  
  final show = results.first;
  print('Found: ${show['name']} (ID: ${show['id']})');
  
  print('Fetching episodes...');
  final episodes = await api.getEpisodesList(show['id']);
  if (episodes.isEmpty) {
    print('No episodes found.');
    return;
  }
  
  final lastEp = episodes.last;
  print('Fetching sources for episode $lastEp...');
  final sources = await api.getSources(show['id'], lastEp);
  
  if (sources.isEmpty) {
    print('No sources found.');
  } else {
    for (var s in sources) {
      print('Source: ${s['name']} - Base URL: ${s['url']}');
      final resolved = await api.resolveSource(s['url']!);
      print('  -> Resolved: $resolved');
    }
  }
}
