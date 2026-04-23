import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/services.dart';
import '../api/scraper_api.dart';
import '../api/skip_api.dart';
import '../api/anilist_api.dart';
import '../providers/history_provider.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';

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
    this.localPath,
  });

  final String? localPath;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  late int _currentIndex;
  
  final ValueNotifier<int> _autoplayNotifier = ValueNotifier(0);
  Timer? _autoplayTimer;
  Timer? _progressSaveTimer;
  bool _hasInitialSeeked = false;
  bool _isChangingEpisode = false;

  // Track last known good position as fallback for dispose
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  // Skip intro/outro state
  List<Map<String, dynamic>> _skipTimes = [];
  final ValueNotifier<Map<String, dynamic>?> _activeSkipMarker = ValueNotifier(null);
  List<Map<String, String>> _availableSources = [];
  int _selectedSourceIndex = 0;
  bool _hasFetchedSkipTimes = false;

  // Cache history notifier to safely use in dispose()
  late HistoryNotifier _historyNotifier;

  @override
  void initState() {
    super.initState();
    _allowAllOrientations();
    _currentIndex = widget.initialIndex;
    _player = Player();
    _controller = VideoController(_player);
    
    // Initialize cached notifier
    _historyNotifier = ref.read(historyProvider.notifier);

    // Set up listeners
    _player.stream.completed.listen((completed) async {
      if (!mounted) return;
      if (completed) {
        // Reset progress on completion
        await _historyNotifier.resetProgress(
          widget.showId, 
          widget.episodes[_currentIndex],
        );

        if (_currentIndex < widget.episodes.length - 1) {
          _startAutoplayCountdown();
        }
      }
    });

    _player.stream.error.listen((error) {
       if (mounted) {
         setState(() {
           _errorMessage = "Playback Error: $error";
         });
       }
    });

    // Continuously update last known good state
    _player.stream.position.listen((pos) {
      if (pos > Duration.zero) {
        _lastKnownPosition = pos;
        _checkSkipMarkers(pos);
      }
    });
    _player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        _lastKnownDuration = dur;
        _fetchSkipTimesOnce(dur);
      }
    });

    // Wait for dimensions to be known before seeking
    _player.stream.width.listen((width) {
      if (width != null && width > 0 && !_hasInitialSeeked) {
        _handleInitialSeek();
      }
    });

    _initializePlayer();
    _startProgressTimer();
  }

  void _checkSkipMarkers(Duration position) {
    if (_skipTimes.isEmpty) return;
    
    final currentSeconds = position.inSeconds;
    Map<String, dynamic>? active;
    
    for (var marker in _skipTimes) {
      if (currentSeconds >= marker['start'] && currentSeconds <= marker['end']) {
        active = marker;
        break;
      }
    }
    
    if (_activeSkipMarker.value != active) {
      _activeSkipMarker.value = active;
    }
  }

  Future<void> _fetchSkipTimesOnce(Duration duration) async {
    if (_hasFetchedSkipTimes || _isChangingEpisode) return;
    _hasFetchedSkipTimes = true;

    try {
      // Clean title: remove "Episode X", "(TV)", etc.
      String cleanTitle = widget.title
          .split(' - Episode').first
          .split(' Episode').first
          .split(' (TV)').first
          .trim();
          
      final malId = await AniListApi().getMalIdByTitle(cleanTitle);
      if (malId != null) {
        final episodeNumber = widget.episodes[_currentIndex];
        final times = await SkipApi().getSkipTimes(
          malId, 
          episodeNumber, 
          duration.inSeconds.toDouble(),
        );
        
        if (mounted && times.isNotEmpty) {
          setState(() { _skipTimes = times; });
          debugPrint('AniNode: Loaded ${times.length} skip markers for MAL ID: $malId');
          _checkSkipMarkers(_player.state.position);
        }
      }
    } catch (e) {
      debugPrint('AniNode: Error fetching skip times: $e');
    }
  }

  void _startProgressTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _saveCurrentProgress();
    });
  }

  Future<void> _handleInitialSeek() async {
    if (!mounted || _hasInitialSeeked) return;
    _hasInitialSeeked = true;
    
    final history = ref.read(historyProvider).value;
    if (history == null) return;

    final key = '${widget.showId}_${widget.episodes[_currentIndex]}';
    if (history.containsKey(key)) {
      final savedPos = history[key]!;
      if (savedPos.position < savedPos.duration - 10000) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          await _player.seek(Duration(milliseconds: savedPos.position));
        }
      }
    }
  }

  Future<void> _saveCurrentProgress() async {
    if (_isChangingEpisode) return; // Prevent saving during transition
    
    final currentPos = _player.state.position > Duration.zero 
        ? _player.state.position 
        : _lastKnownPosition;
    
    final totalDur = _player.state.duration > Duration.zero 
        ? _player.state.duration 
        : _lastKnownDuration;
    
    if (totalDur <= Duration.zero || currentPos.inSeconds < 5) return;
    
    unawaited(_historyNotifier.saveProgress(
      animeId: widget.animeId,
      showId: widget.showId,
      episode: widget.episodes[_currentIndex],
      title: widget.title,
      imageUrl: widget.imageUrl,
      mode: widget.mode, // SAVE MODE (SUB/DUB)
      position: currentPos,
      duration: totalDur,
    ));
  }

  Future<void> _allowAllOrientations() async {
    if (Platform.isWindows) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Don't hide status bar globally here, handled per-mode in build
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

  Future<void> _onNextEpisode() async {
    if (_currentIndex < widget.episodes.length - 1) {
      await _saveCurrentProgress();

      if (mounted) {
        setState(() {
          _isChangingEpisode = true;
          _currentIndex++;
          _isLoading = true;
          _errorMessage = null;
          _hasInitialSeeked = false;
          _autoplayNotifier.value = 0;
          _skipTimes = []; // Reset skip times
          _activeSkipMarker.value = null;
          _hasFetchedSkipTimes = false; // Reset fetch flag
          _availableSources = []; // Reset sources for new episode
          _selectedSourceIndex = 0;
          // RESET last known values for the new episode
          _lastKnownPosition = Duration.zero;
          _lastKnownDuration = Duration.zero;
        });
      }
      _autoplayTimer?.cancel();
      // Ensure player is stopped/reset before opening new media
      await _player.pause();
      _initializePlayer();
    }
  }

  void _startAutoplayCountdown() {
    _autoplayNotifier.value = 5;
    _autoplayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_autoplayNotifier.value > 1) {
        _autoplayNotifier.value--;
      } else {
        timer.cancel();
        _onNextEpisode();
      }
    });
  }

  Future<void> _initializePlayer({int? forceSourceIndex}) async {
    try {
      if (!mounted) return;
      final episodeNumber = widget.episodes[_currentIndex];
      
      // Check for local file first
      String? activePath = widget.localPath;
      if (activePath == null) {
        final downloads = ref.read(downloadProvider);
        final downloadId = "${widget.showId}_$episodeNumber";
        final item = downloads[downloadId];
        if (item != null && item.status == DownloadStatus.completed && item.filePath != null) {
          if (await File(item.filePath!).exists()) {
            activePath = item.filePath;
          }
        }
      }

      if (activePath != null) {
        debugPrint("AniNode: Playing local file: $activePath");
        await _player.open(Media(activePath));
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isChangingEpisode = false;
          });
        }
        return;
      }

      // Fetch sources if not already fetched or if changing episode
      if (_availableSources.isEmpty || forceSourceIndex == null) {
        _availableSources = await ScraperApi().getSources(widget.showId, episodeNumber, mode: widget.mode);
        // Default to vibeplayer if available
        final vibeIdx = _availableSources.indexWhere((s) => s['name']!.toLowerCase().contains('vibe'));
        _selectedSourceIndex = vibeIdx != -1 ? vibeIdx : 0;
      }

      if (forceSourceIndex != null) {
        _selectedSourceIndex = forceSourceIndex;
      }

      if (_availableSources.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No sources found.";
          });
        }
        return;
      }

      bool success = false;
      int tryIndex = _selectedSourceIndex;

      while (tryIndex < _availableSources.length && !success) {
        final source = _availableSources[tryIndex];
        final resolved = await ScraperApi().resolveSource(source['url']!);
        final String? currentUrl = resolved['url'];
        final String? currentReferer = resolved['referer'];
        
        if (currentUrl != null) {
          try {
            if (!mounted) return;
            await _player.open(
              Media(
                currentUrl,
                httpHeaders: {
                  'Referer': currentReferer ?? ScraperApi.baseUrl,
                  'Origin': currentReferer ?? ScraperApi.baseUrl,
                  'User-Agent': ScraperApi.userAgent,
                },
              ),
              play: true,
            );
            _selectedSourceIndex = tryIndex;
            success = true;
          } catch (e) {
            tryIndex++;
            continue;
          }
        } else {
          tryIndex++;
        }
      }

      if (!success) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Could not play any available sources.";
          });
        }
        return;
      }

      if (mounted) {
        setState(() { 
          _isLoading = false; 
          _isChangingEpisode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = "Error: $e";
        });
      }
    }
  }

  void _showServerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1117),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Switch Server", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _availableSources.length,
                itemBuilder: (c, i) {
                  final isSelected = i == _selectedSourceIndex;
                  return ListTile(
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: isSelected ? Colors.red : Colors.white54,
                    ),
                    title: Text(
                      _availableSources[i]['name']!,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      if (!isSelected) {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _initializePlayer(forceSourceIndex: i);
                      }
                    },
                  );
                },
              ),
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
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;
        final isWindows = Platform.isWindows;
        
        // On Mobile Portrait, we want a YouTube-like layout
        if (!isLandscape && !isWindows) {
          return _buildPortraitLayout(context);
        }
        
        // On Windows or Landscape, we might want a different layout
        return _buildLandscapeLayout(context, isLandscape);
      },
    );
  }

  // Episode search state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Widget _buildPortraitLayout(BuildContext context) {
    final mobileTheme = _getMobileTheme(context);

    final filteredEpisodes = widget.episodes.asMap().entries.where((e) {
      return _searchQuery.isEmpty || e.value.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C12),
      body: SafeArea(
        child: Column(
          children: [
            // --- VIDEO PLAYER ---
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  MaterialVideoControlsTheme(
                    normal: mobileTheme,
                    fullscreen: mobileTheme,
                    child: Video(controller: _controller, fill: Colors.black),
                  ),
                  if (_isLoading)
                    Container(
                      color: Colors.black54,
                      child: const Center(child: CircularProgressIndicator(color: Color(0xFFE53935))),
                    ),
                  if (_errorMessage != null) _buildErrorOverlay(),
                ],
              ),
            ),

            // --- SCROLLABLE CONTENT ---
            Expanded(
              child: CustomScrollView(
                slivers: [
                  // Title + episode badge
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE53935).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    "EP ${widget.episodes[_currentIndex]}",
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B6B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- SERVERS SECTION ---
                  if (_availableSources.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.dns_rounded, size: 16, color: Color(0xFF9E9E9E)),
                                const SizedBox(width: 6),
                                const Text(
                                  "SERVERS",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF9E9E9E),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 38,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _availableSources.length,
                                itemBuilder: (c, i) {
                                  final isSelected = i == _selectedSourceIndex;
                                  return GestureDetector(
                                    onTap: () {
                                      if (!isSelected) {
                                        setState(() {
                                          _isLoading = true;
                                          _errorMessage = null;
                                        });
                                        _initializePlayer(forceSourceIndex: i);
                                      }
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.only(right: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFFE53935)
                                            : const Color(0xFF1E2130),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isSelected
                                              ? const Color(0xFFE53935)
                                              : const Color(0xFF2E3247),
                                        ),
                                        boxShadow: isSelected
                                            ? [BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.35), blurRadius: 12, spreadRadius: 0)]
                                            : null,
                                      ),
                                      child: Text(
                                        _availableSources[i]['name']!,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // --- EPISODES SECTION ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.video_library_rounded, size: 16, color: Color(0xFF9E9E9E)),
                              const SizedBox(width: 6),
                              Text(
                                "EPISODES (${widget.episodes.length})",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF9E9E9E),
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Search bar
                          TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: "Search episodes...",
                              hintStyle: const TextStyle(color: Color(0xFF555870)),
                              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF555870), size: 20),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Color(0xFF555870), size: 18),
                                      onPressed: () => setState(() {
                                        _searchController.clear();
                                        _searchQuery = '';
                                      }),
                                    )
                                  : null,
                              filled: true,
                              fillColor: const Color(0xFF1E2130),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF2E3247)),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFF2E3247)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFE53935)),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
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
                        (context, idx) {
                          final entry = filteredEpisodes[idx];
                          final index = entry.key;
                          final epNum = entry.value;
                          final isCurrent = index == _currentIndex;
                          final history = ref.watch(historyProvider).value;
                          final progress = history?['${widget.showId}_$epNum'];
                          final isWatched = progress != null && progress.percent > 0.9;
                          final watchPercent = progress?.percent ?? 0.0;

                          return GestureDetector(
                            onTap: () {
                              if (!isCurrent) {
                                setState(() {
                                  _currentIndex = index;
                                  _isLoading = true;
                                  _errorMessage = null;
                                });
                                _initializePlayer();
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? const Color(0xFFE53935).withValues(alpha: 0.12)
                                    : const Color(0xFF1A1D2E),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isCurrent
                                      ? const Color(0xFFE53935).withValues(alpha: 0.5)
                                      : const Color(0xFF252840),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        // Episode number badge
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: isCurrent
                                                ? const Color(0xFFE53935)
                                                : isWatched
                                                    ? const Color(0xFF252840)
                                                    : const Color(0xFF252840),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: isCurrent
                                                ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)
                                                : Text(
                                                    epNum,
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 13,
                                                      color: isWatched ? const Color(0xFF9E9E9E) : Colors.white,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Episode $epNum",
                                                style: TextStyle(
                                                  color: isCurrent ? Colors.white : const Color(0xFFCCCCCC),
                                                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              if (watchPercent > 0 && !isWatched)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 4),
                                                  child: Text(
                                                    "${(watchPercent * 100).toInt()}% watched",
                                                    style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 11),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        if (isWatched)
                                          const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18)
                                        else if (watchPercent > 0)
                                          Text(
                                            "${(watchPercent * 100).toInt()}%",
                                            style: const TextStyle(color: Color(0xFFE53935), fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Watch progress bar
                                  if (watchPercent > 0 && !isWatched)
                                    ClipRRect(
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                      child: LinearProgressIndicator(
                                        value: watchPercent,
                                        backgroundColor: Colors.white10,
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFFE53935)),
                                        minHeight: 3,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: filteredEpisodes.length,
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

  Widget _buildLandscapeLayout(BuildContext context, bool isLandscape) {
    final mobileTheme = _getMobileTheme(context);
    final desktopTheme = _getDesktopTheme(context);

    // --- WINDOWS DESKTOP LAYOUT ---
    if (Platform.isWindows) {
      final filteredEpisodes = widget.episodes.asMap().entries.where((e) {
        return _searchQuery.isEmpty || e.value.contains(_searchQuery);
      }).toList();

      return Scaffold(
        backgroundColor: const Color(0xFF0A0C12),
        body: Row(
          children: [
            // Left: Video + Info
            Expanded(
              flex: 7,
              child: CustomScrollView(
                slivers: [
                  // Video player
                  SliverToBoxAdapter(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        children: [
                          MaterialDesktopVideoControlsTheme(
                            normal: desktopTheme,
                            fullscreen: desktopTheme,
                            child: Video(controller: _controller, fill: Colors.black),
                          ),
                          if (_isLoading)
                            Container(
                              color: Colors.black54,
                              child: const Center(child: CircularProgressIndicator(color: Color(0xFFE53935))),
                            ),
                          if (_errorMessage != null) _buildErrorOverlay(),
                          _buildAutoplayOverlay(),
                          _buildSkipMarkerOverlay(),
                        ],
                      ),
                    ),
                  ),

                  // Title + server chips
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE53935).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.4)),
                                          ),
                                          child: Text(
                                            "Episode ${widget.episodes[_currentIndex]}",
                                            style: const TextStyle(
                                              color: Color(0xFFFF6B6B),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
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

                          // Server section
                          if (_availableSources.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                const Icon(Icons.dns_rounded, size: 15, color: Color(0xFF9E9E9E)),
                                const SizedBox(width: 6),
                                const Text(
                                  "SERVERS",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF9E9E9E),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: List.generate(_availableSources.length, (i) {
                                final isSelected = i == _selectedSourceIndex;
                                return GestureDetector(
                                  onTap: () {
                                    if (!isSelected) {
                                      setState(() { _isLoading = true; _errorMessage = null; });
                                      _initializePlayer(forceSourceIndex: i);
                                    }
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFE53935) : const Color(0xFF1E2130),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFFE53935) : const Color(0xFF2E3247),
                                      ),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: const Color(0xFFE53935).withValues(alpha: 0.3), blurRadius: 14)]
                                          : null,
                                    ),
                                    child: Text(
                                      _availableSources[i]['name']!,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : const Color(0xFF9E9E9E),
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ],
                          const SizedBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Divider
            Container(width: 1, color: const Color(0xFF1E2130)),

            // Right: Episode panel
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0F1117),
                      border: Border(bottom: BorderSide(color: Color(0xFF1E2130))),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.video_library_rounded, size: 15, color: Color(0xFF9E9E9E)),
                            const SizedBox(width: 6),
                            Text(
                              "EPISODES (${widget.episodes.length})",
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF9E9E9E),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: "Search...",
                            hintStyle: const TextStyle(color: Color(0xFF555870)),
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF555870), size: 18),
                            filled: true,
                            fillColor: const Color(0xFF1A1D2E),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF2E3247)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF252840)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE53935)),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Episode list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filteredEpisodes.length,
                      itemBuilder: (context, idx) {
                        final entry = filteredEpisodes[idx];
                        final index = entry.key;
                        final epNum = entry.value;
                        final isCurrent = index == _currentIndex;
                        final history = ref.watch(historyProvider).value;
                        final progress = history?['${widget.showId}_$epNum'];
                        final isWatched = progress != null && progress.percent > 0.9;
                        final watchPercent = progress?.percent ?? 0.0;

                        return GestureDetector(
                          onTap: () {
                            if (!isCurrent) {
                              setState(() {
                                _currentIndex = index;
                                _isLoading = true;
                                _errorMessage = null;
                              });
                              _initializePlayer();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? const Color(0xFFE53935).withValues(alpha: 0.14)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isCurrent
                                    ? const Color(0xFFE53935).withValues(alpha: 0.45)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: isCurrent ? const Color(0xFFE53935) : const Color(0xFF1E2130),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Center(
                                          child: isCurrent
                                              ? const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18)
                                              : Text(
                                                  epNum,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: isWatched ? const Color(0xFF9E9E9E) : Colors.white,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          "Episode $epNum",
                                          style: TextStyle(
                                            color: isCurrent ? Colors.white : const Color(0xFFCCCCCC),
                                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      if (isWatched)
                                        const Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 16)
                                      else if (watchPercent > 0)
                                        Text(
                                          "${(watchPercent * 100).toInt()}%",
                                          style: const TextStyle(color: Color(0xFFE53935), fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                                if (watchPercent > 0 && !isWatched)
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                    child: LinearProgressIndicator(
                                      value: watchPercent,
                                      backgroundColor: Colors.white10,
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFFE53935)),
                                      minHeight: 2,
                                    ),
                                  ),
                              ],
                            ),
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

    // --- MOBILE LANDSCAPE (fullscreen) ---
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: MaterialVideoControlsTheme(
              normal: mobileTheme,
              fullscreen: mobileTheme,
              child: Video(controller: _controller, fill: Colors.black),
            ),
          ),
          if (_isLoading) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Color(0xFFE53935)))),
          if (_errorMessage != null) _buildErrorOverlay(),
          _buildAutoplayOverlay(),
          _buildSkipMarkerOverlay(),
        ],
      ),
    );
  }


  MaterialVideoControlsThemeData _getMobileTheme(BuildContext context) {
    return MaterialVideoControlsThemeData(
      seekBarPositionColor: Colors.red,
      seekBarThumbColor: Colors.red,
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
            final target = _player.state.position - const Duration(seconds: 10);
            _player.seek(target < Duration.zero ? Duration.zero : target);
          },
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
        ),
        MaterialCustomButton(
          onPressed: () {
            final target = _player.state.position + const Duration(seconds: 10);
            final duration = _player.state.duration;
            _player.seek(target > duration ? duration : target);
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
        if (_availableSources.isNotEmpty)
          MaterialCustomButton(
            onPressed: _showServerPicker,
            icon: const Icon(Icons.dns_rounded, color: Colors.white),
          ),
        const MaterialFullscreenButton(),
      ],
    );
  }

  MaterialDesktopVideoControlsThemeData _getDesktopTheme(BuildContext context) {
    return MaterialDesktopVideoControlsThemeData(
      seekBarPositionColor: Colors.red,
      seekBarThumbColor: Colors.red,
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
            final target = _player.state.position - const Duration(seconds: 10);
            _player.seek(target < Duration.zero ? Duration.zero : target);
          },
          icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
        ),
        MaterialCustomButton(
          onPressed: () {
            final target = _player.state.position + const Duration(seconds: 10);
            final duration = _player.state.duration;
            _player.seek(target > duration ? duration : target);
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
        if (_availableSources.isNotEmpty)
          MaterialCustomButton(
            onPressed: _showServerPicker,
            icon: const Icon(Icons.dns_rounded, color: Colors.white),
          ),
        const MaterialFullscreenButton(),
      ],
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.red, size: 50),
          const SizedBox(height: 10),
          Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              _resetOrientation();
              Navigator.pop(context);
            },
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoplayOverlay() {
    return ValueListenableBuilder<int>(
      valueListenable: _autoplayNotifier,
      builder: (context, countdown, _) {
        if (countdown == 0) return const SizedBox.shrink();
        return Container(
          color: Colors.black.withOpacity(0.9),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Up Next", style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 12),
                Text(
                  "Episode ${widget.episodes[_currentIndex + 1]}",
                  style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 40),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120, height: 120,
                      child: CircularProgressIndicator(
                        value: countdown / 5,
                        color: Colors.red,
                        strokeWidth: 8,
                        backgroundColor: Colors.white10,
                      ),
                    ),
                    Text("$countdown", style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 50),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        _autoplayTimer?.cancel();
                        _autoplayNotifier.value = 0;
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      ),
                      child: const Text("Cancel"),
                    ),
                    const SizedBox(width: 24),
                    ElevatedButton(
                      onPressed: _onNextEpisode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      ),
                      child: const Text("Play Now"),
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

  Widget _buildSkipMarkerOverlay() {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: _activeSkipMarker,
      builder: (context, marker, _) {
        if (marker == null) return const SizedBox.shrink();
        
        String label = "Skip Intro";
        if (marker['type'] == 'ed') label = "Skip Outro";
        if (marker['type'] == 'recap') label = "Skip Recap";
        
        return Positioned(
          bottom: 100,
          right: 30,
          child: ElevatedButton.icon(
            onPressed: () {
              _player.seek(Duration(seconds: (marker['end'] as double).toInt()));
              _activeSkipMarker.value = null;
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.skip_next),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }
}
