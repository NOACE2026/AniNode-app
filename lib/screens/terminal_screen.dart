import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../api/scraper_api.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<TextSpan> _logs = [];

  @override
  void initState() {
    super.initState();
    _printLog("AniNode Terminal v1.0.0");
    _printLog("Type 'help' to see available commands.");
    _printLog("------------------------------------");
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
        _printLog("  search <query>  - Search for anime metadata");
        _printLog("  clear           - Clear terminal output");
        _printLog("  exit            - Close terminal mode");
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
          final results = await ScraperApi().searchMetadata(query);
          if (results.isEmpty) {
            _printLog("No results found.", color: Colors.amber);
          } else {
            for (int i = 0; i < results.length && i < 10; i++) {
              final show = results[i];
              final title = _getTitle(show);
              _printLog("[$i] $title", color: Colors.greenAccent);
            }
          }
        } catch (e) {
          _printLog("Error: $e", color: Colors.redAccent);
        }
        break;

      default:
        _printLog("Command not found: $cmd. Type 'help' for options.", color: Colors.redAccent);
        break;
    }

    _focusNode.requestFocus();
  }

  String _getTitle(dynamic show) {
    try {
      if (show.title is String) return show.title;
      return show.title?.preferred ?? 'Unknown';
    } catch (_) {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2130),
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
            color: const Color(0xFF1E2130),
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
