import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../api/anilist_api.dart';
import '../models/anime_media.dart';

final aniListApiProvider = Provider((ref) => AniListApi());

final trendingAnimeProvider = FutureProvider<List<AnimeMedia>>((ref) async {
  final api = ref.watch(aniListApiProvider);
  final results = await api.fetchTrending();
  return results.map((m) => AnimeMedia.fromAniList(m)).toList();
});

final searchQueryProvider = StateProvider<String>((ref) => "");

final searchResultsProvider = FutureProvider<List<AnimeMedia>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  
  final api = ref.watch(aniListApiProvider);
  final results = await api.searchAnime(query);
  return results.map((m) => AnimeMedia.fromAniList(m)).toList();
});
