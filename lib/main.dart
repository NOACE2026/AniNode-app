import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'providers/auth_provider.dart';
import 'theme/cp.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: AniNodeApp()));
}

class AniNodeApp extends ConsumerWidget {
  const AniNodeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    return MaterialApp(
      title: 'AniNode',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: CP.bg,
        primaryColor: CP.cyan,
        colorScheme: ColorScheme.dark(
          primary: CP.cyan,
          secondary: CP.magenta,
          surface: CP.surface,
          onPrimary: CP.bg,
          onSurface: CP.text,
        ),
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: CP.text,
          displayColor: CP.text,
        ),
        iconTheme: const IconThemeData(color: CP.cyan),
        appBarTheme: AppBarTheme(
          backgroundColor: CP.bg,
          elevation: 0,
          titleTextStyle: CP.orbitron(size: 18, weight: FontWeight.w800),
          iconTheme: const IconThemeData(color: CP.cyan),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.selected) ? CP.cyan.withValues(alpha: 0.15) : CP.surface),
            foregroundColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.selected) ? CP.cyan : CP.textDim),
            side: WidgetStateProperty.all(BorderSide(color: CP.cyan.withValues(alpha: 0.3))),
            shape: WidgetStateProperty.all(
              const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
            ),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: CP.cyan),
        dividerTheme: DividerThemeData(color: CP.cyan.withValues(alpha: 0.1), thickness: 1),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: CP.surface,
          contentTextStyle: CP.rajdhani(color: CP.text),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: CP.card,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Color(0xFF1A3050)),
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
      ),
      home: _buildHome(authState),
    );
  }

  Widget _buildHome(AuthState authState) {
    if (authState.isLoading) {
      return Scaffold(
        backgroundColor: CP.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ANINODE', style: CP.orbitron(size: 28, color: CP.cyan)),
              const SizedBox(height: 24),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  backgroundColor: CP.surface,
                  color: CP.cyan,
                  minHeight: 2,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!authState.isLoggedIn) return const LoginScreen();
    return const HomeScreen();
  }
}
