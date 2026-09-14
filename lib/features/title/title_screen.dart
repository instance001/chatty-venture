import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/story/story_models.dart';
import '../../core/story/story_engine.dart';
import '../adventure/adventure_controller.dart';
import 'about_screen.dart';
import 'contact_publisher_screen.dart';

class TitleScreen extends StatefulWidget {
  const TitleScreen({
    super.key,
    required this.controller,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onContinue,
    required this.onAdventure,
    required this.onFreeMode,
  });

  final AdventureController controller;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onContinue;
  final ValueChanged<StoryTemplate> onAdventure;
  final VoidCallback onFreeMode;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> {
  static final _repository = Uri.parse(
    'https://github.com/Instance001/chatty-venture',
  );
  bool? hasSavedAdventure;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final saved = await widget.controller.saves.load();
    if (mounted) setState(() => hasSavedAdventure = saved != null);
  }

  Future<void> _open(Uri uri) async {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that link right now.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: widget.darkMode ? 'Use light theme' : 'Use dark theme',
            onPressed: widget.onToggleTheme,
            icon: Icon(widget.darkMode ? Icons.light_mode : Icons.dark_mode),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
              child: ListView(
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.auto_stories, size: 64, color: palette.primary),
                  const SizedBox(height: 18),
                  Text(
                    'CHATTY-VENTURE',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A story that remembers where it has been.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 42),
                  if (hasSavedAdventure == true) ...[
                    FilledButton.icon(
                      onPressed: widget.onContinue,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Continue'),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ...AdventureCatalog.adventures.map(
                    (adventure) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton(
                        onPressed: () => widget.onAdventure(adventure),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 15,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              adventure.title,
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              adventure.pitch,
                              textAlign: TextAlign.left,
                              style: TextStyle(color: palette.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onFreeMode,
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Free Mode'),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AboutScreen(),
                          ),
                        ),
                        child: const Text('About'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ContactPublisherScreen(),
                          ),
                        ),
                        child: const Text('Contact publisher'),
                      ),
                      TextButton(
                        onPressed: () => _open(_repository),
                        child: const Text('View source on GitHub'),
                      ),
                    ],
                  ),
                  Text(
                    'Source available under GNU AGPLv3',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
