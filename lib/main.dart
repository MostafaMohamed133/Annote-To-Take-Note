import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/database_service.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('[ROAD_GUARD_FLUTTER_ERROR] ${details.exceptionAsString()}');
        if (details.stack != null) debugPrintStack(stackTrace: details.stack);
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        debugPrint('[ROAD_GUARD_UNCAUGHT_ERROR] $error');
        debugPrintStack(stackTrace: stack);
        return false;
      };

      runApp(const RoadGuardAnnotatorApp());
    },
    (Object error, StackTrace stack) {
      debugPrint('[ROAD_GUARD_ZONE_ERROR] $error');
      debugPrintStack(stackTrace: stack);
    },
  );
}

class RoadGuardAnnotatorApp extends StatefulWidget {
  const RoadGuardAnnotatorApp({super.key});

  @override
  State<RoadGuardAnnotatorApp> createState() => _RoadGuardAnnotatorAppState();
}

class _RoadGuardAnnotatorAppState extends State<RoadGuardAnnotatorApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _themeLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final saved = await DatabaseService.instance.getThemeMode();
      if (!mounted) return;
      setState(() {
        _themeMode = saved == 'light' ? ThemeMode.light : ThemeMode.dark;
        _themeLoaded = true;
      });
    } catch (error) {
      debugPrint('[ROAD_GUARD_THEME_LOAD_ERROR] $error');
      if (mounted) setState(() => _themeLoaded = true);
    }
  }

  Future<void> _toggleTheme() async {
    final next = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    setState(() => _themeMode = next);
    try {
      await DatabaseService.instance.setThemeMode(
        next == ThemeMode.dark ? 'dark' : 'light',
      );
    } catch (error) {
      debugPrint('[ROAD_GUARD_THEME_SAVE_ERROR] $error');
    }
  }

  ThemeData _lightTheme() {
    const burgundy = Color(0xFF741B3B);
    const lightSurface = Color(0xFFFFFFFF);
    const lightBackground = Color(0xFFFFFBFC);
    final scheme = ColorScheme.fromSeed(
      seedColor: burgundy,
      brightness: Brightness.light,
    ).copyWith(
      primary: burgundy,
      onPrimary: Colors.white,
      secondary: const Color(0xFF9B536B),
      onSecondary: Colors.white,
      surface: lightSurface,
      onSurface: const Color(0xFF24151B),
      error: const Color(0xFFB3261E),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: lightSurface,
        foregroundColor: burgundy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEADDE2)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: lightSurface,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: burgundy,
        foregroundColor: Colors.white,
      ),
    );
  }

  ThemeData _darkTheme() {
    const purple = Color(0xFFB79AFF);
    const darkBackground = Color(0xFF090710);
    const darkSurface = Color(0xFF171321);
    const darkContainer = Color(0xFF251D35);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8B5CF6),
      brightness: Brightness.dark,
    ).copyWith(
      primary: purple,
      onPrimary: const Color(0xFF1D1230),
      secondary: const Color(0xFFCEB9FF),
      onSecondary: const Color(0xFF24183A),
      surface: darkSurface,
      onSurface: const Color(0xFFF4EFFA),
      surfaceContainerHighest: darkContainer,
      error: const Color(0xFFFFB4AB),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: darkBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: purple,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF352B48)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        filled: true,
        fillColor: darkSurface,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: purple,
        foregroundColor: Color(0xFF1D1230),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Road Guard Annotator',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      home: _themeLoaded
          ? HomeScreen(
              isDarkMode: _themeMode == ThemeMode.dark,
              onToggleTheme: _toggleTheme,
            )
          : const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
    );
  }
}
