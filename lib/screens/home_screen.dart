import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/anime_provider.dart';
import '../providers/history_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/cp.dart';
import 'search_screen.dart';
import 'terminal_screen.dart';
import 'web_player_screen.dart';
import 'details_screen.dart';

enum _Badge { none, fresh, hot }

class _BrowseFooter extends StatelessWidget {
  final bool hasMore;
  final bool loading;
  const _BrowseFooter({required this.hasMore, required this.loading});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(color: CP.cyan, strokeWidth: 2),
              ),
              const SizedBox(height: 8),
              Text('LOADING MORE…',
                  style: CP.mono(size: 10, color: CP.textDim)
                      .copyWith(letterSpacing: 1.6)),
            ],
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Center(
          child: Text('END OF FEED',
              style: CP.mono(size: 10, color: CP.textMuted)
                  .copyWith(letterSpacing: 2.0)),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color accent;
  final int? count;
  const _SectionHeader(this.title, {required this.accent, this.count});

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 22,
              decoration: BoxDecoration(
                color: accent,
                boxShadow: [
                  BoxShadow(color: accent.withValues(alpha: 0.7), blurRadius: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title.toUpperCase(),
              style: CP.orbitron(size: 13, weight: FontWeight.w800, color: CP.text)
                  .copyWith(letterSpacing: 1.4),
            ),
            if (count != null) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  count.toString(),
                  style: CP.mono(size: 10, color: accent),
                ),
              ),
            ],
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Selected filter genre for the main grid. Empty string = "All".
class _SelectedGenreNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final selectedGenreProvider =
    NotifierProvider<_SelectedGenreNotifier, String>(_SelectedGenreNotifier.new);

// Sort mode for the main grid.
enum HomeSort { recent, topRated, newest }

class _SortModeNotifier extends Notifier<HomeSort> {
  @override
  HomeSort build() => HomeSort.recent;
  void set(HomeSort v) => state = v;
}

final sortModeProvider =
    NotifierProvider<_SortModeNotifier, HomeSort>(_SortModeNotifier.new);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recentHistory = ref.watch(recentHistoryProvider);
    final recentAnime = ref.watch(recentAnimeProvider);
    final browseAll = ref.watch(browseAllProvider);
    final selectedGenre = ref.watch(selectedGenreProvider);
    final sortMode = ref.watch(sortModeProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        // Use real screen height (LayoutBuilder.maxHeight is unreliable inside
        // a Scaffold-wrapped scroll view). Cap to sensible billboard heights.
        final screenH = MediaQuery.of(context).size.height;
        final heroHeight = isWide
            ? (screenH * 0.70).clamp(420.0, 720.0)
            : (screenH * 0.58).clamp(320.0, 540.0);

        final items = recentAnime.value ?? const [];

        // Derived sections from the source list.
        final featured = items.take(5).toList();
        final List<dynamic> newReleases = _newReleases(items);
        final List<dynamic> topRated = _topRated(items);
        final List<String> genres = _allGenres(items);
        final List<MapEntry<String, List<dynamic>>> genreRows =
            _genreRows(items, count: 3);

        // Main grid (paginated): filter by genre + apply sort over the
        // accumulated infinite feed.
        final browseItems = browseAll.value ?? const [];
        final browseNotifier = ref.read(browseAllProvider.notifier);
        List<dynamic> mainList = browseItems;
        if (selectedGenre.isNotEmpty) {
          mainList = mainList.where((a) {
            final g = (a.genres as List<String>?) ?? const [];
            return g.any((x) => x.toLowerCase() == selectedGenre.toLowerCase());
          }).toList();
        }
        mainList = _applySort(mainList, sortMode);

        return Scaffold(
          backgroundColor: CP.bg,
          extendBodyBehindAppBar: true,
          appBar: _CyberAppBar(isWide: isWide),
          body: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              // Fire loadMore when we're within 600px of the bottom.
              if (n.metrics.axis != Axis.vertical) return false;
              if (n.metrics.pixels >= n.metrics.maxScrollExtent - 600 &&
                  browseNotifier.hasMore &&
                  !browseNotifier.loadingMore) {
                browseNotifier.loadMore();
              }
              return false;
            },
            child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: recentAnime.when(
                  loading: () => SizedBox(
                    height: heroHeight,
                    child: const Center(
                      child: CircularProgressIndicator(color: CP.cyan, strokeWidth: 2),
                    ),
                  ),
                  error: (_, _) => SizedBox(height: heroHeight * 0.5),
                  data: (xs) => xs.isEmpty
                      ? SizedBox(height: heroHeight * 0.5)
                      : _HeroCarousel(
                          items: featured,
                          height: heroHeight,
                          isWide: isWide,
                        ),
                ),
              ),

              if (topRated.isNotEmpty) ...[
                _SectionHeader('Top 10', accent: CP.magenta, count: topRated.take(10).length),
                SliverToBoxAdapter(
                  child: _Top10Row(
                    items: topRated.take(10).toList(),
                    isWide: isWide,
                  ),
                ),
              ],

              if (recentHistory.isNotEmpty) ...[
                _SectionHeader('Continue Watching',
                    accent: CP.cyan, count: recentHistory.length),
                SliverToBoxAdapter(
                  child: _HistoryList(history: recentHistory, isWide: isWide),
                ),
              ],

              if (newReleases.isNotEmpty) ...[
                _SectionHeader('New Releases',
                    accent: CP.cyan, count: newReleases.length),
                SliverToBoxAdapter(
                  child: _PosterRow.fromList(items: newReleases, isWide: isWide, badge: _Badge.fresh),
                ),
              ],

              for (final row in genreRows) ...[
                _SectionHeader(row.key, accent: CP.cyan, count: row.value.length),
                SliverToBoxAdapter(
                  child: _PosterRow.fromList(items: row.value, isWide: isWide),
                ),
              ],

              // Filter / sort bar
              if (genres.isNotEmpty)
                _SectionHeader('Browse All', accent: CP.magenta, count: mainList.length),
              SliverToBoxAdapter(
                child: _FilterBar(
                  genres: genres,
                  selectedGenre: selectedGenre,
                  sortMode: sortMode,
                  onGenre: (g) => ref.read(selectedGenreProvider.notifier).set(g),
                  onSort: (s) => ref.read(sortModeProvider.notifier).set(s),
                ),
              ),

              if (mainList.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Text(
                      selectedGenre.isEmpty
                          ? 'No anime to show'
                          : 'No matches for "$selectedGenre"',
                      style: CP.mono(size: 12, color: CP.textMuted),
                    ),
                  ),
                )
              else if (isWide)
                _PosterGrid.fromList(items: mainList, maxWidth: constraints.maxWidth)
              else
                SliverToBoxAdapter(
                  child: _PosterRow.fromList(items: mainList, isWide: isWide),
                ),

              // Infinite-scroll footer
              SliverToBoxAdapter(
                child: _BrowseFooter(
                  hasMore: browseNotifier.hasMore,
                  loading: browseNotifier.loadingMore,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
            ),
          ),
        );
      },
    );
  }

  /// Pick the top `count` most common genres and return one (genre → items) row
  /// per genre, each capped at 12 items.
  List<MapEntry<String, List<dynamic>>> _genreRows(List<dynamic> items, {int count = 3}) {
    final freq = <String, int>{};
    for (final a in items) {
      final gs = (a.genres as List<String>?) ?? const [];
      for (final g in gs) {
        final k = g.trim();
        if (k.isEmpty) continue;
        freq[k] = (freq[k] ?? 0) + 1;
      }
    }
    final ranked = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.take(count).map((e) => e.key).toList();
    return top.map((g) {
      final rowItems = items
          .where((a) => ((a.genres as List<String>?) ?? const [])
              .any((x) => x.toLowerCase() == g.toLowerCase()))
          .take(12)
          .toList();
      return MapEntry(g, rowItems);
    }).where((e) => e.value.isNotEmpty).toList();
  }

  // ── Derivation helpers ────────────────────────────────────────────────────

  List<dynamic> _newReleases(List<dynamic> items) {
    if (items.isEmpty) return const [];
    final years = items.map((a) => a.year as int?).whereType<int>().toList();
    if (years.isEmpty) return const [];
    final maxYear = years.reduce((a, b) => a > b ? a : b);
    return items
        .where((a) => (a.year as int?) != null && a.year! >= maxYear - 0)
        .take(12)
        .toList();
  }

  List<dynamic> _topRated(List<dynamic> items) {
    final scored = items
        .where((a) => (a.score as double?) != null && a.score! > 0)
        .toList();
    scored.sort((a, b) => (b.score as double).compareTo(a.score as double));
    return scored.take(12).toList();
  }

  List<String> _allGenres(List<dynamic> items) {
    final s = <String>{};
    for (final a in items) {
      final gs = (a.genres as List<String>?) ?? const [];
      for (final g in gs) {
        if (g.trim().isNotEmpty) s.add(g.trim());
      }
    }
    final list = s.toList()..sort();
    return list;
  }

  List<dynamic> _applySort(List<dynamic> items, HomeSort mode) {
    final list = List<dynamic>.from(items);
    switch (mode) {
      case HomeSort.recent:
        return list;
      case HomeSort.topRated:
        list.sort((a, b) {
          final sa = (a.score as double?) ?? 0.0;
          final sb = (b.score as double?) ?? 0.0;
          return sb.compareTo(sa);
        });
        return list;
      case HomeSort.newest:
        list.sort((a, b) {
          final ya = (a.year as int?) ?? 0;
          final yb = (b.year as int?) ?? 0;
          return yb.compareTo(ya);
        });
        return list;
    }
  }
}

// ── Filter / sort bar ───────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final List<String> genres;
  final String selectedGenre;
  final HomeSort sortMode;
  final ValueChanged<String> onGenre;
  final ValueChanged<HomeSort> onSort;

  const _FilterBar({
    required this.genres,
    required this.selectedGenre,
    required this.sortMode,
    required this.onGenre,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sort row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Text('SORT', style: CP.mono(size: 10, color: CP.textMuted)),
                const SizedBox(width: 10),
                _sortChip('Recent', HomeSort.recent),
                const SizedBox(width: 6),
                _sortChip('Top Rated', HomeSort.topRated),
                const SizedBox(width: 6),
                _sortChip('Newest', HomeSort.newest),
              ],
            ),
          ),
          // Genre chips row (horizontal scroll)
          if (genres.isNotEmpty)
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _genreChip('All', selected: selectedGenre.isEmpty, value: ''),
                  for (final g in genres)
                    _genreChip(g,
                        selected: selectedGenre.toLowerCase() == g.toLowerCase(),
                        value: g),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sortChip(String label, HomeSort mode) {
    final isSel = sortMode == mode;
    return GestureDetector(
      onTap: () => onSort(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? CP.cyan.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
              color: CP.cyan.withValues(alpha: isSel ? 0.6 : 0.18)),
        ),
        child: Text(
          label.toUpperCase(),
          style: CP.mono(size: 10, color: isSel ? CP.cyan : CP.textDim),
        ),
      ),
    );
  }

  Widget _genreChip(String label, {required bool selected, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => onGenre(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? CP.magenta.withValues(alpha: 0.15) : CP.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? CP.magenta.withValues(alpha: 0.7)
                  : CP.cyan.withValues(alpha: 0.15),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: CP.magenta.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label.toUpperCase(),
            style: CP.mono(
              size: 11,
              color: selected ? CP.magenta : CP.text,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hero Billboard ──────────────────────────────────────────────────────────

// ── Hero carousel ───────────────────────────────────────────────────────────

class _HeroCarousel extends StatefulWidget {
  final List<dynamic> items;
  final double height;
  final bool isWide;
  const _HeroCarousel({required this.items, required this.height, required this.isWide});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _ctrl = PageController();
  int _idx = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 7), (_) {
        if (!mounted) return;
        final next = (_idx + 1) % widget.items.length;
        _ctrl.animateToPage(
          next,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _ctrl,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _idx = i),
            itemBuilder: (_, i) => _HeroBillboard(
              anime: widget.items[i],
              height: widget.height,
              isWide: widget.isWide,
            ),
          ),
          // Page indicator dots
          if (widget.items.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.items.length; i++)
                    GestureDetector(
                      onTap: () => _ctrl.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 4,
                        width: i == _idx ? 26 : 10,
                        decoration: BoxDecoration(
                          color: i == _idx
                              ? CP.cyan
                              : CP.text.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: i == _idx
                              ? CP.glow(CP.cyan, r: 8, a: 0.5)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HeroBillboard extends ConsumerWidget {
  final dynamic anime;
  final double height;
  final bool isWide;
  const _HeroBillboard({
    required this.anime,
    required this.height,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = (anime.title ?? '') as String;
    final bannerRaw = anime.bannerImage as String?;
    final posterRaw = anime.imageUrl as String?;
    final banner = (bannerRaw != null && bannerRaw.isNotEmpty)
        ? bannerRaw
        : (posterRaw ?? '');
    final genres = (anime.genres as List<String>?) ?? const <String>[];
    final desc = (anime.description as String?) ?? '';
    final year = anime.year as int?;
    final rating = anime.rating as String?;

    final hasDedicatedBanner = bannerRaw != null && bannerRaw.isNotEmpty;

    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // Backdrop image — heavily blurred when we only have the poster,
          // so upscaling doesn't look blurry/pixelated.
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: banner,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: CP.surface),
              errorWidget: (_, _, _) => Container(color: CP.surface),
            ),
          ),
          if (!hasDedicatedBanner)
            Positioned.fill(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(color: CP.bg.withValues(alpha: 0.35)),
                ),
              ),
            ),
          // Sharp poster anchored to the right on wide layouts
          if (!hasDedicatedBanner && isWide && (posterRaw?.isNotEmpty ?? false))
            Positioned(
              top: 24,
              bottom: 24,
              right: 40,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: posterRaw!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: CP.surface),
                        errorWidget: (_, _, _) => Container(color: CP.surface),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: CP.cyan.withValues(alpha: 0.25)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Top scrim (for appbar legibility) + left fade so text reads
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    CP.bg.withValues(alpha: 0.55),
                    Colors.transparent,
                    CP.bg.withValues(alpha: 0.55),
                    CP.bg,
                  ],
                  stops: const [0.0, 0.25, 0.7, 1.0],
                ),
              ),
            ),
          ),
          if (isWide)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      CP.bg.withValues(alpha: 0.85),
                      CP.bg.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 0.65],
                  ),
                ),
              ),
            ),
          // Neon side glow
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      CP.cyan.withValues(alpha: 0.06),
                      Colors.transparent,
                      CP.magenta.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Info block — keep narrow on wide screens so the poster on the
          // right stays unobscured.
          Positioned(
            left: isWide ? 40 : 20,
            right: isWide ? null : 20,
            bottom: 24,
            width: isWide ? (height * 0.9).clamp(360.0, 560.0) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Meta strip
                Row(
                  children: [
                    Container(
                      width: 3,
                      height: 14,
                      decoration: BoxDecoration(
                        color: CP.cyan,
                        boxShadow: CP.glow(CP.cyan, r: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'FEATURED',
                      style: CP.orbitron(size: 10, weight: FontWeight.w800, color: CP.cyan)
                          .copyWith(letterSpacing: 2.4),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CP.orbitron(
                    size: isWide ? 38 : 26,
                    weight: FontWeight.w900,
                  ).copyWith(
                    shadows: [
                      Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 12),
                      Shadow(color: CP.cyan.withValues(alpha: 0.3), blurRadius: 24),
                    ],
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 10),
                // Year / rating / genres
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (year != null) _metaBadge(year.toString(), CP.cyan),
                    if (rating != null && rating.isNotEmpty)
                      _metaBadge(rating, CP.yellow),
                    for (final g in genres.take(3))
                      Text(
                        g.toUpperCase(),
                        style: CP.mono(size: 10, color: CP.textDim)
                            .copyWith(letterSpacing: 1.4),
                      ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: CP.rajdhani(size: 13, color: CP.text.withValues(alpha: 0.85)),
                  ),
                ],
                const SizedBox(height: 16),
                // Action buttons
                Row(
                  children: [
                    _HeroButton(
                      icon: Icons.play_arrow_rounded,
                      label: 'PLAY',
                      filled: true,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DetailsScreen(media: anime)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _HeroButton(
                      icon: Icons.info_outline_rounded,
                      label: 'INFO',
                      filled: false,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DetailsScreen(media: anime)),
                      ),
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

  Widget _metaBadge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: CP.mono(size: 10, color: color)),
      );
}

class _HeroButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  const _HeroButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? CP.bg : CP.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? CP.cyan : CP.surface.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: filled ? CP.cyan : CP.cyan.withValues(alpha: 0.4),
          ),
          boxShadow: filled ? CP.glow(CP.cyan, r: 14, a: 0.35) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: CP.orbitron(size: 11, weight: FontWeight.w800, color: fg)
                  .copyWith(letterSpacing: 1.8),
            ),
          ],
        ),
      ),
    );
  }
}

// ── AppBar ──────────────────────────────────────────────────────────────────

class _CyberAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final bool isWide;
  const _CyberAppBar({required this.isWide});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: CP.bg.withValues(alpha: 0.45),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: kToolbarHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 16),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 24,
                      decoration: BoxDecoration(
                        color: CP.cyan,
                        boxShadow: CP.glow(CP.cyan, r: 8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (b) => const LinearGradient(
                        colors: [CP.cyan, Color(0xFF00A8CC)],
                      ).createShader(b),
                      child: Text('ANINODE', style: CP.orbitron(size: 18)),
                    ),
                    const Spacer(),
                    _iconBtn(Icons.search_rounded, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SearchScreen()))),
                    _iconBtn(Icons.terminal_rounded, () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const TerminalScreen()))),
                    _iconBtn(Icons.delete_sweep_rounded, () => _confirmClearData(context, ref)),
                    _iconBtn(Icons.power_settings_new_rounded, () => _confirmLogout(context, ref)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => IconButton(
        icon: Icon(icon, color: CP.text, size: 20),
        onPressed: onTap,
        splashRadius: 20,
      );

  void _confirmClearData(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: CP.surface,
        title: Text('CLEAR DATA', style: CP.orbitron(size: 14, color: CP.yellow)),
        content: Text(
          'This will delete all watch history and clear the browser cache.',
          style: CP.rajdhani(color: CP.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('CANCEL', style: CP.mono(color: CP.textDim)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await ref.read(historyProvider.notifier).clearAll();
              await InAppWebViewController.clearAllCache();
            },
            child: Text('CLEAR', style: CP.mono(color: CP.yellow)),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: CP.surface,
        title: Text('LOGOUT', style: CP.orbitron(size: 14, color: CP.magenta)),
        content: Text('Terminate current session?', style: CP.rajdhani(color: CP.textDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('CANCEL', style: CP.mono(color: CP.textDim)),
          ),
          TextButton(
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              Navigator.pop(c);
            },
            child: Text('LOGOUT', style: CP.mono(color: CP.magenta)),
          ),
        ],
      ),
    );
  }
}

// ── Continue Watching (16:9 landscape Netflix-style) ─────────────────────────

class _HistoryList extends ConsumerWidget {
  final List<WatchProgress> history;
  final bool isWide;
  const _HistoryList({required this.history, required this.isWide});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = isWide ? 170.0 : 130.0;
    final w = h * 16 / 9;
    return SizedBox(
      height: h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: history.length,
        itemBuilder: (_, i) {
          final item = history[i];
          return GestureDetector(
            onTap: () => _resume(context, ref, item),
            child: Container(
              width: w,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: CP.magenta.withValues(alpha: 0.18),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ],
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: item.imageUrl ?? '',
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(color: CP.surface),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, CP.bg.withValues(alpha: 0.95)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.45, 1.0],
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_outline_rounded,
                        color: Colors.white70, size: 38),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.title,
                                  style: CP.rajdhani(size: 13, weight: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              Text('EP ${item.episode} · ${item.mode.toUpperCase()}',
                                  style: CP.mono(size: 10, color: CP.textDim)),
                            ],
                          ),
                        ),
                        Container(
                          height: 3,
                          color: CP.surface,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: item.percent.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                color: CP.magenta,
                                boxShadow: CP.glow(CP.magenta, r: 6),
                              ),
                            ),
                          ),
                        ),
                      ],
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

  Future<void> _resume(BuildContext context, WidgetRef ref, WatchProgress item) async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: CP.cyan),
      ),
    );

    void closeDialog() {
      if (rootNav.canPop()) rootNav.pop();
    }

    void showError(String msg) {
      messenger.showSnackBar(SnackBar(
        content: Text(msg, style: CP.mono(size: 12, color: CP.text)),
        backgroundColor: CP.surface,
        duration: const Duration(seconds: 3),
      ));
    }

    // Fast path: history already has the exact stream list captured at
    // play-time. No re-fetch, no title-search heuristics — the URLs that
    // worked then will work now.
    final saved = item.streams;
    if (saved == null || saved.isEmpty) {
      closeDialog();
      showError('No saved streams for "${item.title}". Open it from the details page once.');
      return;
    }

    final streams = saved
        .map((s) => EpisodeStream(
              number: s.number,
              subUrl: s.subUrl,
              dubUrl: s.dubUrl,
            ))
        .toList();

    var idx = streams.indexWhere((s) => s.number == item.episode);
    if (idx == -1) idx = 0;

    closeDialog();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPlayerScreen(
          animeId: item.animeId,
          showId: item.showId,
          episodes: streams,
          initialIndex: idx,
          title: item.title,
          imageUrl: item.imageUrl,
          mode: item.mode,
        ),
      ),
    );
  }
}

// ── Poster grid (used on wide / desktop) ────────────────────────────────────

// ── Top 10 row (huge stylized numerals behind posters) ─────────────────────

class _Top10Row extends StatelessWidget {
  final List<dynamic> items;
  final bool isWide;
  const _Top10Row({required this.items, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final h = isWide ? 230.0 : 175.0;
    final posterW = h * 2 / 3;
    // Numeral hangs off the left of each poster. Sized so single digits and
    // "10" both read clearly without overlapping the next card.
    final numeralW = isWide ? 70.0 : 52.0;
    final cellW = posterW + numeralW * 0.7;
    return SizedBox(
      height: h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
            16 + numeralW * 0.4, 0, 16, 0), // leave room for the first numeral
        itemCount: items.length,
        itemBuilder: (_, i) {
          final a = items[i];
          final title = (a.title ?? '') as String;
          final image = (a.imageUrl ?? '') as String;
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DetailsScreen(media: a)),
            ),
            child: SizedBox(
              width: cellW,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Outlined rank numeral peeking from behind the poster
                  Positioned(
                    left: -numeralW * 0.5,
                    top: 0,
                    bottom: 0,
                    child: _RankNumeral(
                      n: i + 1,
                      height: h,
                      width: numeralW * (i == 9 ? 1.6 : 1.0),
                    ),
                  ),
                  // Poster
                  Positioned(
                    right: 4,
                    top: 0,
                    bottom: 0,
                    width: posterW,
                    child: _HoverScale(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: CP.magenta.withValues(alpha: 0.18),
                              blurRadius: 16,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: image,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: CP.surface),
                              errorWidget: (_, _, _) => Container(color: CP.surface),
                            ),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    CP.bg.withValues(alpha: 0.92),
                                  ],
                                  stops: const [0.55, 1.0],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 8,
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: CP.rajdhani(size: 12, weight: FontWeight.w700),
                              ),
                            ),
                          ],
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

class _RankNumeral extends StatelessWidget {
  final int n;
  final double height;
  final double width;
  const _RankNumeral({required this.n, required this.height, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.center,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Layer 1: Ambient soft blur neon glow (magenta)
            Text(
              n.toString(),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w900,
                height: 1,
                color: CP.magenta.withValues(alpha: 0.35),
                shadows: [
                  Shadow(
                    color: CP.magenta.withValues(alpha: 0.8),
                    blurRadius: 28,
                  ),
                  Shadow(
                    color: CP.magenta.withValues(alpha: 0.5),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
            // Layer 2: Thick background-colored boundary stroke (knockout separation)
            Text(
              n.toString(),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w900,
                height: 1,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 9
                  ..strokeCap = StrokeCap.round
                  ..strokeJoin = StrokeJoin.round
                  ..color = CP.bg,
              ),
            ),
            // Layer 3: High-contrast bright glowing inner-stroke
            Text(
              n.toString(),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w900,
                height: 1,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3
                  ..strokeCap = StrokeCap.round
                  ..strokeJoin = StrokeJoin.round
                  ..color = CP.magenta,
              ),
            ),
            // Layer 4: Magenta gradient fill — bright pink to deep neon
            Text(
              n.toString(),
              style: TextStyle(
                fontFamily: 'Orbitron',
                fontWeight: FontWeight.w900,
                height: 1,
                foreground: Paint()
                  ..style = PaintingStyle.fill
                  ..shader = const LinearGradient(
                    colors: [
                      Color(0xFFFF7AB6), // Light pink top
                      Color(0xFFFF2D78), // Neon magenta bottom
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(Rect.fromLTWH(0, 0, 160, 200)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Tiny mouse-hover scale wrapper — desktop polish, no-op on touch.
class _HoverScale extends StatefulWidget {
  final Widget child;
  const _HoverScale({required this.child});
  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? 1.04 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  final List<dynamic> items;
  final double maxWidth;
  const _PosterGrid.fromList({
    required this.items,
    required this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('Nothing here yet',
              style: CP.mono(size: 11, color: CP.textMuted)),
        ),
      );
    }
    final list = items;
    // Target ~170px poster width; clamp column count for readability.
    final cols = (maxWidth / 190).floor().clamp(3, 8);
    return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 2 / 3,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, i) {
                final a = list[i];
                final title = (a.title ?? '') as String;
                final image = (a.imageUrl ?? '') as String;
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetailsScreen(media: a)),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: CP.cyan.withValues(alpha: 0.12),
                          blurRadius: 14,
                          spreadRadius: -4,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(color: CP.surface),
                          errorWidget: (_, _, _) => Container(color: CP.surface),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                CP.bg.withValues(alpha: 0.95),
                              ],
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.55, 1.0],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: CP.bg.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: CP.cyan.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              '#${i + 1}',
                              style: CP.mono(size: 9, color: CP.cyan),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 10,
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CP.rajdhani(size: 13, weight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: list.length,
            ),
          ),
        );
  }
}

// ── Poster row (2:3 portrait — Netflix grid feel) ───────────────────────────

class _PosterRow extends StatelessWidget {
  final List<dynamic> items;
  final bool isWide;
  final _Badge badge;
  const _PosterRow.fromList({
    required this.items,
    required this.isWide,
    this.badge = _Badge.none,
  });

  @override
  Widget build(BuildContext context) {
    final h = isWide ? 240.0 : 190.0;
    final w = h * 2 / 3;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Text('Nothing here yet',
            style: CP.mono(size: 11, color: CP.textMuted)),
      );
    }
    return SizedBox(
      height: h,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final a = items[i];
          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _PosterCard(
              anime: a,
              width: w,
              rank: null,
              badge: badge,
            ),
          );
        },
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final dynamic anime;
  final double width;
  final int? rank;
  final _Badge badge;
  const _PosterCard({
    required this.anime,
    required this.width,
    this.rank,
    this.badge = _Badge.none,
  });

  @override
  Widget build(BuildContext context) {
    final title = (anime.title ?? '') as String;
    final image = (anime.imageUrl ?? '') as String;
    final score = anime.score as double?;
    return _HoverScale(
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DetailsScreen(media: anime)),
        ),
        child: Container(
          width: width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: CP.cyan.withValues(alpha: 0.12),
                blurRadius: 14,
                spreadRadius: -4,
              ),
            ],
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: CP.surface),
                errorWidget: (_, _, _) => Container(color: CP.surface),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      CP.bg.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
              // Top-left: rank or badge
              if (rank != null)
                Positioned(
                  top: 6, left: 6,
                  child: _miniChip('#$rank', CP.yellow),
                )
              else if (badge == _Badge.fresh)
                Positioned(top: 6, left: 6, child: _miniChip('NEW', CP.cyan))
              else if (badge == _Badge.hot)
                Positioned(top: 6, left: 6, child: _miniChip('HOT', CP.magenta)),
              // Top-right: score badge
              if (score != null && score > 0)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: CP.bg.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: CP.yellow.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded, size: 10, color: CP.yellow),
                        const SizedBox(width: 2),
                        Text(
                          score.toStringAsFixed(1),
                          style: CP.mono(size: 9, color: CP.yellow),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 8, right: 8, bottom: 8,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CP.rajdhani(size: 12, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: CP.bg.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: color.withValues(alpha: 0.55)),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: -2),
          ],
        ),
        child: Text(label, style: CP.mono(size: 9, color: color)),
      );
}
