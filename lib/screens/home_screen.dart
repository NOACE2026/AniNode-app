import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../providers/history_provider.dart';
import '../models/anime_media.dart';
import 'details_screen.dart';
import 'search_screen.dart';
import 'video_player_screen.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingAnimeProvider);
    final recentHistory = ref.watch(recentHistoryProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('AniNode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => const SearchScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () {
              showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Logout'),
                  content: const Text('Are you sure you want to logout?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                    TextButton(
                      onPressed: () {
                        ref.read(authProvider.notifier).logout();
                        Navigator.pop(c);
                      },
                      child: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero / Trending Header
            trendingAsync.when(
              data: (animeList) => _TrendingHeroSlider(animeList: animeList),
              loading: () => const _LoadingBanner(),
              error: (e, s) => const SizedBox(height: 300, child: Center(child: Text('Error loading trending'))),
            ),

            // Recently Watched Section
            if (recentHistory.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Continue Watching',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              _RecentHistoryList(history: recentHistory),
            ],
            
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Trending Now',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            
            SCardList(asyncValue: trendingAsync),

            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Popular Series',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            // Reusing trending for demo popular section
            SCardList(asyncValue: trendingAsync),
          ],
        ),
      ),
    );
  }
}

class _RecentHistoryList extends ConsumerWidget {
  final List<WatchProgress> history;
  const _RecentHistoryList({required this.history});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: history.length,
        itemBuilder: (c, i) {
          final item = history[i];
          return Container(
            width: 240,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () async {
                // Show a loading dialog while we fetch the episodes list
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (c) => const Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text("Starting playback..."),
                          ],
                        ),
                      ),
                    ),
                  ),
                );

                try {
                  // Fetch the episodes list for this show and mode
                  final eps = await ref.read(episodesProvider((
                    showId: item.showId, 
                    mode: item.mode
                  )).future);

                  // Find the index of the last watched episode
                  final index = eps.indexOf(item.episode);
                  
                  // Close loading dialog
                  if (context.mounted) Navigator.pop(context);

                  if (index != -1) {
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => VideoPlayerScreen(
                            animeId: item.animeId,
                            showId: item.showId,
                            episodes: eps,
                            initialIndex: index,
                            title: item.title,
                            imageUrl: item.imageUrl,
                            mode: item.mode,
                          ),
                        ),
                      );
                    }
                  } else {
                    // Fallback to details if episode not found in list (rare)
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Could not find episode in list. Opening details..."))
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => DetailsScreen(
                            anime: AnimeMedia(
                              id: item.animeId,
                              title: item.title,
                              coverUrl: item.imageUrl,
                              genres: [],
                            ),
                          ),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error: $e"))
                    );
                  }
                }
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: item.imageUrl ?? '',
                                width: 240,
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Container(color: Colors.white10),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                ),
                              ),
                              const Center(
                                child: Icon(Icons.play_circle_outline, color: Colors.white, size: 40),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(8.0),
                          color: Colors.white.withOpacity(0.05),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Episode ${item.episode}',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: item.percent,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TrendingHeroSlider extends StatefulWidget {
  final List<AnimeMedia> animeList;
  const _TrendingHeroSlider({super.key, required this.animeList});

  @override
  State<_TrendingHeroSlider> createState() => _TrendingHeroSliderState();
}

class _TrendingHeroSliderState extends State<_TrendingHeroSlider> {
  late final PageController _pageController;
  late final Timer _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _timer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (_pageController.hasClients) {
        final nextIndex = (_currentIndex + 1) % widget.animeList.length;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 480,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: widget.animeList.length,
            itemBuilder: (context, index) {
              final anime = widget.animeList[index];
              return _HeroSlide(anime: anime);
            },
          ),
          // Page Indicator
          Positioned(
            bottom: 30,
            right: 16,
            child: Row(
              children: List.generate(
                widget.animeList.length.clamp(0, 5), // Only show first 5 dots for cleanliness
                (index) => Container(
                  width: _currentIndex == index ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: _currentIndex == index 
                        ? Theme.of(context).primaryColor 
                        : Colors.white.withOpacity(0.3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  final AnimeMedia anime;
  const _HeroSlide({required this.anime});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CachedNetworkImage(
          imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
          fit: BoxFit.cover,
          height: 480,
          width: double.infinity,
          errorWidget: (c, u, e) => Container(color: Colors.grey[900]),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                const Color(0xFF0F1117).withOpacity(0.8),
                const Color(0xFF0F1117),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          bottom: 40,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                anime.title,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var genre in anime.genres.take(3))
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(genre, style: const TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => DetailsScreen(anime: anime)));
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Watch Now'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => DetailsScreen(anime: anime)));
                    },
                    child: const Text('Details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class SCardList extends StatelessWidget {
  final AsyncValue<List<AnimeMedia>> asyncValue;
  const SCardList({super.key, required this.asyncValue});

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (list) => SizedBox(
        height: 220,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: list.length,
          itemBuilder: (c, i) {
            final anime = list[i];
            return GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (c) => DetailsScreen(anime: anime)));
              },
              child: Container(
                width: 140,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: anime.coverUrl ?? '',
                        height: 180,
                        width: 140,
                        fit: BoxFit.cover,
                        placeholder: (c, u) => Container(color: Colors.white10),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      anime.title,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      loading: () => const _LoadingList(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

class _LoadingBanner extends StatelessWidget {
  const _LoadingBanner();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.white12,
      highlightColor: Colors.white24,
      child: const SizedBox(height: 450),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (c, i) => Shimmer.fromColors(
          baseColor: Colors.white12,
          highlightColor: Colors.white24,
          child: Container(width: 140, margin: const EdgeInsets.all(4), color: Colors.white12),
        ),
      ),
    );
  }
}
