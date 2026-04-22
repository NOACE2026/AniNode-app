import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../models/download_item.dart';
import '../api/scraper_api.dart';

final downloadProvider = NotifierProvider<DownloadNotifier, Map<String, DownloadItem>>(DownloadNotifier.new);

class DownloadNotifier extends Notifier<Map<String, DownloadItem>> {
  final _dio = Dio();
  final _scraper = ScraperApi();
  late SharedPreferences _prefs;

  @override
  Map<String, DownloadItem> build() {
    _init();
    return {};
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    final data = _prefs.getString('downloads');
    if (data != null) {
      final Map<String, dynamic> jsonMap = json.decode(data);
      state = jsonMap.map((key, value) => MapEntry(key, DownloadItem.fromJson(value)));
      // Verify files still exist, if not mark as failed or removed
      _verifyFiles();
    }
  }

  Future<void> _verifyFiles() async {
    bool changed = false;
    final newState = {...state};
    for (var key in newState.keys) {
      final item = newState[key]!;
      if (item.status == DownloadStatus.completed && item.filePath != null) {
        if (!await File(item.filePath!).exists()) {
          newState[key] = item.copyWith(status: DownloadStatus.failed, filePath: null);
          changed = true;
        }
      }
    }
    if (changed) {
      state = newState;
      _save();
    }
  }

  Future<void> _save() async {
    final data = json.encode(state.map((key, value) => MapEntry(key, value.toJson())));
    await _prefs.setString('downloads', data);
  }

  Future<void> startDownload({
    required String animeId,
    required String showId,
    required String title,
    required String episode,
    required String sourceUrl,
    String? bannerUrl,
  }) async {
    final id = "${showId}_$episode";
    if (state.containsKey(id) && state[id]!.status == DownloadStatus.completed) return;

    final item = DownloadItem(
      id: id,
      animeId: animeId,
      showId: showId,
      title: title,
      episode: episode,
      bannerUrl: bannerUrl,
      downloadUrl: sourceUrl,
      status: DownloadStatus.downloading,
      progress: 0.0,
    );

    state = {...state, id: item};
    _save();

    try {
      // 1. Resolve direct URL
      final directUrl = await _scraper.resolveSource(sourceUrl);
      if (directUrl == null) throw Exception("Could not resolve source URL");

      // 2. Prepare file path
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory(p.join(appDir.path, 'downloads'));
      if (!await downloadDir.exists()) await downloadDir.create(recursive: true);
      
      final fileName = "${showId}_ep${episode}_${DateTime.now().millisecondsSinceEpoch}.mp4";
      final filePath = p.join(downloadDir.path, fileName);

      // 3. Start download
      await _dio.download(
        directUrl,
        filePath,
        onReceiveProgress: (count, total) {
          if (total > 0) {
            state = {
              ...state,
              id: state[id]!.copyWith(progress: count / total)
            };
          }
        },
      );

      state = {
        ...state,
        id: state[id]!.copyWith(
          status: DownloadStatus.completed,
          filePath: filePath,
          progress: 1.0,
        )
      };
      _save();
    } catch (e) {
      state = {
        ...state,
        id: state[id]!.copyWith(status: DownloadStatus.failed)
      };
      _save();
    }
  }

  Future<void> deleteDownload(String id) async {
    final item = state[id];
    if (item == null) return;

    if (item.filePath != null) {
      final file = File(item.filePath!);
      if (await file.exists()) await file.delete();
    }

    final newState = {...state};
    newState.remove(id);
    state = newState;
    _save();
  }
}
