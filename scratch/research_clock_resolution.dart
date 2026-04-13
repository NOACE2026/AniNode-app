import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Referer': 'https://allmanga.to',
    },
  ));

  const url = 'https://allanime.day/apivtwo/clock.json?id=7d2473746a243c2429756f72637529656e6774726a697375727f2967686f6b6334295463696956477e564b754e4b324d564b5f593737333059757364286b7632242a2475727463676b63744f62243c24556e67746376696f6872242a2462677263243c24343634302b36322b37345234373c32373c3636283636365c242a2472746768756a67726f6968527f7663243c24757364242a246d637f243c2463762b5463696956477e564b754e4b324d564b5f593737333059757364247b';
  
  try {
    print('Testing clock.json resolution...');
    final response = await dio.get(url);
    print('Status Code: ${response.statusCode}');
    print('Data: ${response.data}');
  } catch (e) {
    print('Error: $e');
  }
}
