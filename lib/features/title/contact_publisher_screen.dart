import 'package:flutter/material.dart';

import '../../core/contact/developer_message_service.dart';

class ContactPublisherScreen extends StatefulWidget {
  const ContactPublisherScreen({super.key});

  @override
  State<ContactPublisherScreen> createState() => _ContactPublisherScreenState();
}

class _ContactPublisherScreenState extends State<ContactPublisherScreen> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _service = const DeveloperMessageService();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a message before sending it.')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await _service.send(
        subject: subject.isEmpty ? 'Chatty-Venture player message' : subject,
        message: message,
      );
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Message was not sent: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Scaffold(
        appBar: AppBar(title: const Text('Message developer')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 56),
                const SizedBox(height: 18),
                Text(
                  'Message sent',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Thanks for helping make Chatty-Venture better.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to title screen'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Message developer')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Send a note to the publisher',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Only the words you enter here are sent. Your adventure, narration, API keys, and device details stay on your device.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            TextField(
              controller: _subject,
              maxLength: 160,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Subject (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              minLines: 6,
              maxLines: 10,
              maxLength: 2000,
              decoration: const InputDecoration(
                alignLabelWithHint: true,
                labelText: 'Your message',
                hintText: 'Tell us what happened or what you would like to see.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? 'Sending…' : 'Send message'),
            ),
          ],
        ),
      ),
    );
  }
}
