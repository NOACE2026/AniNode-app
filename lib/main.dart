import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/downloads_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'AniNode Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        primaryColor: const Color(0xFF3F51B5),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3F51B5),
          secondary: Color(0xFF00BFA5),
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      ),
      home: _buildInitialScreen(ref, authState),
    );
  }

  Widget _buildInitialScreen(WidgetRef ref, AuthState authState) {
    if (!authState.isLoggedIn) return const LoginScreen();

    final connectivity = ref.watch(connectivityProvider).value;
    if (connectivity == ConnectivityStatus.offline) {
      return const DownloadsScreen();
    }
    
    return const HomeScreen();
  }
}
