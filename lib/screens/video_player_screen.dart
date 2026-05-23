import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/services.dart';
import '../api/scraper_api.dart';
import '../providers/history_provider.dart';
import '../theme/cp.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String animeId;
  final String showId;
  final List<String> episodes;
  final int initialIndex;
  final String title;
  final String? imageUrl;
  final String mode;

  const VideoPlayerScreen({
    super.key,
    required this.animeId,
    required this.showId,
    required this.episodes,
    required this.initialIndex,
    required this.title,
    this.imageUrl,
    required this.mode,
  });

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;

  bool _isLoading = true;
  bool _isBuffering = false;
  String? _errorMessage;
  late int _currentIndex;
  int _streamErrorRetries = 0;

  final ValueNotifier<int> _autoplayNotifier = ValueNotifier(0);
  Timer? _autoplayTimer;
  Timer? _progressSaveTimer;
  bool _hasInitialSeeked = false;
  bool _isChangingEpisode = false;

  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  // Sources
  List<Map<String, String>> _availableSources = [];
  int _selectedSourceIndex = 0;

  // Subtitle tracks from the resolved stream source
  List<SubtitleTrackInfo> _subtitles = [];
  int _selectedSubtitleIndex = -1; // -1 = off

  late HistoryNotifier _historyNotifier;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _allowAllOrientations();
    _currentIndex = widget.initialIndex;
    _player = Player();
    _controller = VideoController(_player);
    _historyNotifier = ref.read(historyProvider.notifier);

    _player.stream.completed.listen((done) async {
      if (!mounted || !done) return;
      await _historyNotifier.resetProgress(
          widget.showId, widget.episodes[_currentIndex]);
      if (_currentIndex < widget.episodes.length - 1) _startAutoplayCountdown();
    });

    _player.stream.error.listen((e) {
      if (!mounted) return;
      // Auto-retry once — covers transient network blips and short-lived CDN URLs.
      if (_streamErrorRetries < 1) {
        _streamErrorRetries++;
        debugPrint('Stream error (auto-retry $_streamErrorRetries): $e');
        setState(() => _isLoading = true);
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _initializePlayer(forceSourceIndex: _selectedSourceIndex);
        });
      } else {
        setState(() => _errorMessage = 'Playback Error: $e');
      }
    });

    _player.stream.buffering.listen((buffering) {
      // Only show buffering overlay when the video is actually playing (not during
      // the initial source-load spinner — that is handled by _isLoading).
      if (mounted && !_isLoading) setState(() => _isBuffering = buffering);
    });

    _player.stream.position.listen((p) {
      if (p > Duration.zero) _lastKnownPosition = p;
    });
    _player.stream.duration.listen((d) {
      if (d > Duration.zero) _lastKnownDuration = d;
    });
    _player.stream.width.listen((w) {
      if (w != null && w > 0 && !_hasInitialSeeked) _handleInitialSeek();
    });

    _initializePlayer();
    _startProgressTimer();
  }

  // ── Progress persistence ──────────────────────────────────────────────────

  void _startProgressTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (t) {
      if (!mounted) { t.cancel(); return; }
      _saveCurrentProgress();
    });
  }

  Future<void> _handleInitialSeek() async {
    if (!mounted || _hasInitialSeeked) return;
    _hasInitialSeeked = true;
    final history = ref.read(historyProvider).value;
    if (history == null) return;
    final key = '${widget.showId}_${widget.episodes[_currentIndex]}';
    final saved = history[key];
    if (saved != null && saved.position < saved.duration - 10000) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) await _player.seek(Duration(milliseconds: saved.position));
    }
  }

  Future<void> _saveCurrentProgress() async {
    if (_isChangingEpisode) return;
    final pos = _player.state.position > Duration.zero
        ? _player.state.position
        : _lastKnownPosition;
    final dur = _player.state.duration > Duration.zero
        ? _player.state.duration
        : _lastKnownDuration;
    if (dur <= Duration.zero || pos.inSeconds < 5) return;
    unawaited(_historyNotifier.saveProgress(
      animeId: widget.animeId,
      showId: widget.showId,
      episode: widget.episodes[_currentIndex],
      title: widget.title,
      imageUrl: widget.imageUrl,
      mode: widget.mode,
      position: pos,
      duration: dur,
    ));
  }

  // ── Orientation ───────────────────────────────────────────────────────────

  Future<void> _allowAllOrientations() async {
    if (Platform.isWindows) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _resetOrientation() async {
    if (Platform.isWindows) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // ── Episode navigation ────────────────────────────────────────────────────

  Future<void> _onNextEpisode() async {
    if (_currentIndex >= widget.episodes.length - 1) return;
    await _saveCurrentProgress();
    if (mounted) {
      setState(() {
        _isChangingEpisode = true;
        _currentIndex++;
        _isLoading = true;
        _errorMessage = null;
        _hasInitialSeeked = false;
        _autoplayNotifier.value = 0;
        _availableSources = [];
        _selectedSourceIndex = 0;
        _subtitles = [];
        _selectedSubtitleIndex = -1;
        _streamErrorRetries = 0;
        _lastKnownPosition = Duration.zero;
        _lastKnownDuration = Duration.zero;
      });
    }
    _autoplayTimer?.cancel();
    await _player.pause();
    _initializePlayer();
  }

  void _startAutoplayCountdown() {
    _autoplayNotifier.value = 5;
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_autoplayNotifier.value > 1) {
        _autoplayNotifier.value--;
      } else {
        t.cancel();
        _onNextEpisode();
      }
    });
  }


  // ── Source initialisation ─────────────────────────────────────────────────

  Future<void> _initializePlayer({int? forceSourceIndex}) async {
    try {
      if (!mounted) return;

      // Tune MPV's demuxer/cache before opening media so that HLS segments are
      // read far enough ahead to survive brief network hiccups without stalling.
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('demuxer-readahead-secs', '30');
        await platform.setProperty('demuxer-max-bytes', '50MiB');
        await platform.setProperty('demuxer-max-back-bytes', '25MiB');
        // Wait up to 10 s for the buffer to recover before pausing playback.
        await platform.setProperty('cache-pause-wait', '10');
      }

      final epNum = widget.episodes[_currentIndex];

      if (_availableSources.isEmpty || forceSourceIndex == null) {
        final episodeObj = ScraperApi.getCachedEpisode(widget.showId, epNum);
        if (episodeObj != null) {
          _availableSources = await ScraperApi().getSources(episodeObj);
        } else {
          _availableSources = await _fetchSourcesFresh(epNum);
        }
        _selectedSourceIndex = 0;
      }
      if (forceSourceIndex != null) _selectedSourceIndex = forceSourceIndex;

      if (_availableSources.isEmpty) {
        if (mounted) {
          setState(() { _isLoading = false; _errorMessage = 'No sources found.'; });
        }
        return;
      }

      bool success = false;
      int tryIdx = _selectedSourceIndex;

      while (tryIdx < _availableSources.length && !success) {
        final src = _availableSources[tryIdx];
        final resolved = await ScraperApi().resolveSource(src['url']!);

        if (resolved.hasStream) {
          try {
            if (!mounted) return;
            final referer = resolved.referer ?? 'https://anizone.to';
            final origin = Uri.tryParse(referer)?.origin ?? 'https://anizone.to';
            await _player.open(
              Media(resolved.streamUrl!, httpHeaders: {
                'Referer': referer,
                'Origin': origin,
              }),
              play: true,
            );

            // Apply subtitles — auto-select first track if available
            final subs = resolved.subtitles;
            if (subs.isNotEmpty) {
              await _player.setSubtitleTrack(SubtitleTrack.uri(
                subs.first.url,
                title: subs.first.label,
                language: subs.first.language,
              ));
            } else {
              await _player.setSubtitleTrack(SubtitleTrack.no());
            }

            if (mounted) {
              setState(() {
                _selectedSourceIndex = tryIdx;
                _subtitles = subs;
                _selectedSubtitleIndex = subs.isNotEmpty ? 0 : -1;
              });
            }
            success = true;
          } catch (_) {
            tryIdx++;
          }
        } else {
          tryIdx++;
        }
      }

      if (!success && mounted) {
        setState(() { _isLoading = false; _errorMessage = 'Could not play any source.'; });
        return;
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isChangingEpisode = false;
          _streamErrorRetries = 0; // reset so a later network blip gets one retry
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _errorMessage = 'Error: $e'; });
    }
  }

  // ── Cold-start source fetching ────────────────────────────────────────────

  Future<List<Map<String, String>>> _fetchSourcesFresh(String epNum) async {
    try {
      final results = await ScraperApi().searchStreams(widget.title);
      if (results.isEmpty) return [];
      final resultId = ScraperApi.extractResultId(results.first, 'anikoto');
      ScraperApi.cacheStreamResult(resultId, results.first);
      final epObjects = await ScraperApi().getEpisodes(results.first, resultId: resultId);
      ScraperApi.cacheEpisodeObjects(resultId, epObjects);
      final epObj = ScraperApi.getCachedEpisode(resultId, epNum);
      if (epObj == null) return [];
      return ScraperApi().getSources(epObj);
    } catch (e) {
      debugPrint('Fresh source fetch error: $e');
      return [];
    }
  }

  // ── Subtitle helpers ──────────────────────────────────────────────────────

  Future<void> _selectSubtitle(int index) async {
    setState(() => _selectedSubtitleIndex = index);
    if (index == -1) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final s = _subtitles[index];
      await _player.setSubtitleTrack(
          SubtitleTrack.uri(s.url, title: s.label, language: s.language));
    }
  }

  void _showSubtitlePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CP.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: Color(0xFF1A3050)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 3, height: 16,
                    decoration: BoxDecoration(
                        color: CP.cyan, boxShadow: CP.glow(CP.cyan, r: 6))),
                const SizedBox(width: 8),
                Text('SUBTITLE TRACK', style: CP.orbitron(size: 11, color: CP.cyan)),
              ]),
              const SizedBox(height: 16),
              // Off option
              _SubtitleOption(
                label: 'OFF',
                language: 'Disable subtitles',
                isSelected: _selectedSubtitleIndex == -1,
                onTap: () {
                  Navigator.pop(context);
                  _selectSubtitle(-1);
                },
              ),
              const SizedBox(height: 4),
              ..._subtitles.asMap().entries.map((e) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _SubtitleOption(
                      label: e.value.label,
                      language: e.value.language.toUpperCase(),
                      isSelected: _selectedSubtitleIndex == e.key,
                      onTap: () {
                        Navigator.pop(context);
                        _selectSubtitle(e.key);
                      },
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showServerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: CP.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
        side: BorderSide(color: Color(0xFF1A3050)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(width: 3, height: 16,
                  decoration: BoxDecoration(
                      color: CP.cyan, boxShadow: CP.glow(CP.cyan, r: 6))),
              const SizedBox(width: 8),
              Text('SELECT SERVER', style: CP.orbitron(size: 11, color: CP.cyan)),
            ]),
            const SizedBox(height: 16),
            ListView.builder(
              shrinkWrap: true,
              itemCount: _availableSources.length,
              itemBuilder: (_, i) {
                final isSel = i == _selectedSourceIndex;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (!isSel) {
                      setState(() { _isLoading = true; _errorMessage = null; });
                      _initializePlayer(forceSourceIndex: i);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSel ? CP.cyan.withValues(alpha: 0.1) : CP.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSel
                            ? CP.cyan.withValues(alpha: 0.6)
                            : CP.cyan.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        Icon(isSel ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSel ? CP.cyan : CP.textDim, size: 18),
                        const SizedBox(width: 10),
                        Text(_availableSources[i]['name']!,
                            style: CP.mono(size: 13, color: isSel ? CP.cyan : CP.textDim)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveCurrentProgress();
    _resetOrientation();
    _autoplayTimer?.cancel();
    _progressSaveTimer?.cancel();
    _searchController.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final isLandscape = constraints.maxWidth > constraints.maxHeight;
      if (!isLandscape && !Platform.isWindows) return _buildPortrait(context);
      return _buildLandscape(context);
    });
  }

  // ── Portrait layout ───────────────────────────────────────────────────────

  Widget _buildPortrait(BuildContext context) {
    final filtered = widget.episodes.asMap().entries
        .where((e) => _searchQuery.isEmpty || e.value.contains(_searchQuery))
        .toList();

    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Video
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(children: [
                MaterialVideoControlsTheme(
                  normal: _mobileTheme(context),
                  fullscreen: _mobileTheme(context),
                  child: Video(controller: _controller, fill: Colors.black),
                ),
                if (_isLoading) _loadingOverlay(),
                if (_errorMessage != null) _errorOverlay(),
                _bufferingOverlay(),
              ]),
            ),

            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Title + badges
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              style: CP.orbitron(size: 14, weight: FontWeight.w800).copyWith(
                                shadows: [Shadow(
                                    color: CP.cyan.withValues(alpha: 0.3),
                                    blurRadius: 10)],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(children: [
                            _EpBadge(ep: widget.episodes[_currentIndex]),
                            if (_selectedSubtitleIndex >= 0 &&
                                _selectedSubtitleIndex < _subtitles.length) ...[
                              const SizedBox(width: 8),
                              _SubBadge(
                                  label: _subtitles[_selectedSubtitleIndex].label),
                            ],
                          ]),
                        ],
                      ),
                    ),
                  ),

                  // Servers
                  if (_availableSources.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: _ServerChips(
                          sources: _availableSources,
                          selected: _selectedSourceIndex,
                          onSelect: (i) {
                            setState(() { _isLoading = true; _errorMessage = null; });
                            _initializePlayer(forceSourceIndex: i);
                          },
                        ),
                      ),
                    ),

                  // Subtitles
                  if (_subtitles.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: _SubtitleChips(
                          subtitles: _subtitles,
                          selected: _selectedSubtitleIndex,
                          onSelect: _selectSubtitle,
                        ),
                      ),
                    ),

                  // Episodes header + search
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CP.sectionLabel('EPISODES (${widget.episodes.length})'),
                          const SizedBox(height: 12),
                          _SearchField(
                            controller: _searchController,
                            query: _searchQuery,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            onClear: () => setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Episode list
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final e = filtered[i];
                          final isCurrent = e.key == _currentIndex;
                          final progress = ref
                              .watch(historyProvider)
                              .value?['${widget.showId}_${e.value}'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _EpisodeTile(
                              epNum: e.value,
                              isCurrent: isCurrent,
                              progress: progress,
                              watched: progress != null && progress.percent > 0.9,
                              onTap: isCurrent
                                  ? null
                                  : () {
                                      setState(() {
                                        _currentIndex = e.key;
                                        _isLoading = true;
                                        _errorMessage = null;
                                      });
                                      _initializePlayer();
                                    },
                            ),
                          );
                        },
                        childCount: filtered.length,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Landscape / Windows layout ────────────────────────────────────────────

  Widget _buildLandscape(BuildContext context) {
    if (Platform.isWindows) {
      final filtered = widget.episodes.asMap().entries
          .where((e) => _searchQuery.isEmpty || e.value.contains(_searchQuery))
          .toList();

      return Scaffold(
        backgroundColor: CP.bg,
        body: Row(
          children: [
            Expanded(
              flex: 7,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(children: [
                        MaterialDesktopVideoControlsTheme(
                          normal: _desktopTheme(context),
                          fullscreen: _desktopTheme(context),
                          child: Video(controller: _controller, fill: Colors.black),
                        ),
                        if (_isLoading) _loadingOverlay(),
                        if (_errorMessage != null) _errorOverlay(),
                        _bufferingOverlay(),
                        _autoplayOverlay(),
                      ]),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title,
                              style: CP.orbitron(size: 20, weight: FontWeight.w900).copyWith(
                                  shadows: [Shadow(
                                      color: CP.cyan.withValues(alpha: 0.3),
                                      blurRadius: 12)])),
                          const SizedBox(height: 10),
                          Row(children: [
                            _EpBadge(ep: widget.episodes[_currentIndex]),
                            if (_selectedSubtitleIndex >= 0 &&
                                _selectedSubtitleIndex < _subtitles.length) ...[
                              const SizedBox(width: 8),
                              _SubBadge(
                                  label: _subtitles[_selectedSubtitleIndex].label),
                            ],
                          ]),
                          if (_availableSources.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _ServerChips(
                              sources: _availableSources,
                              selected: _selectedSourceIndex,
                              onSelect: (i) {
                                setState(() { _isLoading = true; _errorMessage = null; });
                                _initializePlayer(forceSourceIndex: i);
                              },
                            ),
                          ],
                          if (_subtitles.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _SubtitleChips(
                              subtitles: _subtitles,
                              selected: _selectedSubtitleIndex,
                              onSelect: _selectSubtitle,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, color: CP.cyan.withValues(alpha: 0.15)),
            // Episode panel
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: CP.surface,
                      border: Border(
                          bottom: BorderSide(color: CP.cyan.withValues(alpha: 0.15))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CP.sectionLabel('EPISODES (${widget.episodes.length})'),
                        const SizedBox(height: 12),
                        _SearchField(
                          controller: _searchController,
                          query: _searchQuery,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          onClear: () => setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          }),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        final isCurrent = e.key == _currentIndex;
                        final progress = ref
                            .watch(historyProvider)
                            .value?['${widget.showId}_${e.value}'];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _EpisodeTileCompact(
                            epNum: e.value,
                            isCurrent: isCurrent,
                            progress: progress,
                            watched: progress != null && progress.percent > 0.9,
                            onTap: isCurrent
                                ? null
                                : () {
                                    setState(() {
                                      _currentIndex = e.key;
                                      _isLoading = true;
                                      _errorMessage = null;
                                    });
                                    _initializePlayer();
                                  },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Mobile landscape — fullscreen
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: MaterialVideoControlsTheme(
            normal: _mobileTheme(context),
            fullscreen: _mobileTheme(context),
            child: Video(controller: _controller, fill: Colors.black),
          ),
        ),
        if (_isLoading) _loadingOverlay(),
        if (_errorMessage != null) _errorOverlay(),
        _bufferingOverlay(),
        _autoplayOverlay(),
      ]),
    );
  }

  // ── Player control themes ─────────────────────────────────────────────────

  MaterialVideoControlsThemeData _mobileTheme(BuildContext context) =>
      MaterialVideoControlsThemeData(
        seekBarPositionColor: CP.cyan,
        seekBarThumbColor: CP.cyan,
        topButtonBar: [
          MaterialCustomButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ],
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          MaterialCustomButton(
            onPressed: () {
              final t = _player.state.position - const Duration(seconds: 10);
              _player.seek(t < Duration.zero ? Duration.zero : t);
            },
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          ),
          MaterialCustomButton(
            onPressed: () {
              final t = _player.state.position + const Duration(seconds: 10);
              final d = _player.state.duration;
              _player.seek(t > d ? d : t);
            },
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
          ),
          const MaterialSkipPreviousButton(),
          const MaterialSkipNextButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          if (_currentIndex < widget.episodes.length - 1)
            MaterialCustomButton(
              onPressed: _onNextEpisode,
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
            ),
          if (_subtitles.isNotEmpty)
            MaterialCustomButton(
              onPressed: _showSubtitlePicker,
              icon: Icon(
                Icons.subtitles_rounded,
                color: _selectedSubtitleIndex >= 0 ? CP.cyan : Colors.white54,
              ),
            ),
          if (_availableSources.isNotEmpty)
            MaterialCustomButton(
              onPressed: _showServerPicker,
              icon: const Icon(Icons.dns_rounded, color: Colors.white),
            ),
          const MaterialFullscreenButton(),
        ],
      );

  MaterialDesktopVideoControlsThemeData _desktopTheme(BuildContext context) =>
      MaterialDesktopVideoControlsThemeData(
        seekBarPositionColor: CP.cyan,
        seekBarThumbColor: CP.cyan,
        topButtonBar: [
          MaterialCustomButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ],
        bottomButtonBar: [
          const MaterialPlayOrPauseButton(),
          MaterialCustomButton(
            onPressed: () {
              final t = _player.state.position - const Duration(seconds: 10);
              _player.seek(t < Duration.zero ? Duration.zero : t);
            },
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
          ),
          MaterialCustomButton(
            onPressed: () {
              final t = _player.state.position + const Duration(seconds: 10);
              final d = _player.state.duration;
              _player.seek(t > d ? d : t);
            },
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
          ),
          const MaterialSkipPreviousButton(),
          const MaterialSkipNextButton(),
          const MaterialPositionIndicator(),
          const Spacer(),
          if (_currentIndex < widget.episodes.length - 1)
            MaterialCustomButton(
              onPressed: _onNextEpisode,
              icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
            ),
          if (_subtitles.isNotEmpty)
            MaterialCustomButton(
              onPressed: _showSubtitlePicker,
              icon: Icon(
                Icons.subtitles_rounded,
                color: _selectedSubtitleIndex >= 0 ? CP.cyan : Colors.white54,
              ),
            ),
          if (_availableSources.isNotEmpty)
            MaterialCustomButton(
              onPressed: _showServerPicker,
              icon: const Icon(Icons.dns_rounded, color: Colors.white),
            ),
          const MaterialFullscreenButton(),
        ],
      );

  // ── Overlays ──────────────────────────────────────────────────────────────

  Widget _loadingOverlay() => Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: const Center(
            child: CircularProgressIndicator(color: CP.cyan, strokeWidth: 2)),
      );

  Widget _bufferingOverlay() {
    if (!_isBuffering) return const SizedBox.shrink();
    return Positioned(
      bottom: 56, // above the control bar
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: CP.bg.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: CP.cyan.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    color: CP.cyan,
                    strokeWidth: 2,
                    backgroundColor: CP.cyan.withValues(alpha: 0.15)),
              ),
              const SizedBox(width: 8),
              Text('BUFFERING…', style: CP.mono(size: 10, color: CP.textDim)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorOverlay() => Container(
        color: CP.bg.withValues(alpha: 0.92),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: CP.magenta, size: 48,
                  shadows: [
                    Shadow(color: CP.magenta.withValues(alpha: 0.6), blurRadius: 20)
                  ]),
              const SizedBox(height: 16),
              Text('PLAYBACK ERROR',
                  style: CP.orbitron(size: 12, color: CP.magenta)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage ?? '',
                  style: CP.mono(size: 11, color: CP.textDim),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Retry — re-resolves the source URL in case it expired
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _errorMessage = null;
                        _isLoading = true;
                        _streamErrorRetries = 0;
                      });
                      _initializePlayer(forceSourceIndex: _selectedSourceIndex);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: CP.cyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: CP.cyan.withValues(alpha: 0.5)),
                        boxShadow: CP.glow(CP.cyan, r: 10, a: 0.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, color: CP.cyan, size: 15),
                          const SizedBox(width: 6),
                          Text('RETRY',
                              style: CP.orbitron(size: 11, color: CP.cyan)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () { _resetOrientation(); Navigator.pop(context); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 10),
                      decoration: BoxDecoration(
                        color: CP.magenta.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: CP.magenta.withValues(alpha: 0.4)),
                      ),
                      child: Text('GO BACK',
                          style: CP.orbitron(size: 11, color: CP.magenta)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _autoplayOverlay() => ValueListenableBuilder<int>(
        valueListenable: _autoplayNotifier,
        builder: (_, countdown, _) {
          if (countdown == 0) return const SizedBox.shrink();
          return Container(
            color: CP.bg.withValues(alpha: 0.94),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('UP NEXT', style: CP.mono(size: 12, color: CP.textDim)),
                  const SizedBox(height: 12),
                  Text(
                    'EPISODE ${widget.episodes[_currentIndex + 1]}',
                    style: CP.orbitron(size: 28, weight: FontWeight.w900, color: CP.cyan)
                        .copyWith(shadows: [
                      Shadow(color: CP.cyan.withValues(alpha: 0.6), blurRadius: 20)
                    ]),
                  ),
                  const SizedBox(height: 40),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 100,
                        height: 100,
                        child: CircularProgressIndicator(
                          value: countdown / 5,
                          color: CP.cyan,
                          strokeWidth: 4,
                          backgroundColor: CP.surface,
                        ),
                      ),
                      Text('$countdown',
                          style: CP.orbitron(
                              size: 36, weight: FontWeight.w900, color: CP.cyan)),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _autoplayTimer?.cancel();
                          _autoplayNotifier.value = 0;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: CP.textDim.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('CANCEL',
                              style: CP.mono(size: 12, color: CP.textDim)),
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector(
                        onTap: _onNextEpisode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 36, vertical: 12),
                          decoration: BoxDecoration(
                            color: CP.cyan.withValues(alpha: 0.12),
                            border: Border.all(
                                color: CP.cyan.withValues(alpha: 0.7)),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: CP.glow(CP.cyan, r: 14, a: 0.3),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: CP.cyan, size: 18),
                              const SizedBox(width: 6),
                              Text('PLAY NOW',
                                  style: CP.orbitron(size: 11, color: CP.cyan)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EpBadge extends StatelessWidget {
  final String ep;
  const _EpBadge({required this.ep});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: CP.cyan.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: CP.cyan.withValues(alpha: 0.4)),
        ),
        child: Text('EP $ep', style: CP.mono(size: 11, color: CP.cyan)),
      );
}

class _SubBadge extends StatelessWidget {
  final String label;
  const _SubBadge({required this.label});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: CP.yellow.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: CP.yellow.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subtitles_rounded, color: CP.yellow, size: 11),
            const SizedBox(width: 4),
            Text(label, style: CP.mono(size: 10, color: CP.yellow)),
          ],
        ),
      );
}

class _ServerChips extends StatelessWidget {
  final List<Map<String, String>> sources;
  final int selected;
  final ValueChanged<int> onSelect;
  const _ServerChips(
      {required this.sources, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CP.sectionLabel('SERVERS'),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: sources.length,
              itemBuilder: (_, i) {
                final isSel = i == selected;
                return GestureDetector(
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? CP.cyan.withValues(alpha: 0.12)
                          : CP.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isSel
                            ? CP.cyan.withValues(alpha: 0.7)
                            : CP.cyan.withValues(alpha: 0.15),
                      ),
                      boxShadow: isSel ? CP.glow(CP.cyan, r: 10, a: 0.25) : null,
                    ),
                    child: Text(sources[i]['name']!,
                        style: CP.mono(
                            size: 12, color: isSel ? CP.cyan : CP.textDim)),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class _SubtitleChips extends StatelessWidget {
  final List<SubtitleTrackInfo> subtitles;
  final int selected;
  final ValueChanged<int> onSelect;
  const _SubtitleChips(
      {required this.subtitles, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CP.sectionLabel('SUBTITLES', accent: CP.yellow),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: subtitles.length + 1, // +1 for "Off"
              itemBuilder: (_, i) {
                final isOff = i == 0;
                final subIndex = i - 1;
                final isSel = isOff ? selected == -1 : selected == subIndex;
                final label = isOff ? 'OFF' : subtitles[subIndex].label;
                return GestureDetector(
                  onTap: () => onSelect(isOff ? -1 : subIndex),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSel
                          ? CP.yellow.withValues(alpha: 0.1)
                          : CP.surface,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isSel
                            ? CP.yellow.withValues(alpha: 0.6)
                            : CP.cyan.withValues(alpha: 0.12),
                      ),
                      boxShadow: isSel ? CP.glow(CP.yellow, r: 8, a: 0.2) : null,
                    ),
                    child: Text(label,
                        style: CP.mono(
                            size: 12,
                            color: isSel ? CP.yellow : CP.textDim)),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

class _SubtitleOption extends StatelessWidget {
  final String label;
  final String language;
  final bool isSelected;
  final VoidCallback onTap;
  const _SubtitleOption({
    required this.label,
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? CP.yellow.withValues(alpha: 0.08) : CP.surface,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? CP.yellow.withValues(alpha: 0.5)
                  : CP.cyan.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? CP.yellow : CP.textDim,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: CP.mono(
                            size: 13,
                            color: isSelected ? CP.yellow : CP.textDim)),
                    if (language.isNotEmpty)
                      Text(language,
                          style: CP.mono(size: 10, color: CP.textMuted)),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, color: CP.yellow, size: 16),
            ],
          ),
        ),
      );
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CP.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: CP.cyan.withValues(alpha: 0.2)),
        ),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: CP.mono(size: 13, color: CP.text),
          decoration: InputDecoration(
            hintText: 'SEARCH EPISODES...',
            hintStyle: CP.mono(size: 12, color: CP.textMuted),
            prefixIcon:
                Icon(Icons.search_rounded, color: CP.textMuted, size: 18),
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded,
                        color: CP.textMuted, size: 16),
                    onPressed: onClear,
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      );
}

class _EpisodeTile extends StatelessWidget {
  final String epNum;
  final bool isCurrent;
  final WatchProgress? progress;
  final bool watched;
  final VoidCallback? onTap;
  const _EpisodeTile({
    required this.epNum,
    required this.isCurrent,
    required this.progress,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress?.percent ?? 0.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: isCurrent ? CP.cyan.withValues(alpha: 0.08) : CP.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isCurrent
                ? CP.cyan.withValues(alpha: 0.6)
                : CP.cyan.withValues(alpha: 0.1),
          ),
          boxShadow: isCurrent ? CP.glow(CP.cyan, r: 10, a: 0.15) : null,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? CP.cyan.withValues(alpha: 0.15)
                          : CP.card,
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: isCurrent
                            ? CP.cyan.withValues(alpha: 0.6)
                            : CP.cyan.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Center(
                      child: isCurrent
                          ? Icon(Icons.play_arrow_rounded,
                              color: CP.cyan, size: 22)
                          : Text(epNum,
                              style: CP.mono(
                                  size: 13,
                                  color: watched ? CP.textDim : CP.text)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Episode $epNum',
                            style: CP.rajdhani(
                                size: 14,
                                weight: isCurrent
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isCurrent ? CP.cyan : CP.text)),
                        if (pct > 0 && !watched)
                          Text('${(pct * 100).toInt()}% watched',
                              style: CP.mono(size: 10, color: CP.textDim)),
                      ],
                    ),
                  ),
                  if (watched)
                    Icon(Icons.check_circle_rounded,
                        color: CP.magenta, size: 18)
                  else if (pct > 0)
                    Text('${(pct * 100).toInt()}%',
                        style: CP.mono(size: 11, color: CP.cyan)),
                ],
              ),
            ),
            if (pct > 0 && !watched)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(4)),
                child: LinearProgressIndicator(
                  value: pct,
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

class _EpisodeTileCompact extends StatelessWidget {
  final String epNum;
  final bool isCurrent;
  final WatchProgress? progress;
  final bool watched;
  final VoidCallback? onTap;
  const _EpisodeTileCompact({
    required this.epNum,
    required this.isCurrent,
    required this.progress,
    required this.watched,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress?.percent ?? 0.0;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color:
              isCurrent ? CP.cyan.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isCurrent ? CP.cyan.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color:
                          isCurrent ? CP.cyan.withValues(alpha: 0.12) : CP.surface,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Center(
                      child: isCurrent
                          ? Icon(Icons.play_arrow_rounded,
                              color: CP.cyan, size: 18)
                          : Text(epNum,
                              style: CP.mono(
                                  size: 11,
                                  color: watched ? CP.textDim : CP.text)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Episode $epNum',
                        style: CP.rajdhani(
                            size: 13,
                            weight:
                                isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? CP.cyan : CP.text)),
                  ),
                  if (watched)
                    Icon(Icons.check_circle_rounded,
                        color: CP.magenta, size: 14)
                  else if (pct > 0)
                    Text('${(pct * 100).toInt()}%',
                        style: CP.mono(size: 10, color: CP.cyan)),
                ],
              ),
            ),
            if (pct > 0 && !watched)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(4)),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 2,
                  color: CP.cyan,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
