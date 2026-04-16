import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

void main() async {
  final dio = Dio(BaseOptions(
    headers: {
      'Referer': 'https://allmanga.to/',
      'Origin': 'https://allmanga.to',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0',
      'Content-Type': 'application/json',
    },
  ));

  try {
    // 1. Get Dorohedoro Season 2 episode 5 directly
    const gqlQuery = r'''
      query ($showId: String!, $translationType: VaildTranslationTypeEnumType!, $episodeString: String!) { 
        episode( showId: $showId translationType: $translationType episodeString: $episodeString ) { 
          episodeString sourceUrls __typename
        } 
      }
    ''';
    
    final response = await dio.post('https://api.allanime.day/api', data: {
      "query": gqlQuery,
      "variables": {
        "showId": "KvBvdrsppnuMqGRcN",
        "translationType": "sub",
        "episodeString": "5"
      }
    });

    final tobeparsed = response.data['data']['tobeparsed'];
    print('Fresh tobeparsed length: ${tobeparsed.length}');

    // 2. Decrypt
    String normalized = tobeparsed.trim().replaceAll('_', '/').replaceAll('-', '+');
    while (normalized.length % 4 != 0) normalized += '=';
    
    final bytes = base64.decode(normalized);
    final ivBytes = bytes.sublist(0, 12);
    final ciphertextWithMac = bytes.sublist(12);

    const reversedPassword = "SimtVuagFbGR2K7P";
    final keyBytes = sha256.convert(utf8.encode(reversedPassword)).bytes;
    
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List.fromList(ivBytes));

    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));
    final decrypted = encrypter.decrypt(
      enc.Encrypted(Uint8List.fromList(ciphertextWithMac)), 
      iv: iv
    );
    
    final decoded = json.decode(decrypted);
    print('SOURCES: ${decoded['episode']?['sourceUrls']}');
  } catch (e) {
    print('ERROR: $e');
  }
}

