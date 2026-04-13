import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter/services.dart';
import '../api/scraper_api.dart';
import '../providers/history_provider.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final int animeId;
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
  String? _errorMessage;
  late int _currentIndex;
  
  final ValueNotifier<int> _autoplayNotifier = ValueNotifier(0);
  Timer? _autoplayTimer;
  Timer? _progressSaveTimer;
  bool _hasInitialSeeked = false;

  // Track last known good position as fallback for dispose
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;

  // Cache history notifier to safely use in dispose()
  late HistoryNotifier _historyNotifier;

  @override
  void initState() {
    super.initState();
    _forceLandscape();
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
      }
    });
    _player.stream.duration.listen((dur) {
      if (dur > Duration.zero) {
        _lastKnownDuration = dur;
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

  Future<void> _forceLandscape() async {
    if (Platform.isWindows) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
          _currentIndex++;
          _isLoading = true;
          _errorMessage = null;
          _hasInitialSeeked = false;
          _autoplayNotifier.value = 0;
          // RESET last known values for the new episode
          _lastKnownPosition = Duration.zero;
          _lastKnownDuration = Duration.zero;
        });
      }
      _autoplayTimer?.cancel();
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

  Future<void> _initializePlayer() async {
    try {
      if (!mounted) return;
      final episodeNumber = widget.episodes[_currentIndex];
      final sources = await ScraperApi().getSources(widget.showId, episodeNumber, mode: widget.mode);

      if (sources.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "No sources found.";
          });
        }
        return;
      }

      String? matchedUrl;
      for (var source in sources) {
        final currentUrl = await ScraperApi().resolveSource(source['url']!);
        if (currentUrl != null) {
          matchedUrl = currentUrl;
          break;
        }
      }

      if (matchedUrl == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Could not resolve sources.";
          });
        }
        return;
      }

      if (!mounted) return;
      await _player.open(
        Media(
          matchedUrl,
          httpHeaders: {
            'Referer': ScraperApi.referer,
            'User-Agent': ScraperApi.userAgent,
          },
        ),
      );

      if (mounted) {
        setState(() { _isLoading = false; });
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
    final mobileTheme = MaterialVideoControlsThemeData(
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
        const MaterialFullscreenButton(),
      ],
    );

    final desktopTheme = MaterialDesktopVideoControlsThemeData(
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
        const MaterialFullscreenButton(),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) await _resetOrientation();
        },
        child: Stack(
          children: [
            Center(
              child: MaterialVideoControlsTheme(
                normal: mobileTheme,
                fullscreen: mobileTheme,
                child: MaterialDesktopVideoControlsTheme(
                  normal: desktopTheme,
                  fullscreen: desktopTheme,
                  child: Video(controller: _controller, fill: Colors.black),
                ),
              ),
            ),
            if (_isLoading) const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_errorMessage != null)
              Center(
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
              ),
            ValueListenableBuilder<int>(
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
            ),
          ],
        ),
      ),
    );
  }
}
