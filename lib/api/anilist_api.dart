import 'package:dio/dio.dart';

class AniListApi {
  static const String apiUrl = 'https://graphql.anilist.co/';

  final Dio _dio = Dio(BaseOptions(
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  Future<List<Map<String, dynamic>>> fetchTrending() async {
    const String gqlQuery = r'''
      query {
        Page(page: 1, perPage: 10) {
          media(type: ANIME, sort: TRENDING_DESC) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
              extraLarge
            }
            bannerImage
            description
            averageScore
            genres
          }
        }
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {"query": gqlQuery});
      final List media = response.data['data']['Page']['media'];
      return media.map((m) => m as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchAnime(String query) async {
    const String gqlQuery = r'''
      query ($search: String) {
        Page(page: 1, perPage: 20) {
          media(search: $search, type: ANIME) {
            id
            title {
              romaji
              english
            }
            coverImage {
              large
            }
            bannerImage
            description
            averageScore
          }
        }
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": {"search": query}
      });
      final List media = response.data['data']['Page']['media'];
      return media.map((m) => m as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  Future<int?> getMalId(int anilistId) async {
    const String gqlQuery = r'''
      query ($id: Int) {
        Media(id: $id, type: ANIME) {
          idMal
        }
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": {"id": anilistId}
      });
      return response.data['data']['Media']['idMal'];
    } catch (e) {
      return null;
    }
  }

  Future<int?> getMalIdByTitle(String title) async {
    const String gqlQuery = r'''
      query ($search: String) {
        Media(search: $search, type: ANIME) {
          idMal
        }
      }
    ''';

    try {
      final response = await _dio.post(apiUrl, data: {
        "query": gqlQuery,
        "variables": {"search": title}
      });
      return response.data['data']['Media']['idMal'];
    } catch (e) {
      return null;
    }
  }
}
