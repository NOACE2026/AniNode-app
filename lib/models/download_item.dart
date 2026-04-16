enum DownloadStatus { queued, downloading, completed, failed }

class DownloadItem {
  final String id; // showId_epNum
  final int animeId;
  final String showId;
  final String title;
  final String episode;
  final String? bannerUrl;
  final String downloadUrl;
  final String? filePath;
  final double progress;
  final DownloadStatus status;

  DownloadItem({
    required this.id,
    required this.animeId,
    required this.showId,
    required this.title,
    required this.episode,
    this.bannerUrl,
    required this.downloadUrl,
    this.filePath,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
  });

  DownloadItem copyWith({
    String? filePath,
    double? progress,
    DownloadStatus? status,
  }) {
    return DownloadItem(
      id: id,
      animeId: animeId,
      showId: showId,
      title: title,
      episode: episode,
      bannerUrl: bannerUrl,
      downloadUrl: downloadUrl,
      filePath: filePath ?? this.filePath,
      progress: progress ?? this.progress,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'animeId': animeId,
    'showId': showId,
    'title': title,
    'episode': episode,
    'bannerUrl': bannerUrl,
    'downloadUrl': downloadUrl,
    'filePath': filePath,
    'progress': progress,
    'status': status.index,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
    id: json['id'],
    animeId: json['animeId'],
    showId: json['showId'],
    title: json['title'],
    episode: json['episode'],
    bannerUrl: json['bannerUrl'],
    downloadUrl: json['downloadUrl'],
    filePath: json['filePath'],
    progress: (json['progress'] as num).toDouble(),
    status: DownloadStatus.values[json['status']],
  );
}
