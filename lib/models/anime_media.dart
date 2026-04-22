class AnimeMedia {
  final String id;
  final String title;
  final String? englishTitle;
  final String? coverUrl;
  final String? bannerUrl;
  final String? description;
  final int? score;
  final List<String> genres;

  AnimeMedia({
    required this.id,
    required this.title,
    this.englishTitle,
    this.coverUrl,
    this.bannerUrl,
    this.description,
    this.score,
    this.genres = const [],
  });

  factory AnimeMedia.fromAniList(Map<String, dynamic> json) {
    return AnimeMedia(
      id: json['id'].toString(),
      title: json['title']['romaji'] ?? json['title']['english'] ?? 'Unknown',
      englishTitle: json['title']['english'],
      coverUrl: json['coverImage']?['extraLarge'] ?? json['coverImage']?['large'],
      bannerUrl: json['bannerImage'],
      description: json['description'],
      score: json['averageScore'],
      genres: List<String>.from(json['genres'] ?? []),
    );
  }

  factory AnimeMedia.fromAllAnime(Map<String, dynamic> json) {
    final String thumb = json['thumbnail'] ?? '';
    
    return AnimeMedia(
      id: json['id'] ?? json['_id'] ?? '',
      title: json['name'] ?? 'Unknown',
      englishTitle: json['englishName'],
      coverUrl: thumb.isNotEmpty ? thumb : null,
      description: json['description'],
      genres: List<String>.from(json['genres'] ?? []),
      score: (double.tryParse(json['score']?.toString() ?? '0') ?? 0).toInt(),
    );
  }
}
