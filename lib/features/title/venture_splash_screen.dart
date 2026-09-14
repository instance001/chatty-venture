import 'package:flutter/material.dart';

class VentureSplashScreen extends StatelessWidget {
  const VentureSplashScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final compact = media.size.height < 620;
    final veryCompact = media.size.height < 480;
    final dark = theme.brightness == Brightness.dark;
    final titleStyle =
        (compact
                ? theme.textTheme.headlineSmall
                : theme.textTheme.headlineMedium)
            ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.8);

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? const [
                    Color(0xFF17151A),
                    Color(0xFF2A1D23),
                    Color(0xFF432B32),
                  ]
                : const [
                    Color(0xFFF8F2E9),
                    Color(0xFFF0E2DD),
                    Color(0xFFDCC9C2),
                  ],
          ),
        ),
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onContinue,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    minHeight: media.size.height - media.padding.vertical - 48,
                  ),
                  child: Center(
                    child: Card(
                      elevation: 0,
                      color: dark
                          ? const Color(0xFF261F24).withValues(alpha: 0.94)
                          : Colors.white.withValues(alpha: 0.88),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(compact ? 26 : 32),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(compact ? 18 : 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Chatty-Venture',
                              textAlign: TextAlign.center,
                              style: titleStyle,
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            Text(
                              'Narration-first adventures that remember the journey.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 26),
                            Image.asset(
                              'assets/branding/fmi-splash-wordmark.png',
                              fit: BoxFit.contain,
                              height: veryCompact
                                  ? 44
                                  : compact
                                  ? 58
                                  : 74,
                            ),
                            SizedBox(height: compact ? 14 : 20),
                            Image.asset(
                              'assets/branding/rd-engine-logo.png',
                              fit: BoxFit.contain,
                              height: veryCompact
                                  ? 52
                                  : compact
                                  ? 66
                                  : 86,
                            ),
                            SizedBox(height: compact ? 16 : 22),
                            Text(
                              'Published under Fractal Media Infrastructure and built on RD Engine reducer doctrine.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.35,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(height: compact ? 16 : 22),
                            FilledButton(
                              onPressed: onContinue,
                              child: const Text('Continue'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap anywhere to continue',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
