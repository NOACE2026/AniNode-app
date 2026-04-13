import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../api/scraper_api.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String showId;
  final String episodeNumber;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.showId,
    required this.episodeNumber,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final sources = await ScraperApi().getSources(widget.showId, widget.episodeNumber);
      
      if (sources.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = "No sources found.";
        });
        return;
      }

      final scraper = ScraperApi();
      final primaryColor = Theme.of(context).primaryColor;
      
      String? videoUrl;
      String? activeSource;

      for (var source in sources) {
        final currentUrl = await scraper.resolveSource(source['url']!);
        if (currentUrl == null) continue;

        try {
          final tempController = VideoPlayerController.networkUrl(
            Uri.parse(currentUrl),
            httpHeaders: {
              'Referer': ScraperApi.referer,
              'User-Agent': ScraperApi.userAgent,
            },
          );

          await tempController.initialize();
          
          if (!mounted) {
            tempController.dispose();
            return;
          }

          _videoPlayerController = tempController;
          videoUrl = currentUrl;
          activeSource = source['name'];
          break; // Successfully initialized a source
        } catch (e) {
          debugPrint('Failed to initialize source ${source['name']}: $e');
          // Continue to next source
        }
      }
      
      if (_videoPlayerController == null || videoUrl == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage = "Could not play any of the available sources.";
        });
        return;
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        placeholder: Container(color: Colors.black),
        materialProgressColors: ChewieProgressColors(
          playedColor: primaryColor,
          handleColor: primaryColor,
          backgroundColor: Colors.grey,
          bufferedColor: Colors.white24,
        ),
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = "Playback Error: ${e.toString()}";
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _isLoading
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text('Fetching stream...', style: TextStyle(color: Colors.white70)),
                ],
              )
            : _errorMessage != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 48),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  )
                : AspectRatio(
                    aspectRatio: _videoPlayerController!.value.aspectRatio,
                    child: Chewie(controller: _chewieController!),
                  ),
      ),
    );
  }
}
