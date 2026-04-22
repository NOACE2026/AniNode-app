import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/anime_media.dart';
import '../api/scraper_api.dart';
import '../providers/history_provider.dart';
import '../providers/anime_provider.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import 'video_player_screen.dart';

class DetailsScreen extends ConsumerWidget {
  final AnimeMedia anime;
  const DetailsScreen({super.key, required this.anime});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedModeProvider);
    // If the ID is an Anitaku slug (contains hyphens, not a pure number), use it directly.
    // Otherwise fall back to a search to resolve the correct ID.
    final isAnitakuSlug = anime.id.contains('-') || !RegExp(r'^\d+$').hasMatch(anime.id);
    final showIdAsync = isAnitakuSlug
        ? AsyncValue.data(anime.id)
        : ref.watch(scraperIdProvider((title: anime.title, englishTitle: anime.englishTitle, mode: mode)));
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black.withOpacity(0.5),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: CachedNetworkImage(
                imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
                fit: BoxFit.cover,
                color: Colors.black.withOpacity(0.4),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Episodes', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'sub', label: Text('Sub'), icon: Icon(Icons.closed_caption)),
                          ButtonSegment(value: 'dub', label: Text('Dub'), icon: Icon(Icons.mic)),
                        ],
                        selected: {mode},
                        onSelectionChanged: (newSelection) {
                          ref.read(selectedModeProvider.notifier).state = newSelection.first;
                        },
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          selectedForegroundColor: Colors.white,
                          selectedBackgroundColor: Theme.of(context).primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  showIdAsync.when(
                    data: (id) {
                      if (id == null) return const Center(child: Text('No streaming source found for this series.'));
                      return ref.watch(episodesProvider((showId: id, mode: mode))).when(
                        data: (eps) => ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: eps.length,
                          itemBuilder: (c, i) {
                            final epNum = eps[i];
                            final history = historyAsync.value;
                            final progress = history?['${id}_$epNum'];

                            return Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                                  leading: Container(
                                    width: 45,
                                    height: 45,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.white10),
                                    ),
                                    child: Text(epNum, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  title: Text('Episode $epNum'),
                                  trailing: SizedBox(
                                    width: 100,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        _DownloadButton(
                                          animeId: anime.id,
                                          showId: id,
                                          title: anime.title,
                                          episode: epNum,
                                          bannerUrl: anime.coverUrl,
                                          scraper: ScraperApi(),
                                          mode: mode,
                                        ),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.play_circle_fill, color: Colors.white54),
                                      ],
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (c) => VideoPlayerScreen(
                                          animeId: anime.id,
                                          showId: id,
                                          episodes: eps,
                                          initialIndex: i,
                                          mode: mode,
                                          title: anime.title,
                                          imageUrl: anime.coverUrl,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (progress != null && progress.percent > 0)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: progress.percent,
                                        backgroundColor: Colors.white10,
                                        color: Colors.red,
                                        minHeight: 3,
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
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

class _DownloadButton extends ConsumerWidget {
  final String animeId;
  final String showId;
  final String title;
  final String episode;
  final String? bannerUrl;
  final ScraperApi scraper;
  final String mode;

  const _DownloadButton({
    required this.animeId,
    required this.showId,
    required this.title,
    required this.episode,
    this.bannerUrl,
    required this.scraper,
    required this.mode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider);
    final id = "${showId}_$episode";
    final item = downloads[id];

    if (item == null) {
      return IconButton(
        icon: const Icon(Icons.download_for_offline_outlined, size: 20),
        onPressed: () async {
          // Find source URL before starting download
          try {
            final sources = await scraper.getSources(showId, episode, mode: mode);
            if (sources.isNotEmpty) {
              final bestSource = sources.first['url'];
              if (bestSource != null) {
                ref.read(downloadProvider.notifier).startDownload(
                  animeId: animeId,
                  showId: showId,
                  title: title,
                  episode: episode,
                  sourceUrl: bestSource,
                  bannerUrl: bannerUrl,
                );
              }
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
          }
        },
      );
    }

    switch (item.status) {
      case DownloadStatus.downloading:
        return Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                value: item.progress,
                strokeWidth: 2,
                backgroundColor: Colors.white10,
              ),
            ),
            Text(
              "${(item.progress * 100).toInt()}%",
              style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
            ),
          ],
        );
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20);
      case DownloadStatus.failed:
        return IconButton(
          icon: const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
          onPressed: () {
             // Retry or remove? For now just remove and let user click download again
             ref.read(downloadProvider.notifier).deleteDownload(id);
          },
        );
      default:
        return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    }
  }
}
