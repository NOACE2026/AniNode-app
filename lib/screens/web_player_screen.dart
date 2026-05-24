import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../api/filler_service.dart';
import '../providers/history_provider.dart';
import '../theme/cp.dart';
import 'local_player_server_io.dart' if (dart.library.html) 'local_player_server_web.dart';

/// WebView-backed player utilizing flutter_inappwebview for robust cross-platform
/// playback supporting Android, iOS, and Windows desktop targets inside the app.
class WebPlayerScreen extends ConsumerStatefulWidget {
  final String animeId;
  final String showId;
  final String title;
  final String? imageUrl;
  final List<EpisodeStream> episodes;
  final int initialIndex;
  final String mode; // 'sub' | 'dub'

  const WebPlayerScreen({
    super.key,
    required this.animeId,
    required this.showId,
    required this.title,
    required this.episodes,
    required this.initialIndex,
    required this.mode,
    this.imageUrl,
  });

  @override
  ConsumerState<WebPlayerScreen> createState() => _WebPlayerScreenState();
}

/// Minimal per-episode payload — just what the WebView needs.
class EpisodeStream {
  final String number;
  final String? subUrl;
  final String? dubUrl;
  const EpisodeStream({required this.number, this.subUrl, this.dubUrl});

  bool hasMode(String mode) =>
      (mode == 'dub' ? dubUrl : subUrl)?.isNotEmpty ?? false;

  String? urlFor(String mode) => mode == 'dub' ? dubUrl : subUrl;
}

class _WebPlayerScreenState extends ConsumerState<WebPlayerScreen> {
  InAppWebViewController? _web;
  late int _currentIndex;
  late String _mode;
  bool _loading = true;
  String? _error;
  String _search = '';
  bool _desktopFullscreen = false;
  final _searchCtrl = TextEditingController();
  Set<String> _fillerEpisodes = const {};

  List<SavedStream> get _savedStreams => widget.episodes
      .map((e) => SavedStream(number: e.number, subUrl: e.subUrl, dubUrl: e.dubUrl))
      .toList();

  double _lastSavedPos = -1;
  DateTime _lastSavedAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _loadTriggered = false; // prevent double _loadCurrent() on init
  // Timestamp of the last loadUrl() call. Events arriving within 2 s of a
  // URL change are from the OLD page (WebView2 doesn't flush them instantly)
  // and must be discarded to prevent stale-position saves and crashes.
  DateTime _lastLoadAt = DateTime.fromMillisecondsSinceEpoch(0);

  // The WebView must be created once and reused across layout changes —
  // otherwise rotating to landscape (or any rebuild that swaps which layout
  // method is returned) tears down the WebView and restarts playback.
  // A GlobalKey lets Flutter re-parent the same Element/State when the widget
  // moves between portrait/fullscreen/desktop trees.
  final GlobalKey _webViewKey = GlobalKey();
  late final Widget _persistentWebView = _buildWebView();

  @override
  void initState() {
    super.initState();
    _allowAllOrientations();
    _currentIndex = widget.initialIndex;
    _mode = widget.mode;
    if (!_currentEpisode.hasMode(_mode)) {
      _mode = _mode == 'sub' ? 'dub' : 'sub';
    }
    // Async-fetch filler episode list (Jikan/MAL) for this title.
    FillerService.fillerForTitle(widget.title).then((set) {
      if (!mounted || set.isEmpty) return;
      setState(() => _fillerEpisodes = set);
    });
    LocalPlayerServer.start().then((_) {
      if (mounted && _web != null && !_loadTriggered) {
        _loadTriggered = true;
        _loadCurrent();
      }
    });
  }

  void _handlePlayerMessage(String jsonStr) {
    // Discard events that arrived within 2 s of the last loadUrl() — they are
    // stale postMessages from the previous page still draining through WebView2.
    if (DateTime.now().difference(_lastLoadAt).inMilliseconds < 2000) return;
    try {
      var decoded = jsonDecode(jsonStr);
      // Bridge wraps as { _origin, data } — unwrap.
      if (decoded is Map && decoded['data'] != null) {
        decoded = decoded['data'];
      }
      if (decoded is String) {
        try { decoded = jsonDecode(decoded); } catch (_) {}
      }
      if (decoded is! Map) return;
      final data = decoded;

      // Accept many shapes — different embeds use different keys/types.
      final type = (data['type'] ?? data['event'])?.toString();
      double? toD(Object? v) {
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      final isTime = type == 'time' ||
          type == 'timeupdate' ||
          type == 'progress' ||
          data.containsKey('currentTime') ||
          data.containsKey('current_time');
      if (isTime) {
        final double? posSeconds = toD(data['value']) ??
            toD(data['position']) ??
            toD(data['time']) ??
            toD(data['currentTime']) ??
            toD(data['current_time']);
        final double? durSeconds = toD(data['duration']) ?? toD(data['total']);
        if (posSeconds != null && durSeconds != null && durSeconds > 0) {
          // Guard against the player firing low-position events right after
          // load — they'd otherwise overwrite the saved resume point.
          final history = ref.read(historyProvider).value;
          final existing = history?['${widget.showId}_${_currentEpisode.number}'];
          if (existing != null && posSeconds < 10 && existing.position > 10000) {
            return;
          }
          // Dedupe: bursts of identical-position events (paused video) and
          // rate-limit to one save per 5s to keep prefs writes cheap.
          final now = DateTime.now();
          final movedEnough = (posSeconds - _lastSavedPos).abs() >= 1.0;
          final dueByTime = now.difference(_lastSavedAt).inSeconds >= 5;
          if (!movedEnough && !dueByTime) return;
          _lastSavedPos = posSeconds;
          _lastSavedAt = now;
          ref.read(historyProvider.notifier).saveProgress(
                animeId: widget.animeId,
                showId: widget.showId,
                episode: _currentEpisode.number,
                title: widget.title,
                imageUrl: widget.imageUrl,
                mode: _mode,
                position: Duration(milliseconds: (posSeconds * 1000).toInt()),
                duration: Duration(milliseconds: (durSeconds * 1000).toInt()),
                streams: _savedStreams,
              ).catchError((_) {});
        }
      } else if (type == 'complete') {
        ref.read(historyProvider.notifier).resetProgress(
              widget.showId,
              _currentEpisode.number,
            ).catchError((_) {});
        if (_currentIndex < widget.episodes.length - 1) {
          _switchEpisode(_currentIndex + 1);
        }
      } else if (type == 'error') {
        setState(() {
          _error = data['message']?.toString() ?? 'Playback Error';
        });
      }
    } catch (e) {
      debugPrint('Error parsing player event: $e');
    }
  }

  EpisodeStream get _currentEpisode => widget.episodes[_currentIndex];

  bool get _isDesktopOrWeb =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _allowAllOrientations() async {
    if (_isDesktopOrWeb) return;
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _loadCurrent() {
    final url = _currentEpisode.urlFor(_mode);
    if (url == null || url.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'No $_mode source for episode ${_currentEpisode.number}';
      });
      return;
    }

    setState(() { _loading = true; _error = null; });
    _lastLoadAt = DateTime.now();

    if (kIsWeb) {
      // On web there is no localhost server — load the embed URL directly in the
      // iframe. Clear the spinner immediately; the embed page shows its own loader.
      _web?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      setState(() => _loading = false);
      unawaited(_recordStartIfNew());
      return;
    } else {
      if (LocalPlayerServer.port == null) {
        setState(() {
          _loading = false;
          _error = 'Player server not ready — please retry';
        });
        return;
      }
      final localhostUrl = 'http://localhost:${LocalPlayerServer.port}/play?url=${Uri.encodeComponent(url)}';
      _web?.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(localhostUrl),
          headers: {
            'Referer': 'https://anikoto.cz/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );
    }

    // Mark this episode as "started" so the Continue Watching row picks it up
    // even before the player fires any time events. Must wait for history to
    // finish loading from prefs — saving against an unloaded ({}) state would
    // wipe entries from disk and clobber a real saved position with the stub.
    unawaited(_recordStartIfNew());
  }

  Future<void> _recordStartIfNew() async {
    final historyMap = await ref.read(historyProvider.future);
    final existing = historyMap['${widget.showId}_${_currentEpisode.number}'];
    if (existing != null) return;
    if (!mounted) return;
    await ref.read(historyProvider.notifier).saveProgress(
          animeId: widget.animeId,
          showId: widget.showId,
          episode: _currentEpisode.number,
          title: widget.title,
          imageUrl: widget.imageUrl,
          mode: _mode,
          position: const Duration(seconds: 1),
          duration: const Duration(minutes: 24),
          streams: _savedStreams,
        );
  }

  void _switchEpisode(int index) {
    if (index < 0 || index >= widget.episodes.length) return;
    final next = widget.episodes[index];
    var mode = _mode;
    if (!next.hasMode(mode)) {
      mode = mode == 'sub' ? 'dub' : 'sub';
    }
    setState(() {
      _currentIndex = index;
      _mode = mode;
      _loading = true;
      _error = null;
    });
    _loadTriggered = true; // not an init load — always proceed
    _loadCurrent();
  }

  void _toggleMode() {
    final next = _mode == 'sub' ? 'dub' : 'sub';
    if (!_currentEpisode.hasMode(next)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${next.toUpperCase()} for this episode')),
      );
      return;
    }
    setState(() => _mode = next);
    _loadTriggered = true;
    _loadCurrent();
  }

  @override
  void dispose() {
    LocalPlayerServer.stop();
    _searchCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final landscape = c.maxWidth > c.maxHeight;
      final isDesktop = _isDesktopOrWeb;
      if (isDesktop && c.maxWidth >= 900) return _buildDesktop(c);
      if (landscape && !isDesktop) return _buildFullscreen();
      return _buildPortrait(c);
    });
  }

  // Shared WebView builder — same config used by every layout so the player
  // state and JS bridge are consistent across portrait/landscape/desktop.
  Widget _buildWebView() => InAppWebView(
        key: _webViewKey,
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          useShouldOverrideUrlLoading: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true,
          allowsInlineMediaPlayback: true,
          allowsPictureInPictureMediaPlayback: true,
          // Disable disk cache — HLS segments are never reused and can fill
          // the drive within a few hours of watching on Windows (WebView2).
          cacheEnabled: false,
          userAgent:
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          // Web: grant the iframe permission to call requestFullscreen() so
          // the embed's own fullscreen button works natively in the browser.
          iframeAllowFullscreen: true,
          iframeAllow: 'fullscreen; autoplay; encrypted-media; picture-in-picture',
          isElementFullscreenEnabled: true,
        ),
        onWebViewCreated: (controller) {
          _web = controller;
          // addJavaScriptHandler is not implemented on the web platform —
          // the embed is a cross-origin iframe anyway so the bridge can't
          // reach it. Only register the handler on native targets.
          if (!kIsWeb) {
            _web?.addJavaScriptHandler(
              handlerName: 'PlayerChannel',
              callback: (args) {
                if (args.isNotEmpty) {
                  _handlePlayerMessage(args.first.toString());
                }
              },
            );
          }
          if (LocalPlayerServer.port != null && !_loadTriggered) {
            _loadTriggered = true;
            _loadCurrent();
          }
        },
        onCreateWindow: (controller, _) async => false,
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          // On web the flutter_inappwebview renders as an <iframe> — there is no
          // localhost wrapper, so the embed URL IS the main-frame URL. Allow all
          // navigation; pop-under blocking is handled by onCreateWindow => false.
          if (kIsWeb) return NavigationActionPolicy.ALLOW;

          final uri = navigationAction.request.url;
          if (uri == null) return NavigationActionPolicy.CANCEL;
          final urlStr = uri.toString();
          if (navigationAction.isForMainFrame) {
            if (urlStr.startsWith('http://localhost')) {
              return NavigationActionPolicy.ALLOW;
            }
            return NavigationActionPolicy.CANCEL;
          }
          if (urlStr.contains('megaplay.buzz') ||
              urlStr.contains('anikotoapi.site') ||
              urlStr.contains('.m3u8') ||
              urlStr.contains('.mp4') ||
              urlStr.contains('plyr') ||
              urlStr.contains('hls') ||
              urlStr.contains('blob:')) {
            return NavigationActionPolicy.ALLOW;
          }
          // Block obvious ad/pop-under navigation patterns.
          final uri2 = Uri.tryParse(urlStr);
          final host = uri2?.host ?? '';
          if (host.startsWith('ad.') ||
              host.startsWith('ads.') ||
              host.startsWith('pop.') ||
              host.startsWith('click.') ||
              host.contains('.ad.') ||
              host.contains('popunder') ||
              host.contains('popads')) {
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
        onLoadStart: (controller, url) {
          // On web the embed URL is loaded directly — don't touch loading state
          // here (it was already cleared in _loadCurrent). On native we only
          // track our localhost wrapper page to avoid stale sub-frame events.
          if (kIsWeb || !mounted) return;
          final urlStr = url?.toString() ?? '';
          if (urlStr.startsWith('http://localhost')) {
            setState(() { _loading = true; _error = null; });
          }
        },
        onLoadStop: (controller, url) async {
          if (!mounted) return;
          final urlStr = url?.toString() ?? '';
          // Native: clear spinner only for our localhost page.
          // Web: spinner already cleared; just try to install the JS bridge.
          if (!kIsWeb && urlStr.startsWith('http://localhost')) {
            setState(() => _loading = false);
          }
          // Install postMessage bridge on every page load (idempotent guard inside).
          // On web this runs in the iframe scope — will silently fail for
          // cross-origin iframes, which is expected and harmless.
          try {
            await controller.evaluateJavascript(source: '''
              (function() {
                if (window.__aninodeBridgeInstalled) return;
                window.__aninodeBridgeInstalled = true;
                window.addEventListener('message', function(event) {
                  try {
                    var payload = event.data;
                    if (typeof payload === 'string') {
                      try { payload = JSON.parse(payload); } catch (_) {}
                    }
                    var wrapped = { _origin: event.origin, data: payload };
                    window.flutter_inappwebview.callHandler('PlayerChannel', JSON.stringify(wrapped));
                  } catch (e) {
                    console.error('bridge error', e);
                  }
                });
              })();
            ''');
          } catch (_) {}
        },
        onReceivedError: (controller, request, error) {
          if (kIsWeb || !mounted) return;
          final url = request.url.toString();
          if ((request.isForMainFrame ?? false) && url.startsWith('http://localhost')) {
            setState(() { _loading = false; _error = error.description; });
          }
        },
        onEnterFullscreen: (controller) async {
          // On web the browser owns fullscreen — the embed's native button
          // triggers it directly. Don't touch Flutter layout or orientation.
          if (kIsWeb || !mounted) return;
          if (_isDesktopOrWeb) {
            setState(() => _desktopFullscreen = true);
            return;
          }
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        },
        onExitFullscreen: (controller) async {
          if (kIsWeb || !mounted) return;
          if (_isDesktopOrWeb) {
            setState(() => _desktopFullscreen = false);
            return;
          }
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        },
      );

  void _toggleDesktopFullscreen() {
    setState(() => _desktopFullscreen = !_desktopFullscreen);
  }

  // ── Desktop layout: video on left filling height, episode panel on right ───
  Widget _buildDesktop(BoxConstraints c) {
    final panelWidth = (c.maxWidth * 0.28).clamp(300.0, 440.0);
    final filtered = widget.episodes.asMap().entries
        .where((e) => _search.isEmpty || e.value.number.contains(_search))
        .toList();
    final gridCols = (panelWidth / 64).floor().clamp(3, 8);

    final videoPane = Container(
      color: Colors.black,
      padding: EdgeInsets.all(_desktopFullscreen ? 0 : 16),
      child: Column(
        children: [
          if (!_desktopFullscreen)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    splashRadius: 22,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: CP.orbitron(
                          size: 16,
                          weight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Pill(label: 'EP ${_currentEpisode.number}', color: CP.cyan),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _toggleMode,
                    child: _Pill(
                      label: _mode.toUpperCase(),
                      color: CP.yellow,
                      icon: Icons.swap_horiz_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_currentIndex < widget.episodes.length - 1)
                    GestureDetector(
                      onTap: () => _switchEpisode(_currentIndex + 1),
                      child: _Pill(
                        label: 'NEXT EP',
                        color: CP.magenta,
                        icon: Icons.skip_next_rounded,
                      ),
                    ),
                  // Fullscreen on web is handled by the embed's own button.
                  if (!kIsWeb) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Fullscreen (F / Esc)',
                      icon: const Icon(Icons.fullscreen_rounded, color: Colors.white),
                      onPressed: _toggleDesktopFullscreen,
                      splashRadius: 22,
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius:
                    BorderRadius.circular(_desktopFullscreen ? 0 : 8),
                boxShadow: _desktopFullscreen
                    ? null
                    : [
                        BoxShadow(
                          color: CP.cyan.withValues(alpha: 0.18),
                          blurRadius: 22,
                          spreadRadius: -6,
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(_desktopFullscreen ? 0 : 8),
                child: Stack(
                  children: [
                    Positioned.fill(child: _persistentWebView),
                    if (_loading) _loadingOverlay(),
                    if (_error != null) _errorOverlay(),
                    if (_desktopFullscreen && !kIsWeb)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Exit fullscreen (Esc)',
                            icon: const Icon(Icons.fullscreen_exit_rounded,
                                color: Colors.white),
                            onPressed: _toggleDesktopFullscreen,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: CP.bg,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          // On web the browser owns keyboard shortcuts for fullscreen.
          if (kIsWeb) return KeyEventResult.ignored;
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                _desktopFullscreen) {
              _toggleDesktopFullscreen();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyF) {
              _toggleDesktopFullscreen();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          children: [
            Expanded(child: videoPane),

          // ── Episode side panel ────────────────────────────────────────
          if (!_desktopFullscreen) Container(
            width: panelWidth,
            decoration: BoxDecoration(
              color: CP.surface,
              border: Border(
                left: BorderSide(color: CP.cyan.withValues(alpha: 0.18)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: CP.sectionLabel('EPISODES (${widget.episodes.length})'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: CP.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: CP.cyan.withValues(alpha: 0.15)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _search = v),
                      style: CP.mono(size: 13, color: CP.text),
                      decoration: InputDecoration(
                        hintText: 'FILTER EPISODES…',
                        hintStyle: CP.mono(size: 11, color: CP.textMuted),
                        prefixIcon: Icon(Icons.search_rounded,
                            color: CP.cyan.withValues(alpha: 0.6), size: 18),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: gridCols,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final e = filtered[i];
                      final isCurrent = e.key == _currentIndex;
                      final progress = ref
                          .watch(historyProvider)
                          .value?['${widget.showId}_${e.value.number}'];
                      final percent = progress?.percent ?? 0.0;
                      final watched = percent > 0.9;
                      return _EpisodeGridItem(
                        number: e.value.number,
                        isCurrent: isCurrent,
                        watched: watched,
                        isFiller: _fillerEpisodes.contains(e.value.number),
                        progress: percent,
                        onTap: isCurrent ? null : () => _switchEpisode(e.key),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullscreen() => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(child: _persistentWebView),
            if (_loading) _loadingOverlay(),
            if (_error != null) _errorOverlay(),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ]),
        ),
      );

  Widget _buildPortrait(BoxConstraints c) {
    final filtered = widget.episodes.asMap().entries
        .where((e) => _search.isEmpty || e.value.number.contains(_search))
        .toList();
    final cols = (c.maxWidth / 62).floor().clamp(5, 24);

    return Scaffold(
      backgroundColor: CP.bg,
      body: SafeArea(
        child: Column(children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: c.maxHeight * 0.42,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: CP.cyan.withValues(alpha: 0.15),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Container(
                      color: Colors.black,
                      child: Stack(children: [
                        Positioned.fill(child: _persistentWebView),
                        if (_loading) _loadingOverlay(),
                        if (_error != null) _errorOverlay(),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          Expanded(
            child: CustomScrollView(slivers: [
              // Title & Pills Details Area
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: CP.orbitron(size: 15, weight: FontWeight.w800, color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 12),
                      Row(children: [
                        _Pill(
                          label: 'EP ${_currentEpisode.number}',
                          color: CP.cyan,
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _toggleMode,
                          child: _Pill(
                            label: _mode.toUpperCase(),
                            color: CP.yellow,
                            icon: Icons.swap_horiz_rounded,
                          ),
                        ),
                        const Spacer(),
                        if (_currentIndex < widget.episodes.length - 1)
                          GestureDetector(
                            onTap: () => _switchEpisode(_currentIndex + 1),
                            child: _Pill(
                              label: 'NEXT EP',
                              color: CP.magenta,
                              icon: Icons.skip_next_rounded,
                            ),
                          ),
                      ]),
                    ],
                  ),
                ),
              ),

              // Filter & Grid Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CP.sectionLabel('EPISODES (${widget.episodes.length})'),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: CP.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: CP.cyan.withValues(alpha: 0.15)),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _search = v),
                          style: CP.mono(size: 13, color: CP.text),
                          decoration: InputDecoration(
                            hintText: 'FILTER EPISODES…',
                            hintStyle: CP.mono(size: 11, color: CP.textMuted),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: CP.cyan.withValues(alpha: 0.6), size: 18),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Episode Grid!
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.0,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final e = filtered[i];
                      final isCurrent = e.key == _currentIndex;
                      final progress = ref
                          .watch(historyProvider)
                          .value?['${widget.showId}_${e.value.number}'];
                      final percent = progress?.percent ?? 0.0;
                      final watched = percent > 0.9;
                      return _EpisodeGridItem(
                        number: e.value.number,
                        isCurrent: isCurrent,
                        watched: watched,
                        isFiller: _fillerEpisodes.contains(e.value.number),
                        progress: percent,
                        onTap: isCurrent ? null : () => _switchEpisode(e.key),
                      );
                    },
                    childCount: filtered.length,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _loadingOverlay() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: Colors.black.withValues(alpha: 0.65),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: CP.cyan,
                    strokeWidth: 2.5,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'LOAD STREAM…',
                  style: CP.orbitron(
                    size: 9,
                    color: CP.cyan,
                    weight: FontWeight.w700,
                  ).copyWith(letterSpacing: 2.0),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _errorOverlay() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: CP.bg.withValues(alpha: 0.96),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: CP.magenta, size: 36),
                const SizedBox(height: 12),
                Text('PLAYBACK ERROR',
                    style: CP.orbitron(size: 11, color: CP.magenta, weight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(_error ?? 'Unknown error occurred',
                    style: CP.mono(size: 10, color: CP.textDim),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _error = null;
                      _loading = true;
                    });
                    _loadCurrent();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      color: CP.cyan.withValues(alpha: 0.1),
                      border: Border.all(color: CP.cyan.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('RETRY',
                        style: CP.orbitron(size: 10, color: CP.cyan, weight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const _Pill({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: CP.mono(size: 10, color: color),
            ),
          ],
        ),
      );
}

class _EpisodeGridItem extends StatelessWidget {
  final String number;
  final bool isCurrent;
  final bool watched;
  final bool isFiller;
  final double progress;
  final VoidCallback? onTap;

  const _EpisodeGridItem({
    required this.number,
    required this.isCurrent,
    required this.watched,
    required this.progress,
    this.isFiller = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Priority: current > filler > watched > default.
    final Color accent = isCurrent
        ? CP.cyan
        : isFiller
            ? CP.yellow
            : watched
                ? CP.magenta
                : CP.text;
    final Color borderColor = isCurrent
        ? CP.cyan.withValues(alpha: 0.8)
        : isFiller
            ? CP.yellow.withValues(alpha: 0.5)
            : watched
                ? CP.magenta.withValues(alpha: 0.3)
                : CP.cyan.withValues(alpha: 0.1);
    final Color bg = isCurrent
        ? CP.cyan.withValues(alpha: 0.1)
        : isFiller
            ? CP.yellow.withValues(alpha: 0.05)
            : watched
                ? CP.magenta.withValues(alpha: 0.04)
                : CP.card;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: isCurrent ? 1.5 : 1.0,
          ),
          boxShadow: isCurrent
              ? CP.glow(CP.cyan, r: 8, a: 0.12)
              : isFiller
                  ? CP.glow(CP.yellow, r: 6, a: 0.08)
                  : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Episode Number
            Text(
              number,
              style: CP.orbitron(
                size: 13,
                color: accent,
                weight: isCurrent ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            // Filler badge (top-left)
            if (isFiller && !isCurrent)
              Positioned(
                top: 3,
                left: 4,
                child: Text(
                  'F',
                  style: CP.mono(size: 8, color: CP.yellow)
                      .copyWith(letterSpacing: 0),
                ),
              ),
            
            // Progress Indicator Bar
            if (progress > 0 && !watched)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    color: CP.cyan,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),

            // Watched Indicator Dot
            if (watched)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 10,
                  color: CP.magenta,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

