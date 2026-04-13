import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../models/anime_media.dart';
import 'details_screen.dart';
import 'search_screen.dart';
import 'package:shimmer/shimmer.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendingAsync = ref.watch(trendingAnimeProvider);

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
          IconButton(icon: const Icon(Icons.person_outline), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero / Trending Header
            trendingAsync.when(
              data: (animeList) => _TrendingHeader(key: const ValueKey('trending'), anime: animeList.first),
              loading: () => const _LoadingBanner(),
              error: (e, s) => const SizedBox(height: 300, child: Center(child: Text('Error loading trending'))),
            ),
            
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

class _TrendingHeader extends StatelessWidget {
  final AnimeMedia anime;
  const _TrendingHeader({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 450,
      width: double.infinity,
      child: Stack(
        children: [
          CachedNetworkImage(
            imageUrl: anime.bannerUrl ?? anime.coverUrl ?? '',
            fit: BoxFit.cover,
            height: 450,
            width: double.infinity,
            errorWidget: (c, u, e) => Container(color: Colors.grey[900]),
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF0F1117).withValues(alpha: 0.8),
                  const Color(0xFF0F1117),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            bottom: 20,
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
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(genre, style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                        side: const BorderSide(color: Colors.white),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      ),
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
      loading: () => _LoadingList(),
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
