
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

void main() {
  final tobeparsed = "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";

  try {
    final bytes = base64.decode(tobeparsed);
    if (bytes.length < 28) {
      print("Too short");
      return;
    }

    final ivBytes = bytes.sublist(0, 12);
    final tagBytes = bytes.sublist(bytes.length - 16);
    final ciphertextBytes = bytes.sublist(12, bytes.length - 16);

    const secret = "opbbna"; // anbbpo reversed
    final keyBytes = sha256.convert(utf8.encode(secret)).bytes;
    final key = enc.Key(Uint8List.fromList(keyBytes));
    final iv = enc.IV(Uint8List.fromList(ivBytes));

    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm, padding: null));
    final encrypted = enc.Encrypted(Uint8List.fromList([...ciphertextBytes, ...tagBytes]));
    
    final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
    print("DECRYPTED UTF8: ${utf8.decode(decrypted)}");
  } catch (e) {
    print("Error: $e");
  }
}
