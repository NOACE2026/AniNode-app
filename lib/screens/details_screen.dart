import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_media.dart';
import '../api/scraper_api.dart';
import 'video_player_screen.dart';

final episodesProvider = FutureProvider.family<List<String>, String>((ref, showId) async {
  return ScraperApi().getEpisodesList(showId);
});

final scraperIdProvider = FutureProvider.family<String?, ({String title, String? englishTitle})>((ref, arg) async {
  final results = await ScraperApi().search(arg.title);
  if (results.isNotEmpty) return results.first['id'];
  if (arg.englishTitle != null) {
    final engResults = await ScraperApi().search(arg.englishTitle!);
    if (engResults.isNotEmpty) return engResults.first['id'];
  }
  return null;
});

class DetailsScreen extends ConsumerWidget {
  final AnimeMedia anime;
  const DetailsScreen({super.key, required this.anime});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showIdAsync = ref.watch(scraperIdProvider((title: anime.title, englishTitle: anime.englishTitle)));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: CachedNetworkImage(
                imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
                fit: BoxFit.cover,
                color: Colors.black.withValues(alpha: 0.4),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anime.title,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (anime.score != null)
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(width: 4),
                        Text('${anime.score! / 10}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Text(' / 10', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Text(
                    anime.description?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '') ?? 'No description available.',
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 24),
                  const Text('Episodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  showIdAsync.when(
                    data: (id) {
                      if (id == null) return const Center(child: Text('No streaming source found for this series.'));
                      return ref.watch(episodesProvider(id)).when(
                        data: (eps) => ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: eps.length,
                          itemBuilder: (c, i) => ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            leading: Container(
                              width: 45,
                              height: 45,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: Text(eps[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            title: Text('Episode ${eps[i]}'),
                            trailing: const Icon(Icons.play_circle_fill, color: Colors.white54),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => VideoPlayerScreen(
                                    showId: id,
                                    episodeNumber: eps[i],
                                    title: '${anime.title} - Ep ${eps[i]}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        loading: () => const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(),
                        )),
                        error: (e, s) => Text('Error loading episodes: $e'),
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, s) => Text('Error finding series: $e'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
