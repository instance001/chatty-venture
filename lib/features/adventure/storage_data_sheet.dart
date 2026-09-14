import 'package:flutter/material.dart';

import '../../core/storage/local_model_store.dart';
import '../../core/storage/story_save_store.dart';

Future<void> showStorageDataSheet({
  required BuildContext context,
  required Future<void> Function() onModelsChanged,
  required Future<void> Function() onClearSavedAdventure,
  required Future<void> Function() onClearAllPrivateData,
  required VoidCallback onManageModels,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _StorageDataSheet(
    onModelsChanged: onModelsChanged,
    onClearSavedAdventure: onClearSavedAdventure,
    onClearAllPrivateData: onClearAllPrivateData,
    onManageModels: onManageModels,
  ),
);

class _StorageDataSheet extends StatefulWidget {
  const _StorageDataSheet({
    required this.onModelsChanged,
    required this.onClearSavedAdventure,
    required this.onClearAllPrivateData,
    required this.onManageModels,
  });

  final Future<void> Function() onModelsChanged;
  final Future<void> Function() onClearSavedAdventure;
  final Future<void> Function() onClearAllPrivateData;
  final VoidCallback onManageModels;

  @override
  State<_StorageDataSheet> createState() => _StorageDataSheetState();
}

class _StorageDataSheetState extends State<_StorageDataSheet> {
  final _models = LocalModelStore();
  final _saves = StorySaveStore();
  var _loading = true;
  var _modelsBytes = 0;
  var _saveBytes = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final records = await _models.load();
    final saveBytes = await _saves.byteSize();
    if (!mounted) return;
    setState(() {
      _modelsBytes = records.fold(0, (total, model) => total + model.bytes);
      _saveBytes = saveBytes;
      _loading = false;
    });
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _clearSavedAdventure() async {
    if (!await _confirm(
      title: 'Clear saved adventure?',
      body:
          'This removes the saved story and starts the current session fresh. Your local models and cloud setup stay untouched.',
      action: 'Clear adventure',
    )) {
      return;
    }
    await widget.onClearSavedAdventure();
    await _reload();
  }

  Future<void> _clearAllPrivateData() async {
    if (!await _confirm(
      title: 'Clear all private app data?',
      body:
          'This permanently removes private GGUF copies, saved adventures, narration settings, cloud configuration, and stored cloud API keys.',
      action: 'Clear all data',
    )) {
      return;
    }
    await widget.onClearAllPrivateData();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _modelsBytes + _saveBytes;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text('Storage & data', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Manage private on-device data. Removing a model does not affect the copy inside the installed app package.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _UsageRow(label: 'Local GGUF models', bytes: _modelsBytes),
              _UsageRow(label: 'Saved adventure', bytes: _saveBytes),
              const Divider(height: 28),
              Text(
                'Private storage: ${_formatBytes(total)}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Manage local models'),
                subtitle: const Text('Remove imported GGUFs one at a time.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  widget.onManageModels();
                },
              ),
              const Divider(height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_stories_outlined),
                title: const Text('Clear saved adventure'),
                subtitle: const Text('Keeps models, prompts, and cloud setup.'),
                onTap: _clearSavedAdventure,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.delete_forever_outlined,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  'Clear all private app data',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                subtitle: const Text(
                  'Models, saves, settings, cloud setup, and keys.',
                ),
                onTap: _clearAllPrivateData,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.label, required this.bytes});

  final String label;
  final int bytes;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(_formatBytes(bytes)),
      ],
    ),
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
