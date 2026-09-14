import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'contact_publisher_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final _repository = Uri.parse(
    'https://github.com/Instance001/chatty-venture',
  );
  static final _privacyPolicy = Uri.parse(
    'https://instance001.github.io/privacy/chatty-venture.html',
  );

  Future<void> _openSource(BuildContext context) async {
    final opened = await launchUrl(
      _repository,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open GitHub right now.')),
      );
    }
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final opened = await launchUrl(
      _privacyPolicy,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the privacy policy.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About Chatty-Venture')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Icon(Icons.auto_stories, size: 58, color: scheme.primary),
            const SizedBox(height: 18),
            Text(
              'A story that remembers where it has been.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 28),
            const _AboutSection(
              title: 'What it is',
              body:
                  'Chatty-Venture is a narration-first text adventure. Its game ledger keeps the durable story facts and objectives consistent while you choose how to proceed.',
            ),
            const _AboutSection(
              title: 'Your narration lane',
              body:
                  'Storyteller demo and local GGUF narration stay on-device. Cloud narration runs only when you select and configure a cloud provider in the app.',
            ),
            const _AboutSection(
              title: 'Local GGUF models',
              body:
                  'Chatty-Venture does not ship model weights: import a GGUF you trust into private app storage. SmolLM2-360M-Instruct is a compact starting point. A larger model may produce richer narration, but needs more memory and can be slower. Most phones are best kept below 1B parameters. Search for “Qwen2.5-0.5B-Instruct GGUF” as a compact alternative; “Qwen2.5-1.5B-Instruct GGUF” is better suited to a powerful phone.',
            ),
            const _AboutSection(
              title: 'Support and privacy',
              body:
                  'Message developer sends only the subject and note you type in that form. It does not automatically include adventures, narration, prompts, API keys, or device details.',
            ),
            const _AboutSection(
              title: 'Source and licence',
              body:
                  'Chatty-Venture is free software under the GNU Affero General Public License v3.0 (AGPLv3). Its source is available on GitHub.',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ContactPublisherScreen(),
                ),
              ),
              icon: const Icon(Icons.mail_outline),
              label: const Text('Message developer'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openSource(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('View source on GitHub'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openPrivacyPolicy(context),
              icon: const Icon(Icons.privacy_tip_outlined),
              label: const Text('Privacy Policy'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
