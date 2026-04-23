import 'dart:ui';
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
      backgroundColor: const Color(0xFF0A0C12),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 350,
            pinned: true,
            backgroundColor: const Color(0xFF0A0C12),
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withOpacity(0.4),
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Color(0xFF0A0C12)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),
                  Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ],
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
                  // Rating row removed as per user request
                  showIdAsync.when(
                    data: (id) {
                      if (id == null) return const SizedBox.shrink();
                      return ref.watch(showDetailsProvider(id)).when(
                        data: (details) {
                          final description = (details?.description != null && details!.description!.isNotEmpty) 
                              ? details.description 
                              : anime.description;
                          final genres = details?.genres ?? anime.genres;
                          final meta = details?.extras ?? {};
                          
                          // Deduplicate title from other names
                          String? otherNames = meta['otherNames'];
                          if (otherNames != null && (otherNames == anime.title || otherNames == 'N/A')) {
                            otherNames = null;
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2130),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (otherNames != null) _detailRow('Alternative', otherNames),
                                    Row(
                                      children: [
                                        Expanded(child: _detailRow('Type', meta['type'] ?? 'TV')),
                                        Expanded(child: _detailRow('Status', meta['status'] ?? 'Unknown')),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        if (meta['episodes'] != 'N/A' && meta['episodes'] != null)
                                          Expanded(child: _detailRow('Episodes', meta['episodes'])),
                                        if (meta['duration'] != 'N/A' && meta['duration'] != null)
                                          Expanded(child: _detailRow('Duration', meta['duration'])),
                                      ],
                                    ),
                                    if (meta['premiered'] != 'N/A' && meta['premiered'] != null) 
                                      _detailRow('Premiered', meta['premiered']),
                                    if (meta['studios'] != 'N/A' && meta['studios'] != null) 
                                      _detailRow('Studios', meta['studios']),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Plot Summary',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                description?.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '') ?? 'No description available.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  height: 1.6,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              if (genres.isNotEmpty) ...[
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: genres.map((g) => ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.08),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                                        ),
                                        child: Text(
                                          g, 
                                          style: const TextStyle(
                                            fontSize: 12, 
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )).toList(),
                                ),
                              ],
                            ],
                          );
                        },
                        loading: () => const LinearProgressIndicator(minHeight: 2),
                        error: (e, s) => Text(anime.description ?? 'No description available.'),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (e, s) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 24),
                  const _EpisodeSectionHeader(),
                  const SizedBox(height: 16),
                  const _EpisodeSearchField(),
                  const SizedBox(height: 16),
                  showIdAsync.when(
                    data: (id) => id != null 
                        ? _ResponsiveEpisodeList(anime: anime, showId: id)
                        : const Center(child: Text('No streaming source found.')),
                    loading: () => const LinearProgressIndicator(),
                    error: (e, s) => Text('Error: $e'),
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
          try {
            // 1. Try to get direct MP4 download links first
            final downloadPageUrl = await scraper.getDownloadPageUrl(showId, episode);
            if (downloadPageUrl != null) {
              final directLinks = await scraper.getDirectDownloadTable(downloadPageUrl);
              if (directLinks.isNotEmpty) {
                // 1. Prioritize "Gogo server" (which are direct MP4s)
                // 2. Then prioritize high quality (1080P/720P)
                final bestLink = directLinks.firstWhere(
                  (l) => l['name']!.toLowerCase().contains('gogo') && (l['name']!.contains('1080P') || l['name']!.contains('720P')),
                  orElse: () => directLinks.firstWhere(
                    (l) => l['name']!.toLowerCase().contains('gogo'),
                    orElse: () => directLinks.firstWhere(
                      (l) => l['name']!.contains('1080P') || l['name']!.contains('720P'),
                      orElse: () => directLinks.first,
                    ),
                  ),
                );

                ref.read(downloadProvider.notifier).startDownload(
                  animeId: animeId,
                  showId: showId,
                  title: title,
                  episode: episode,
                  sourceUrl: bestLink['url']!,
                  bannerUrl: bannerUrl,
                  referer: downloadPageUrl,
                );
                return;
              }
            }

            // 2. Fallback to stream sources if direct download table fails
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
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Download error: $e")));
            }
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

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _EpisodeSectionHeader extends ConsumerWidget {
  const _EpisodeSectionHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedModeProvider);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Episodes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'sub', label: Text('Sub'), icon: Icon(Icons.closed_caption_rounded)),
            ButtonSegment(value: 'dub', label: Text('Dub'), icon: Icon(Icons.mic_rounded)),
          ],
          selected: {mode},
          onSelectionChanged: (newSelection) {
            ref.read(selectedModeProvider.notifier).state = newSelection.first;
          },
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: Theme.of(context).primaryColor,
          ),
        ),
      ],
    );
  }
}

class _EpisodeSearchField extends ConsumerWidget {
  const _EpisodeSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextField(
      onChanged: (v) => ref.read(episodeSearchProvider.notifier).state = v,
      decoration: InputDecoration(
        hintText: 'Search episode number...',
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1E2130),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE53935)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
    );
  }
}

class _ResponsiveEpisodeList extends ConsumerWidget {
  final AnimeMedia anime;
  final String showId;
  const _ResponsiveEpisodeList({required this.anime, required this.showId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedModeProvider);
    final searchQuery = ref.watch(episodeSearchProvider);
    final historyAsync = ref.watch(historyProvider);

    return ref.watch(episodesProvider((showId: showId, mode: mode))).when(
          data: (eps) {
            final filteredEps = eps.where((e) => e.toLowerCase().contains(searchQuery.toLowerCase())).toList();
            if (filteredEps.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No episodes found matching your search.')));

            final screenWidth = MediaQuery.of(context).size.width;
            final isWide = screenWidth > 800;

            if (!isWide) {
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: filteredEps.length,
                itemBuilder: (c, i) {
                  final epNum = filteredEps[i];
                  final originalIndex = eps.indexOf(epNum);
                  final progress = historyAsync.value?['${showId}_$epNum'];
                  final isWatched = progress != null && progress.percent > 0.95;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isWatched ? const Color(0xFF151720) : const Color(0xFF1E2130),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isWatched ? const Color(0xFFE53935).withOpacity(0.3) : Colors.white.withOpacity(0.05)),
                    ),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (c) => VideoPlayerScreen(
                              animeId: anime.id,
                              showId: showId,
                              episodes: eps,
                              initialIndex: originalIndex,
                              mode: mode,
                              title: anime.title,
                              imageUrl: anime.coverUrl,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isWatched ? const Color(0xFFE53935) : Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  epNum,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Episode $epNum',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  if (progress != null && !isWatched) ...[
                                    const SizedBox(height: 8),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: progress.percent,
                                        minHeight: 4,
                                        color: Colors.red,
                                        backgroundColor: Colors.white10,
                                      ),
                                    ),
                                  ] else if (isWatched)
                                    const Text('Watched', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            _DownloadButton(
                              animeId: anime.id,
                              showId: showId,
                              title: anime.title,
                              episode: epNum,
                              bannerUrl: anime.coverUrl,
                              scraper: ScraperApi(),
                              mode: mode,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            final crossAxisCount = screenWidth > 1200 ? 15 : 10;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3,
              ),
              itemCount: filteredEps.length,
              itemBuilder: (c, i) {
                final epNum = filteredEps[i];
                final originalIndex = eps.indexOf(epNum);
                final progress = historyAsync.value?['${showId}_$epNum'];
                final isWatched = progress != null && progress.percent > 0.9;

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => VideoPlayerScreen(
                          animeId: anime.id,
                          showId: showId,
                          episodes: eps,
                          initialIndex: originalIndex,
                          mode: mode,
                          title: anime.title,
                          imageUrl: anime.coverUrl,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isWatched 
                          ? const Color(0xFF151720)
                          : const Color(0xFF1E2130),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isWatched 
                            ? const Color(0xFFE53935).withOpacity(0.3)
                            : Colors.white.withOpacity(0.05),
                      ),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Text(
                            epNum,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isWatched ? const Color(0xFFE53935) : Colors.white,
                            ),
                          ),
                        ),
                        if (progress != null && progress.percent > 0 && !isWatched)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                              child: LinearProgressIndicator(
                                value: progress.percent,
                                backgroundColor: Colors.transparent,
                                color: Colors.red,
                                minHeight: 3,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: _DownloadButton(
                            animeId: anime.id,
                            showId: showId,
                            title: anime.title,
                            episode: epNum,
                            bannerUrl: anime.coverUrl,
                            scraper: ScraperApi(),
                            mode: mode,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => Center(child: Text('Error: $e')),
        );
  }
}
