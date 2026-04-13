import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart'; // Required for StateProvider in Riverpod 3.0 Alpha
import '../api/scraper_api.dart';
import '../api/anilist_api.dart';
import '../models/anime_media.dart';

// --- Shared State Providers ---

// Provides the selection of sub or dub mode
final selectedModeProvider = StateProvider<String>((ref) => 'sub');

// Current search query
final searchQueryProvider = StateProvider<String>((ref) => '');

// --- AniList API Providers ---

// Trending anime for home screen
final trendingAnimeProvider = FutureProvider<List<AnimeMedia>>((ref) async {
  final api = AniListApi();
  final results = await api.fetchTrending();
  return results.map((m) => AnimeMedia.fromAniList(m)).toList();
});

// Search results based on searchQueryProvider
final searchResultsProvider = FutureProvider<List<AnimeMedia>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  
  final api = AniListApi();
  final results = await api.searchAnime(query);
  return results.map((m) => AnimeMedia.fromAniList(m)).toList();
});

// --- Scraper API Providers ---

// Fetches the episodes list for a specific show and mode
final episodesProvider = FutureProvider.family<List<String>, ({String showId, String mode})>((ref, arg) async {
  return ScraperApi().getEpisodesList(arg.showId, mode: arg.mode);
});

// Searches for a scraper-specific ID for a given anime title and mode
final scraperIdProvider = FutureProvider.family<String?, ({String title, String? englishTitle, String mode})>((ref, arg) async {
  final results = await ScraperApi().search(arg.title, mode: arg.mode);
  if (results.isNotEmpty) return results.first['id'];
  if (arg.englishTitle != null) {
    final engResults = await ScraperApi().search(arg.englishTitle!, mode: arg.mode);
    if (engResults.isNotEmpty) return engResults.first['id'];
  }
  return null;
});
