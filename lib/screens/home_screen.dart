import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../providers/history_provider.dart';
import '../models/anime_media.dart';
import 'details_screen.dart';
import 'downloads_screen.dart';
import 'search_screen.dart';
import 'terminal_screen.dart';
import 'video_player_screen.dart';
import 'package:shimmer/shimmer.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingAnimeProvider);
    final recentHistory = ref.watch(recentHistoryProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0C12),
          extendBodyBehindAppBar: true,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(kToolbarHeight),
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AppBar(
                  backgroundColor: const Color(0xFF0A0C12).withOpacity(0.5),
                  elevation: 0,
                  title: const Text(
                    'AniNode',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 1.2),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const SearchScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_rounded),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const DownloadsScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.terminal),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (c) => const TerminalScreen()),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded),
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: const Color(0xFF1E2130),
                            title: const Text('Logout', style: TextStyle(color: Colors.white)),
                            content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(c),
                                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                              ),
                              TextButton(
                                onPressed: () {
                                  ref.read(authProvider.notifier).logout();
                                  Navigator.pop(c);
                                },
                                child: const Text(
                                  'Logout',
                                  style: TextStyle(color: Color(0xFFE53935)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero / Trending Header
                trendingAsync.when(
                  data: (animeList) =>
                      _TrendingHeroSlider(animeList: animeList, isWide: isWide),
                  loading: () => const _LoadingBanner(),
                  error: (e, s) => const SizedBox(
                    height: 300,
                    child: Center(child: Text('Error loading trending')),
                  ),
                ),

                // Recently Watched Section
                if (recentHistory.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 12),
                    child: Text(
                      'Continue Watching',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _RecentHistoryList(history: recentHistory, isWide: isWide),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trending Now',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SCardList(asyncValue: trendingAsync, isGrid: isWide),

                      const SizedBox(height: 40),
                      const Text(
                        'Popular Series',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SCardList(asyncValue: trendingAsync, isGrid: isWide),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentHistoryList extends ConsumerWidget {
  final List<WatchProgress> history;
  final bool isWide;
  const _RecentHistoryList({required this.history, this.isWide = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: isWide ? 280 : 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: history.length,
        itemBuilder: (c, i) {
          final item = history[i];
          return Container(
            width: isWide ? 180 : 240,
            margin: const EdgeInsets.symmetric(horizontal: 6),
            child: GestureDetector(
              onTap: () async {
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
                  final eps = await ref.read(
                    episodesProvider((
                      showId: item.showId,
                      mode: item.mode,
                    )).future,
                  );
                  final index = eps.indexOf(item.episode);
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
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Could not find episode. Opening details...",
                          ),
                        ),
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
                  if (context.mounted)
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Error: $e")));
                }
              },
              child: isWide
                  ? Column(
                      // Portrait for Windows
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              children: [
                                CachedNetworkImage(
                                  imageUrl: item.imageUrl ?? '',
                                  height: double.infinity,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorWidget: (c, u, e) =>
                                      Container(color: Colors.white10),
                                ),
                                _buildOverlay(item),
                              ],
                            ),
                          ),
                        ),
                        _buildInfo(item),
                      ],
                    )
                  : ClipRRect(
                      // Wide for Mobile
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2130),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: item.imageUrl ?? '',
                              width: 240,
                              height: 180,
                              fit: BoxFit.cover,
                              errorWidget: (c, u, e) =>
                                  Container(color: Colors.white10),
                            ),
                            _buildOverlay(item),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ClipRRect(
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    color: Colors.black.withOpacity(0.6),
                                    child: _buildInfo(item, isWhite: true),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOverlay(WatchProgress item) {
    return Stack(
      children: [
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
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 4,
            color: Colors.white10,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: item.percent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE53935).withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfo(WatchProgress item, {bool isWhite = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isWhite) const SizedBox(height: 10),
        Text(
          item.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: isWhite ? Colors.white : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          'Episode ${item.episode}',
          style: TextStyle(
            color: isWhite ? Colors.white70 : Colors.white.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _TrendingHeroSlider extends StatefulWidget {
  final List<AnimeMedia> animeList;
  final bool isWide;
  const _TrendingHeroSlider({
    super.key,
    required this.animeList,
    this.isWide = false,
  });

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
      if (_pageController.hasClients && widget.animeList.isNotEmpty) {
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
      height: widget.isWide ? 600 : 480,
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
                widget.animeList.length.clamp(
                  0,
                  5,
                ), // Only show first 5 dots for cleanliness
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
    final isWide = MediaQuery.of(context).size.width > 800;

    return Stack(
      children: [
        // Background Image with Blur Effect
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
                fit: BoxFit.cover,
              ),
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: Colors.black.withOpacity(isWide ? 0.6 : 0.3)),
                ),
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
            ],
          ),
        ),
        // 2. Content Layout
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 60 : 16,
            vertical: 40,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Portrait Poster (Visible on Wide screens)
              if (isWide) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: anime.coverUrl ?? '',
                    height: 450,
                    width: 300,
                    fit: BoxFit.cover,
                    placeholder: (c, u) => Container(color: Colors.white10),
                  ),
                ),
                const SizedBox(width: 40),
              ],
              // Info Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isWide) const Spacer(),
                    Text(
                      anime.title,
                      style: TextStyle(
                        fontSize: isWide ? 42 : 28,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (var genre in anime.genres.take(3))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.15),
                                  ),
                                ),
                                child: Text(
                                  genre,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (isWide && anime.description != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 30),
                        child: Text(
                          anime.description!.replaceAll(
                            RegExp(r'<[^>]*>|&[^;]+;'),
                            '',
                          ),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 16,
                            height: 1.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE53935).withOpacity(0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE53935),
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isWide ? 32 : 24,
                                vertical: isWide ? 16 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (c) => DetailsScreen(anime: anime),
                                ),
                              );
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 28),
                            label: const Text(
                              'Watch Now',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.2),
                              width: 2,
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: isWide ? 32 : 24,
                              vertical: isWide ? 16 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (c) => DetailsScreen(anime: anime),
                              ),
                            );
                          },
                          child: const Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Bottom Gradient to blend with content
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 100,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, const Color(0xFF0A0C12)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SCardList extends StatelessWidget {
  final AsyncValue<List<AnimeMedia>> asyncValue;
  final bool isGrid;
  const SCardList({super.key, required this.asyncValue, this.isGrid = false});

  @override
  Widget build(BuildContext context) {
    return asyncValue.when(
      data: (list) {
        if (isGrid) {
          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = screenWidth > 1400
              ? 8
              : (screenWidth > 1100 ? 6 : 4);

          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: list.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.7,
            ),
            itemBuilder: (c, i) => _AnimeCard(anime: list[i]),
          );
        }

        return SizedBox(
          height: 240,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: list.length,
            itemBuilder: (c, i) => _AnimeCard(anime: list[i]),
          ),
        );
      },
      loading: () => const _LoadingList(),
      error: (e, s) => const SizedBox.shrink(),
    );
  }
}

class _AnimeCard extends StatelessWidget {
  final AnimeMedia anime;
  const _AnimeCard({required this.anime});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (c) => DetailsScreen(anime: anime)),
        );
      },
      child: Container(
        width: 150,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: anime.coverUrl ?? '',
                      height: double.infinity,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => Container(color: Colors.white10),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Text(
                              anime.extras['type'] ?? 'TV',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              anime.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
          child: Container(
            width: 140,
            margin: const EdgeInsets.all(4),
            color: Colors.white12,
          ),
        ),
      ),
    );
  }
}
