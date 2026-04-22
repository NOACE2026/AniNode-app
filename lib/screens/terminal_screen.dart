import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/scraper_api.dart';
import '../providers/download_provider.dart';
import 'video_player_screen.dart';

class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScraperApi _api = ScraperApi();
  final ScrollController _scrollController = ScrollController();

  List<TextSpan> _logs = [];
  List<Map<String, dynamic>> _lastSearchResults = [];

  @override
  void initState() {
    super.initState();
    _printLog("AniNode Terminal v1.0.0");
    _printLog("Type 'help' to see available commands.");
    _printLog("------------------------------------");
    // Request focus seamlessly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _printLog(String text, {Color color = const Color(0xFF00FF00)}) {
    setState(() {
      _logs = List.from(_logs)..add(
        TextSpan(
          text: "$text\n",
          style: GoogleFonts.robotoMono(
            color: color,
            fontSize: 14,
          ),
        ),
      );
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleCommand(String rawCommand) async {
    final command = rawCommand.trim();
    if (command.isEmpty) return;

    _printLog("> $command", color: Colors.white);
    _controller.clear();

    final parts = command.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.length > 1 ? parts.sublist(1) : [];

    switch (cmd) {
      case 'help':
        _printLog("Available commands:", color: Colors.cyanAccent);
        _printLog("  search <query>      - Search for an anime");
        _printLog("  eps <id/index>      - List episodes for a show");
        _printLog("  play <index> <ep>   - Play a specific episode");
        _printLog("  download <index> <ep> - Start downloading an episode");
        _printLog("  clear             - Clear terminal output");
        _printLog("  exit              - Close terminal mode");
        break;

      case 'clear':
        setState(() {
          _logs.clear();
        });
        break;

      case 'exit':
        Navigator.pop(context);
        break;

      case 'search':
        if (args.isEmpty) {
          _printLog("Error: Missing search query.", color: Colors.redAccent);
          break;
        }
        final query = args.join(' ');
        _printLog("Searching for '$query'...", color: Colors.yellow);
        try {
          final results = await _api.search(query);
          if (results.isEmpty) {
            _printLog("No results found.", color: Colors.amber);
          } else {
            _lastSearchResults = results;
            for (int i = 0; i < results.length; i++) {
              final show = results[i];
              _printLog("[$i] ${show['name']} (Episodes: ${show['episodes']})", color: Colors.greenAccent);
            }
          }
        } catch (e) {
          _printLog("Error: $e", color: Colors.redAccent);
        }
        break;

      case 'eps':
        if (args.isEmpty) {
          _printLog("Error: Missing show ID or index.", color: Colors.redAccent);
          break;
        }
        String idStr = args[0];
        String showId = _resolveShowId(idStr);
        if (showId.isEmpty) break;

        _printLog("Fetching episodes for $showId...", color: Colors.yellow);
        try {
          final eps = await _api.getEpisodesList(showId);
          if (eps.isEmpty) {
            _printLog("No episodes found.", color: Colors.amber);
          } else {
            _printLog("Episodes: ${eps.join(', ')}", color: Colors.greenAccent);
          }
        } catch (e) {
          _printLog("Error: $e", color: Colors.redAccent);
        }
        break;

      case 'play':
        if (args.length < 2) {
          _printLog("Error: Usage 'play <index> <episode>'.", color: Colors.redAccent);
          break;
        }
        String idStr = args[0];
        String epNumber = args[1];

        // Ensure index is valid
        int? index = int.tryParse(idStr);
        if (index == null || index < 0 || index >= _lastSearchResults.length) {
           _printLog("Error: Invalid search index. Did you run 'search'?", color: Colors.redAccent);
           break;
        }

        final showDetail = _lastSearchResults[index];
        final showId = showDetail['id'] as String;
        final showName = showDetail['name'] as String;

        _printLog("Fetching episode list for player...", color: Colors.yellow);
        try {
          final allEps = await _api.getEpisodesList(showId);
          if (allEps.isEmpty) {
            _printLog("Error: No episodes available for this show.", color: Colors.redAccent);
            break;
          }

          int epIndex = allEps.indexOf(epNumber);
          if (epIndex == -1) {
            _printLog("Error: Episode $epNumber not found. Available: ${allEps.join(', ')}", color: Colors.redAccent);
            break;
          }

          _printLog("Launching player for '$showName' Ep $epNumber...", color: Colors.cyanAccent);
          
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => VideoPlayerScreen(
                animeId: '0', // Not tied to AniList in CLI mode natively
                showId: showId,
                episodes: allEps,
                initialIndex: epIndex,
                title: showName,
                mode: 'sub',
              ),
            ),
          ).then((_) {
            // Regain focus when returning
            _focusNode.requestFocus();
          });

        } catch (e) {
          _printLog("Error launching player: $e", color: Colors.redAccent);
        }
        break;

      case 'download':
        if (args.length < 2) {
          _printLog("Error: Usage 'download <index> <episode>'.", color: Colors.redAccent);
          break;
        }
        String idStr = args[0];
        String epNumber = args[1];

        int? index = int.tryParse(idStr);
        if (index == null || index < 0 || index >= _lastSearchResults.length) {
           _printLog("Error: Invalid search index.", color: Colors.redAccent);
           break;
        }

        final showDetail = _lastSearchResults[index];
        final showId = showDetail['id'] as String;
        final showName = showDetail['name'] as String;

        _printLog("Resolving source for download...", color: Colors.yellow);
        try {
          final sources = await _api.getSources(showId, epNumber, mode: 'sub');
          if (sources.isEmpty) {
            _printLog("Error: No sources found for episode $epNumber.", color: Colors.redAccent);
            break;
          }

          final bestSource = sources.first['url'];
          if (bestSource == null) throw Exception("No valid URL in sources.");

          _printLog("Download starting for '$showName' Ep $epNumber...", color: Colors.cyanAccent);
          _printLog("Check 'Downloads' screen for progress.", color: Colors.white70);

          ref.read(downloadProvider.notifier).startDownload(
            animeId: '0', // CLI mode specific
            showId: showId,
            title: showName,
            episode: epNumber,
            sourceUrl: bestSource,
          );
        } catch (e) {
          _printLog("Error starting download: $e", color: Colors.redAccent);
        }
        break;

      default:
        _printLog("Command not found: $cmd. Type 'help' for options.", color: Colors.redAccent);
        break;
    }

    _focusNode.requestFocus();
  }

  String _resolveShowId(String idStr) {
    if (idStr.length < 5) {
      // Treat as index
      int? idx = int.tryParse(idStr);
      if (idx != null && idx >= 0 && idx < _lastSearchResults.length) {
        return _lastSearchResults[idx]['id'];
      } else {
        _printLog("Error: Invalid index. Run 'search' first.", color: Colors.redAccent);
        return "";
      }
    }
    return idStr; // Return raw ID
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text("Terminal", style: GoogleFonts.robotoMono(fontSize: 16)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _focusNode.requestFocus(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: 1, // We bundle all spans in one text for simpler selection/rendering
                  itemBuilder: (context, index) {
                    return SelectableText.rich(
                      TextSpan(children: _logs),
                    );
                  },
                ),
              ),
            ),
          ),
          Container(
            color: Colors.grey[900],
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  "> ",
                  style: GoogleFonts.robotoMono(color: Colors.greenAccent, fontSize: 16),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: GoogleFonts.robotoMono(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send, color: Colors.greenAccent),
                        onPressed: () {
                          _handleCommand(_controller.text);
                        },
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _handleCommand,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
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
