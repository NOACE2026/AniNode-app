import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/jikan_service.dart';
import '../providers/history_provider.dart';
import '../providers/anime_provider.dart';
import '../theme/cp.dart';
import 'web_player_screen.dart';
import '../api/providers/anikoto_provider.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  final dynamic media;
  const DetailsScreen({super.key, required this.media});

  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  final ScrollController _scrollCtrl = ScrollController();

  // Episode state
  final List<String> _episodes = [];
  final Map<String, JikanEpisode> _jikanData = {};
  bool _epLoading = false;
  bool _jikanLoading = false;
  String? _activeShowId;
  int? _malId;
  int? _aniId;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEpisodes());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _getMediaTitle() {
    try {
      if (widget.media.title is String) return widget.media.title;
      return widget.media.title?.preferred ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  String? _getMediaEnglishTitle() {
    try {
      if (widget.media.title is String) return null;
      return widget.media.title?.english;
    } catch (_) {
      return null;
    }
  }

  String _getMediaId() {
    try {
      final id = widget.media.id;
      return id is int ? id.toString() : (id ?? '');
    } catch (_) {
      return '';
    }
  }

  int? _getMediaScore() {
    try {
      // Try AniList averageScore
      if (widget.media.averageScore is int) return widget.media.averageScore;
      // Try AnimeResult rating (numeric only)
      if (widget.media.rating is String) {
        final score = int.tryParse(widget.media.rating!);
        if (score != null) return score;
      }
    } catch (_) {}
    return null;
  }

  String _getMediaDescription() {
    try {
      if (widget.media.description is String) {
        return (widget.media.description as String)
            .replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), '');
      }
    } catch (_) {}
    return 'No description available.';
  }

  List<String> _getMediaGenres() {
    try {
      if (widget.media.genres is List) {
        return List<String>.from(widget.media.genres as List);
      }
    } catch (_) {}
    return [];
  }

  bool _hasAniListData() {
    try {
      // Check if this is an AniList object vs a scraper AnimeResult
      return widget.media.format != null || widget.media.studios != null;
    } catch (_) {
      return false;
    }
  }

  String _getBannerUrl() {
    try {
      // Try AniList-style coverImage (GraphQL) first if it exists
      if (_hasAniListData()) {
        if (widget.media.bannerImage?.isNotEmpty ?? false) {
          return widget.media.bannerImage;
        }
        if (widget.media.coverImage?.extraLarge?.isNotEmpty ?? false) {
          return widget.media.coverImage.extraLarge;
        }
        if (widget.media.coverImage?.large?.isNotEmpty ?? false) {
          return widget.media.coverImage.large;
        }
      }
      // Try AnimeResult.imageUrl (scraper API)
      if (widget.media.imageUrl is String && (widget.media.imageUrl as String).isNotEmpty) {
        return widget.media.imageUrl;
      }
    } catch (_) {}
    return '';
  }

  void _onScroll() {
    // Scroll handling disabled
  }

  int? _getMalId() {
    try {
      if (widget.media is AnimeResult) return (widget.media as AnimeResult).malId;
      return widget.media.malId as int?;
    } catch (_) { return null; }
  }

  int? _getAniListId() {
    try {
      if (widget.media is AnimeResult) return (widget.media as AnimeResult).aniId;
      final id = widget.media.id;
      return id is int ? id : null;
    } catch (_) { return null; }
  }

  int _getEpisodeCount() {
    try {
      if (widget.media is AnimeResult) return (widget.media as AnimeResult).totalEpisodes ?? 0;
      return (widget.media.episodes as int?) ?? 0;
    } catch (_) { return 0; }
  }

  Future<void> _loadEpisodes() async {
    if (_epLoading) return;

    _malId = _getMalId();
    _aniId = _getAniListId();

    if (_malId == null && _aniId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No streaming ID found for this title')),
        );
      }
      return;
    }

    _activeShowId = _malId != null ? 'mal_$_malId' : 'ani_$_aniId';

    // Show numbered placeholders immediately from the known episode count.
    final knownCount = _getEpisodeCount();
    setState(() {
      _epLoading = true;
      if (knownCount > 0) {
        _episodes.clear();
        _episodes.addAll(List.generate(knownCount, (i) => '${i + 1}'));
        _epLoading = false;
      }
    });

    // Fetch Jikan data in background — titles + filler arrive page by page.
    if (_malId != null) {
      setState(() => _jikanLoading = true);
      JikanService.fetchEpisodes(_malId!, onPage: (accumulated) {
        if (!mounted) return;
        setState(() {
          for (final ep in accumulated) {
            _jikanData[ep.number] = ep;
          }
          // If we had no count initially, grow the list as Jikan pages arrive.
          if (_episodes.length < accumulated.length) {
            _episodes.clear();
            _episodes.addAll(accumulated.map((e) => e.number));
          }
          _epLoading = false;
        });
      }).whenComplete(() {
        if (mounted) setState(() => _jikanLoading = false);
      });
    } else {
      // No MAL ID — episode count is our only source; placeholders only.
      if (mounted && knownCount == 0) {
        setState(() {
          _episodes.clear();
          _episodes.addAll(List.generate(1500, (i) => '${i + 1}'));
          _epLoading = false;
        });
      }
    }
  }

  void _play(List<String> allEps, int idx, String mode) {
    final streams = allEps.asMap().entries.map((entry) {
      final epNum = entry.value;
      final epInt = int.tryParse(epNum) ?? (entry.key + 1);
      String? sub, dub;
      if (_malId != null) {
        sub = AnikotoProvider.streamUrlByMal(_malId!, epInt, lang: 'sub');
        dub = AnikotoProvider.streamUrlByMal(_malId!, epInt, lang: 'dub');
      } else if (_aniId != null) {
        sub = AnikotoProvider.streamUrlByAniList(_aniId!, epInt, lang: 'sub');
        dub = AnikotoProvider.streamUrlByAniList(_aniId!, epInt, lang: 'dub');
      }
      return EpisodeStream(number: epNum, subUrl: sub, dubUrl: dub);
    }).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WebPlayerScreen(
          animeId: _getMediaId(),
          showId: _activeShowId ?? '',
          episodes: streams,
          initialIndex: idx,
          mode: mode,
          title: _getMediaTitle(),
          imageUrl: _getBannerUrl(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(selectedModeProvider);
    final searchQuery = ref.watch(episodeSearchProvider);
    final historyAsync = ref.watch(historyProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 800;

    // Filter already-loaded episodes by the search query
    final filtered = searchQuery.isEmpty
        ? List<String>.unmodifiable(_episodes)
        : _episodes
            .where((e) => e.toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();

    final episodeCols = screenWidth > 1200 ? 15 : 10;

    return Scaffold(
      backgroundColor: CP.bg,
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // ── Hero app bar ──────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: CP.bg,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: BoxDecoration(
                    color: CP.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: CP.cyan.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: CP.cyan, size: 18),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: CP.imgUrl(_getBannerUrl(), width: 900),
                    fit: BoxFit.cover,
                    memCacheWidth: 900,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (_, _) => CP.shimmerBox(),
                    errorWidget: (_, _, _) => Container(color: CP.surface),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CP.bg.withValues(alpha: 0.3),
                          CP.bg.withValues(alpha: 0.1),
                          CP.bg,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _ScanlinePainter(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Anime info ────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getMediaTitle(),
                    style: CP.orbitron(size: 22, weight: FontWeight.w900).copyWith(
                      shadows: [
                        Shadow(color: CP.cyan.withValues(alpha: 0.4), blurRadius: 16)
                      ],
                      height: 1.2,
                    ),
                  ),
                  if (_getMediaEnglishTitle() != null &&
                      _getMediaEnglishTitle() != _getMediaTitle()) ...[
                    const SizedBox(height: 4),
                    Text(_getMediaEnglishTitle()!,
                        style: CP.mono(size: 12, color: CP.textDim)),
                  ],
                  const SizedBox(height: 16),
                  if (_getMediaScore() != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Icon(Icons.star_rounded, color: CP.yellow, size: 16,
                              shadows: [Shadow(
                                  color: CP.yellow.withValues(alpha: 0.8),
                                  blurRadius: 8)]),
                          const SizedBox(width: 6),
                          Text('${_getMediaScore()} / 100',
                              style: CP.mono(size: 13, color: CP.yellow)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                  color: CP.surface,
                                  borderRadius: BorderRadius.circular(2)),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor:
                                    ((_getMediaScore() ?? 0) / 100).clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                        colors: [CP.cyan, CP.magenta]),
                                    borderRadius: BorderRadius.circular(2),
                                    boxShadow: CP.glow(CP.cyan, r: 6),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Metadata card (AniList only)
                  if (_hasAniListData())
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: CP.cardDecorOf(CP.cyan, glowAlpha: 0.06),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.media.format != null || (widget.media.status?.isNotEmpty ?? false))
                            _MetaRow(children: [
                              if (widget.media.format != null)
                                _MetaCell('TYPE', widget.media.format!),
                              if (widget.media.status?.isNotEmpty ?? false)
                                _MetaCell('STATUS', widget.media.status ?? ''),
                            ]),
                          if (widget.media.episodes != null || widget.media.duration != null)
                            _MetaRow(children: [
                              if (widget.media.episodes != null)
                                _MetaCell('EPISODES', widget.media.episodes.toString()),
                              if (widget.media.duration != null)
                                _MetaCell('DURATION', '${widget.media.duration} min'),
                            ]),
                          if (widget.media.seasonYear != null)
                            _MetaCell('YEAR', widget.media.seasonYear.toString()),
                          if (widget.media.studios?.isNotEmpty ?? false)
                            _MetaCell('STUDIOS', (widget.media.studios as List?)?.map((s) => s.name).join(', ') ?? ''),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                  CP.sectionLabel('SYNOPSIS'),
                  const SizedBox(height: 12),
                  Text(
                    _getMediaDescription(),
                    style: CP.rajdhani(size: 15, color: CP.textDim)
                        .copyWith(height: 1.6),
                  ),
                  if (_getMediaGenres().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _getMediaGenres()
                          .map((g) => CP.chip(g, color: CP.cyan))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Episode controls ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CP.sectionLabel('EPISODES'),
                      _SubDubToggle(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Loaded count badge
                  if (_episodes.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Text(
                            _jikanLoading
                                ? '${_episodes.length} episodes — loading titles…'
                                : '${_episodes.length} episodes',
                            style: CP.mono(size: 10, color: CP.textMuted),
                          ),
                          if (_jikanLoading) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 8, height: 8,
                              child: CircularProgressIndicator(
                                  color: CP.cyan, strokeWidth: 1.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                  const _EpisodeSearch(),
                ],
              ),
            ),
          ),

          // ── Episodes unavailable ──────────────────────────────────────────
          if (_episodes.isEmpty && !_epLoading)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text('Episodes not loaded. Use search to find streams.',
                      style: CP.mono(color: CP.textMuted)),
                ),
              ),
            ),

          // ── Initial loading ───────────────────────────────────────────────
          if (_epLoading && _episodes.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Center(
                    child: CircularProgressIndicator(color: CP.cyan, strokeWidth: 2)),
              ),
            ),

          // ── Episode grid (wide) ───────────────────────────────────────────
          if (isWide && filtered.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: episodeCols,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.5,
                ),
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final epNum = filtered[i];
                    final progress =
                        historyAsync.value?['${_activeShowId}_$epNum'];
                    final watched = progress != null && progress.percent > 0.9;
                    return _EpisodeGridCell(
                      epNum: epNum,
                      jikanEp: _jikanData[epNum],
                      progress: progress,
                      watched: watched,
                      onTap: () => _play(
                          _episodes, _episodes.indexOf(epNum), mode),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),

          // ── Episode list (mobile) ─────────────────────────────────────────
          if (!isWide && filtered.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final epNum = filtered[i];
                    final progress =
                        historyAsync.value?['${_activeShowId}_$epNum'];
                    final watched = progress != null && progress.percent > 0.95;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _EpisodeListTile(
                        epNum: epNum,
                        jikanEp: _jikanData[epNum],
                        progress: progress,
                        watched: watched,
                        onTap: () => _play(
                            _episodes, _episodes.indexOf(epNum), mode),
                      ),
                    );
                  },
                  childCount: filtered.length,
                ),
              ),
            ),

          // ── Fetch-more footer ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Center(
                child: _epLoading && _episodes.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: CP.cyan, strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text('Loading more…',
                              style: CP.mono(size: 11, color: CP.textDim)),
                        ],
                      )
                    : !false && _episodes.isNotEmpty
                        ? Text(
                            '— END —  ${_episodes.length} episodes total',
                            style: CP.mono(size: 10, color: CP.textMuted),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Metadata layout helpers ───────────────────────────────────────────────────

class _MetaRow extends StatelessWidget {
  final List<Widget> children;
  const _MetaRow({required this.children});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: children.map((c) => Expanded(child: c)).toList(),
        ),
      );
}

class _MetaCell extends StatelessWidget {
  final String label;
  final String value;
  const _MetaCell(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: CP.mono(size: 9, color: CP.textMuted)),
          const SizedBox(height: 2),
          Text(value, style: CP.rajdhani(size: 14, weight: FontWeight.w600)),
        ],
      );
}

// ── Sub / Dub toggle ──────────────────────────────────────────────────────────

class _SubDubToggle extends ConsumerWidget {
  const _SubDubToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(selectedModeProvider);
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
            value: 'sub',
            label: Text('SUB'),
            icon: Icon(Icons.closed_caption_rounded, size: 14)),
        ButtonSegment(
            value: 'dub',
            label: Text('DUB'),
            icon: Icon(Icons.mic_rounded, size: 14)),
      ],
      selected: {mode},
      onSelectionChanged: (s) => ref.read(selectedModeProvider.notifier).setMode(s.first),
      showSelectedIcon: false,
    );
  }
}

// ── Episode search field ──────────────────────────────────────────────────────

class _EpisodeSearch extends ConsumerWidget {
  const _EpisodeSearch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: CP.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CP.cyan.withValues(alpha: 0.2)),
      ),
      child: TextField(
        onChanged: (v) => ref.read(episodeSearchProvider.notifier).set(v),
        style: CP.mono(size: 13, color: CP.text),
        decoration: InputDecoration(
          hintText: 'FILTER LOADED EPISODES...',
          hintStyle: CP.mono(size: 12, color: CP.textMuted),
          prefixIcon: Icon(Icons.search_rounded, color: CP.textMuted, size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(color: CP.cyan.withValues(alpha: 0.5)),
          ),
          enabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

// ── Episode grid cell (wide) ──────────────────────────────────────────────────

class _EpisodeGridCell extends StatelessWidget {
  final String epNum;
  final JikanEpisode? jikanEp;
  final WatchProgress? progress;
  final bool watched;
  final VoidCallback onTap;
  const _EpisodeGridCell({
    required this.epNum,
    required this.jikanEp,
    required this.progress,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFiller = jikanEp?.isFiller ?? false;
    final color = watched ? CP.magenta : isFiller ? CP.yellow : CP.cyan;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isFiller ? CP.yellow.withValues(alpha: 0.06) : CP.surface,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: watched || isFiller ? 0.4 : 0.15)),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(epNum,
                  style: CP.mono(size: 13, color: color)),
            ),
            if (isFiller)
              Positioned(
                top: 2, left: 3,
                child: Text('F', style: CP.mono(size: 8, color: CP.yellow)),
              ),
            if (progress != null && progress!.percent > 0 && !watched)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
                  child: LinearProgressIndicator(
                    value: progress!.percent,
                    minHeight: 2,
                    color: CP.cyan,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Episode list tile (mobile) ────────────────────────────────────────────────

class _EpisodeListTile extends StatelessWidget {
  final String epNum;
  final JikanEpisode? jikanEp;
  final WatchProgress? progress;
  final bool watched;
  final VoidCallback onTap;
  const _EpisodeListTile({
    required this.epNum,
    required this.jikanEp,
    required this.progress,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isFiller = jikanEp?.isFiller ?? false;
    final isRecap = jikanEp?.isRecap ?? false;
    final title = jikanEp?.title;
    final accentColor = watched ? CP.magenta : isFiller ? CP.yellow : CP.cyan;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isFiller ? CP.yellow.withValues(alpha: 0.04) : CP.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accentColor.withValues(alpha: watched || isFiller ? 0.4 : 0.12)),
          boxShadow: watched
              ? [BoxShadow(color: CP.magenta.withValues(alpha: 0.07), blurRadius: 8)]
              : isFiller
                  ? [BoxShadow(color: CP.yellow.withValues(alpha: 0.06), blurRadius: 6)]
                  : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Center(
                      child: Text(epNum, style: CP.mono(size: 14, color: accentColor)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? 'Episode $epNum',
                          style: CP.rajdhani(size: 15, weight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            if (watched) ...[
                              Icon(Icons.check_circle_rounded, color: CP.magenta, size: 11),
                              const SizedBox(width: 4),
                              Text('WATCHED', style: CP.mono(size: 9, color: CP.magenta)),
                              const SizedBox(width: 8),
                            ],
                            if (isFiller) ...[
                              Text('FILLER', style: CP.mono(size: 9, color: CP.yellow)),
                              const SizedBox(width: 8),
                            ],
                            if (isRecap)
                              Text('RECAP', style: CP.mono(size: 9, color: CP.textMuted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.play_circle_outline_rounded, color: CP.textDim, size: 22),
                ],
              ),
            ),
            if (progress != null && progress!.percent > 0 && !watched)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
                child: LinearProgressIndicator(
                  value: progress!.percent,
                  minHeight: 3,
                  color: CP.cyan,
                  backgroundColor: CP.card,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Scan-line painter ─────────────────────────────────────────────────────────

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
