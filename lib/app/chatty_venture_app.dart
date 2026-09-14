import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/adventure/adventure_controller.dart';
import '../features/adventure/adventure_screen.dart';
import '../features/title/title_screen.dart';
import '../features/title/venture_splash_screen.dart';
import '../core/story/story_models.dart';

class ChattyVentureApp extends StatefulWidget {
  const ChattyVentureApp({super.key});
  @override
  State<ChattyVentureApp> createState() => _ChattyVentureAppState();
}

class _ChattyVentureAppState extends State<ChattyVentureApp> {
  late final AdventureController controller;
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool darkMode = false;
  bool _showTitle = false;
  @override
  void initState() {
    super.initState();
    controller = AdventureController();
    controller.begin();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final value =
        (await SharedPreferences.getInstance()).getBool('dark_mode') ?? false;
    if (mounted) setState(() => darkMode = value);
  }

  Future<void> _toggleTheme() async {
    setState(() => darkMode = !darkMode);
    await (await SharedPreferences.getInstance()).setBool(
      'dark_mode',
      darkMode,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: _navigatorKey,
    title: 'Chatty-Venture',
    debugShowCheckedModeBanner: false,
    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9B4637),
        surface: const Color(0xFFF6F0E5),
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F0E5),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFD77D69),
        brightness: Brightness.dark,
        surface: const Color(0xFF1D1A20),
      ),
      scaffoldBackgroundColor: const Color(0xFF17151A),
      useMaterial3: true,
    ),
    home: AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: _showTitle
          ? TitleScreen(
              controller: controller,
              darkMode: darkMode,
              onToggleTheme: _toggleTheme,
              onContinue: () => _openAdventure(),
              onAdventure: (template) => _openAdventure(template: template),
              onFreeMode: () => _openAdventure(freeMode: true),
            )
          : VentureSplashScreen(
              onContinue: () => setState(() => _showTitle = true),
            ),
    ),
  );

  void _openAdventure({StoryTemplate? template, bool freeMode = false}) {
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => AdventureScreen(
          controller: controller,
          darkMode: darkMode,
          onToggleTheme: _toggleTheme,
          initialAdventure: template,
          startFreeMode: freeMode,
        ),
      ),
    );
  }
}
