class AnimeMedia {
  final int id;
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
      id: json['id'],
      title: json['title']['romaji'],
      englishTitle: json['title']['english'],
      coverUrl: json['coverImage']?['extraLarge'] ?? json['coverImage']?['large'],
      bannerUrl: json['bannerImage'],
      description: json['description'],
      score: json['averageScore'],
      genres: List<String>.from(json['genres'] ?? []),
    );
  }
}
