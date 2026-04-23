import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/download_provider.dart';
import '../models/download_item.dart';
import 'video_player_screen.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadProvider).values.where((e) => e.status == DownloadStatus.completed).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0C12),
      appBar: AppBar(
        title: const Text('Offline Downloads'),
        backgroundColor: const Color(0xFF1E2130),
        elevation: 0,
      ),
      body: downloads.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white24),
                   SizedBox(height: 16),
                   Text("No offline videos yet.", style: TextStyle(color: Colors.white54)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: downloads.length,
              itemBuilder: (c, i) {
                final item = downloads[i];
                return _DownloadTile(item: item);
              },
            ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  final DownloadItem item;
  const _DownloadTile({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: const Color(0xFF1E2130),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(8),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.bannerUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.bannerUrl!,
                  width: 80,
                  height: 120,
                  fit: BoxFit.cover,
                )
              : Container(width: 80, color: Colors.white10, child: const Icon(Icons.movie)),
        ),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('Episode ${item.episode}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Color(0xFFE53935)),
          onPressed: () {
            ref.read(downloadProvider.notifier).deleteDownload(item.id);
          },
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => VideoPlayerScreen(
                animeId: item.animeId,
                showId: item.showId,
                episodes: [item.episode],
                initialIndex: 0,
                title: item.title,
                mode: 'sub', // Standardized
                localPath: item.filePath,
              ),
            ),
          );
        },
      ),
    );
  }
}
