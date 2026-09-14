import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/narration/narrator_profiles.dart';
import '../../core/narration/narrator_prompt_settings.dart';
import '../../core/narration/narrator_style_settings.dart';
import '../../core/narration/narrator.dart';
import '../../core/narration/cloud_key_service.dart';
import '../../core/narration/cloud_narrator.dart';
import '../../core/storage/local_model_store.dart';
import '../../core/story/story_engine.dart';
import '../../core/story/free_mode.dart';
import '../../core/story/story_models.dart';
import 'adventure_controller.dart';
import 'storage_data_sheet.dart';

class AdventureScreen extends StatefulWidget {
  const AdventureScreen({
    super.key,
    required this.controller,
    required this.darkMode,
    required this.onToggleTheme,
    this.initialAdventure,
    this.startFreeMode = false,
  });
  final AdventureController controller;
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final StoryTemplate? initialAdventure;
  final bool startFreeMode;
  @override
  State<AdventureScreen> createState() => _AdventureScreenState();
}

class _AdventureScreenState extends State<AdventureScreen> {
  final composer = TextEditingController();
  final scroll = ScrollController();
  NarratorProfile profile = NarratorCatalog.profiles.first;
  final modelStore = LocalModelStore();
  List<LocalModelRecord> models = [];
  String? selectedModelId;
  NarratorFallbackKind fallbackKind = NarratorFallbackKind.ask;
  bool isPreparingNarrator = true;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_scrollEnd);
    _loadNarrator().then((_) {
      if (!mounted) return;
      if (widget.startFreeMode) {
        _startFreeMode(widget.controller);
      } else if (widget.initialAdventure case final template?) {
        _startGuidedAdventure(template);
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_scrollEnd);
    composer.dispose();
    scroll.dispose();
    super.dispose();
  }

  void _scrollEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (scroll.hasClients) {
      scroll.animateTo(
        scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  });
  Future<void> _send() async {
    final text = composer.text;
    composer.clear();
    await widget.controller.submit(text);
  }

  Future<void> _loadNarrator() async {
    final bundledSmol = await modelStore.ensureBundledSmol();
    models = await modelStore.load();
    selectedModelId = await modelStore.selectedId();
    if (selectedModelId == null && bundledSmol != null) {
      selectedModelId = bundledSmol.id;
      await modelStore.select(selectedModelId);
    }
    final narratorSelection = NarratorSelection();
    final hasSavedNarrator = await narratorSelection.hasSavedProfile();
    var saved = await narratorSelection.load();
    if (!hasSavedNarrator && selectedModelId != null) {
      saved = NarratorCatalog.byId('local_gguf');
      await narratorSelection.save(saved);
    }
    fallbackKind = await NarratorFallbackSelection().load();
    if (!mounted) return;
    setState(() {
      profile = saved;
      isPreparingNarrator = false;
    });
    _applyNarrator(saved);
    _applyFallback();
  }

  void _applyNarrator(NarratorProfile value) {
    final model = models
        .where((model) => model.id == selectedModelId)
        .firstOrNull;
    widget.controller.setNarrator(
      NarratorCatalog.create(value, localModelPath: model?.path),
    );
  }

  void _applyFallback() {
    final model = models
        .where((model) => model.id == selectedModelId)
        .firstOrNull;
    switch (fallbackKind) {
      case NarratorFallbackKind.ask:
        widget.controller.setFallbackNarrator(null);
      case NarratorFallbackKind.localThenDemo:
        widget.controller.setFallbackNarrator(
          model == null
              ? NarratorCatalog.create(NarratorCatalog.byId('demo'))
              : NarratorCatalog.create(
                  NarratorCatalog.byId('local_gguf'),
                  localModelPath: model.path,
                ),
          label: model == null ? 'Storyteller demo' : 'Local GGUF',
        );
      case NarratorFallbackKind.demo:
        widget.controller.setFallbackNarrator(
          NarratorCatalog.create(NarratorCatalog.byId('demo')),
          label: 'Storyteller demo',
        );
    }
  }

  String get _fallbackLabel => switch (fallbackKind) {
    NarratorFallbackKind.ask => 'Ask me on each failure',
    NarratorFallbackKind.localThenDemo => 'Local GGUF, then demo if needed',
    NarratorFallbackKind.demo => 'Storyteller demo',
  };

  Future<void> _selectNarrator() async {
    final selected = await showModalBottomSheet<NarratorProfile>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Choose your Dungeon Master'),
            subtitle: Text(
              'The story ledger stays the source of truth with every model.',
            ),
          ),
          ...NarratorCatalog.profiles.map(
            (entry) => ListTile(
              leading: Icon(
                entry.kind == NarratorKind.demo
                    ? Icons.auto_awesome
                    : entry.kind == NarratorKind.localGguf
                    ? Icons.phone_android
                    : Icons.cloud_outlined,
              ),
              title: Text(entry.label),
              subtitle: Text(
                entry.ready
                    ? entry.description
                    : '${entry.description} Setup comes next.',
              ),
              trailing: entry.id == profile.id
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => Navigator.pop(context, entry),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.alt_route_outlined),
            title: const Text('Fallback lane'),
            subtitle: Text(_fallbackLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              Future<void>.microtask(_selectFallbackLane);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('Narration prompts'),
            subtitle: const Text('Tune Cloud or Local GGUF rules'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              Future<void>.microtask(_editNarrationPrompts);
            },
          ),
          ListTile(
            leading: const Icon(Icons.theater_comedy_outlined),
            title: const Text('Dungeon Master style'),
            subtitle: const Text('Add your own voice and personality guidance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              Future<void>.microtask(_editNarratorStyle);
            },
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    if (selected.kind == NarratorKind.cloud && !await _configureCloud()) {
      return;
    }
    if (!mounted) return;
    setState(() => profile = selected);
    _applyNarrator(selected);
    await NarratorSelection().save(selected);
  }

  Future<void> _selectFallbackLane() async {
    final selected = await showModalBottomSheet<NarratorFallbackKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Choose a fallback lane'),
            subtitle: Text(
              'A fallback is only used when you choose it after a narration failure.',
            ),
          ),
          ...[
            (
              NarratorFallbackKind.ask,
              'Ask me on each failure',
              'Keep Retry as the only recovery action.',
            ),
            (
              NarratorFallbackKind.localThenDemo,
              'Local GGUF, then demo if needed',
              'Use your selected offline model; demo is used when none is installed.',
            ),
            (
              NarratorFallbackKind.demo,
              'Storyteller demo',
              'Always use the built-in narrator as the recovery lane.',
            ),
          ].map(
            (entry) => ListTile(
              title: Text(entry.$2),
              subtitle: Text(entry.$3),
              trailing: entry.$1 == fallbackKind
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => Navigator.pop(context, entry.$1),
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => fallbackKind = selected);
    await NarratorFallbackSelection().save(selected);
    _applyFallback();
  }

  Future<void> _editNarrationPrompts() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListView(
      shrinkWrap: true,
      children: [
        const ListTile(
          title: Text('Narration prompts'),
          subtitle: Text(
            'The story ledger remains app-owned. These rules are applied to every future turn.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('Cloud prompt'),
          subtitle: const Text('Rules sent to your online provider'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            Future<void>.microtask(
              () => _editNarrationPrompt(NarratorPromptLane.cloud),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.phone_android_outlined),
          title: const Text('Local GGUF prompt'),
          subtitle: const Text('Template sent to your on-device model'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.pop(context);
            Future<void>.microtask(
              () => _editNarrationPrompt(NarratorPromptLane.localGguf),
            );
          },
        ),
        const SizedBox(height: 20),
      ],
    ),
  );

  Future<void> _editNarratorStyle() async {
    final settings = NarratorStyleSettings();
    final editor = TextEditingController(text: await settings.load());
    if (!mounted) {
      editor.dispose();
      return;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dungeon Master style'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Optional guidance for the narrator’s voice. It applies to both Cloud and Local GGUF narration, including Free Mode. The story ledger remains the source of truth.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: editor,
                minLines: 3,
                maxLines: 6,
                maxLength: 400,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Personality / style note',
                  hintText:
                      'Dry, mischievous fantasy narrator with compact, vivid prose.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await settings.save('');
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, 'cleared');
              }
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () async {
              await settings.save(editor.text);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext, 'saved');
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    editor.dispose();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == 'cleared'
              ? 'Dungeon Master style cleared.'
              : 'Dungeon Master style saved for future narration.',
        ),
      ),
    );
  }

  Future<void> _editNarrationPrompt(NarratorPromptLane lane) async {
    final settings = NarratorPromptSettings();
    final editor = TextEditingController(text: await settings.load(lane));
    if (!mounted) {
      editor.dispose();
      return;
    }
    final laneName = lane == NarratorPromptLane.cloud
        ? 'Cloud prompt'
        : 'Local GGUF prompt';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (dialogContext, update) => AlertDialog(
            title: Text(laneName),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lane == NarratorPromptLane.cloud
                          ? 'The canonical story packet is supplied separately on every turn.'
                          : 'Keep {{story_packet}} exactly once. It is replaced by the canonical story packet for each turn.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: editor,
                      minLines: 8,
                      maxLines: 14,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: laneName,
                        alignLabelWithHint: true,
                        errorText: error,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  await settings.reset(lane);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, 'reset');
                  }
                },
                child: const Text('Reset to default'),
              ),
              FilledButton(
                onPressed: () async {
                  final prompt = editor.text.trim();
                  if (prompt.isEmpty) {
                    update(() => error = 'Prompt cannot be empty.');
                    return;
                  }
                  if (lane == NarratorPromptLane.localGguf &&
                      !prompt.contains(
                        NarratorPromptSettings.storyPacketToken,
                      )) {
                    update(
                      () =>
                          error = 'Keep {{story_packet}} in the GGUF template.',
                    );
                    return;
                  }
                  await settings.save(lane, prompt);
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, 'saved');
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    editor.dispose();
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == 'reset'
              ? '$laneName reset to default.'
              : '$laneName saved.',
        ),
      ),
    );
  }

  Future<bool> _configureCloud() async {
    final existing = await CloudNarratorConfig.load();
    final keys = CloudKeyService();
    var provider = existing.provider;
    var hasKey = await keys.has(provider);
    if (!mounted) return false;
    final endpoint = TextEditingController(text: existing.baseUrl);
    final model = TextEditingController(text: existing.model);
    final apiKey = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Cloud provider setup'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Chatty Venture sends narration directly to the provider you choose. Your API key stays encrypted in Android Keystore; there is no fallback to another provider.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(provider),
                  initialValue: provider,
                  decoration: const InputDecoration(labelText: 'Provider'),
                  items: cloudProviders.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    final defaults = cloudProviderDefaults(value);
                    update(() {
                      provider = value;
                      endpoint.text = defaults.baseUrl;
                      model.text = defaults.model;
                    });
                    final nextHasKey = await keys.has(value);
                    update(() => hasKey = nextHasKey);
                  },
                ),
                TextField(
                  controller: endpoint,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                TextField(
                  controller: model,
                  decoration: const InputDecoration(labelText: 'Model'),
                ),
                TextField(
                  controller: apiKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: hasKey ? 'New API key (optional)' : 'API key',
                    helperText: hasKey
                        ? 'An encrypted key is already stored for this provider.'
                        : 'This is never saved in Flutter preferences.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save and use'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) {
      endpoint.dispose();
      model.dispose();
      apiKey.dispose();
      return false;
    }
    final baseUrl = endpoint.text.trim();
    final modelName = model.text.trim();
    final suppliedKey = apiKey.text.trim();
    endpoint.dispose();
    model.dispose();
    apiKey.dispose();
    final providerHasKey = await keys.has(provider);
    if (baseUrl.isEmpty ||
        modelName.isEmpty ||
        (!providerHasKey && suppliedKey.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Endpoint, model, and an API key are required.'),
          ),
        );
      }
      return false;
    }
    await CloudNarratorConfig(
      provider: provider,
      baseUrl: baseUrl,
      model: modelName,
    ).save();
    if (suppliedKey.isNotEmpty) await keys.save(provider, suppliedKey);
    return true;
  }

  Future<void> _importModel() async {
    final imported = await modelStore.importGguf();
    if (imported == null || !mounted) return;
    models = await modelStore.load();
    selectedModelId = imported.id;
    await modelStore.select(imported.id);
    profile = NarratorCatalog.byId('local_gguf');
    await NarratorSelection().save(profile);
    _applyNarrator(profile);
    _applyFallback();
    setState(() {});
  }

  Future<void> _showModels() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: StatefulBuilder(
            builder: (context, update) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                ListTile(
                  title: const Text('Local GGUF models'),
                  subtitle: const Text(
                    'Smol is included as the on-device baseline. Most phones run best with models below 1B parameters.',
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () async {
                      await _importModel();
                      update(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Import'),
                  ),
                ),
                ...models.map(
                  (model) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      model.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${(model.bytes / 1024 / 1024).toStringAsFixed(0)} MB · ${model.suitability}',
                    ),
                    leading: IconButton(
                      tooltip: model.id == selectedModelId
                          ? 'Selected model'
                          : 'Use this model',
                      icon: Icon(
                        model.id == selectedModelId
                            ? Icons.check_circle
                            : model.isRecommendedBaseline
                            ? Icons.recommend
                            : Icons.radio_button_unchecked,
                      ),
                      onPressed: () async {
                        selectedModelId = model.id;
                        await modelStore.select(model.id);
                        profile = NarratorCatalog.byId('local_gguf');
                        await NarratorSelection().save(profile);
                        _applyNarrator(profile);
                        _applyFallback();
                        update(() {});
                        setState(() {});
                      },
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove model',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await modelStore.remove(model);
                        models = await modelStore.load();
                        selectedModelId = await modelStore.selectedId();
                        _applyNarrator(profile);
                        _applyFallback();
                        update(() {});
                        setState(() {});
                      },
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 12),
                  child: Text(
                    'You can import another GGUF to experiment. Bigger models can produce richer narration, but use more memory and may run slowly on a phone. Try searching for “Qwen2.5-0.5B-Instruct GGUF”; models such as “Qwen2.5-1.5B-Instruct GGUF” are better reserved for powerful phones.',
                  ),
                ),
                if (models.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Import a .gguf model to narrate offline.'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refreshModelsAfterStorageChange() async {
    models = await modelStore.load();
    selectedModelId = await modelStore.selectedId();
    if (profile.kind == NarratorKind.localGguf && selectedModelId == null) {
      profile = NarratorCatalog.byId('demo');
      await NarratorSelection().save(profile);
    }
    _applyNarrator(profile);
    _applyFallback();
    if (mounted) setState(() {});
  }

  Future<void> _clearSavedAdventureData(AdventureController game) async {
    await game.saves.clear();
    await (await SharedPreferences.getInstance()).remove('selected_adventure');
    game.resetAfterPrivateDataClear();
  }

  Future<void> _clearAllPrivateData(AdventureController game) async {
    await modelStore.clearAllModels();
    await game.saves.clear();
    await CloudKeyService().deleteAllKnownProviders(cloudProviders.keys);
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
    models = [];
    selectedModelId = null;
    profile = NarratorCatalog.byId('demo');
    fallbackKind = NarratorFallbackKind.ask;
    _applyNarrator(profile);
    _applyFallback();
    game.resetAfterPrivateDataClear();
    if (mounted) setState(() {});
  }

  Future<void> _showStorageData(AdventureController game) =>
      showStorageDataSheet(
        context: context,
        onModelsChanged: _refreshModelsAfterStorageChange,
        onClearSavedAdventure: () => _clearSavedAdventureData(game),
        onClearAllPrivateData: () => _clearAllPrivateData(game),
        onManageModels: _showModels,
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final game = widget.controller;
      final narratorStatus = switch (profile.kind) {
        NarratorKind.demo => 'Built-in narration',
        NarratorKind.localGguf when selectedModelId == null =>
          'Local model needed',
        NarratorKind.localGguf => 'On-device GGUF',
        NarratorKind.cloud => 'Direct online lane',
      };
      return Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CHATTY-VENTURE',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                game.engine.template.title,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.memory_outlined),
              tooltip: 'Local GGUF models',
              onPressed: _showModels,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'New adventure',
              onPressed: () => _chooseAdventure(game),
            ),
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              tooltip: 'Choose Dungeon Master',
              onPressed: _selectNarrator,
            ),
            IconButton(
              icon: const Icon(Icons.auto_stories_outlined),
              tooltip: 'Story journal',
              onPressed: () => _journal(context, game),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF24202A),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFFFFD6A1),
                      size: 17,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        game.scene.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      'TURN ${game.state.turn}',
                      style: const TextStyle(
                        color: Color(0xFFD4C8B8),
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: _selectNarrator,
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF19151D),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        profile.kind == NarratorKind.localGguf
                            ? Icons.phone_android_outlined
                            : profile.kind == NarratorKind.cloud
                            ? Icons.cloud_outlined
                            : Icons.auto_awesome_outlined,
                        color: const Color(0xFFD4C8B8),
                        size: 14,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          '${profile.label} · $narratorStatus',
                          style: const TextStyle(
                            color: Color(0xFFD4C8B8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.tune,
                        color: Color(0xFFD4C8B8),
                        size: 15,
                      ),
                    ],
                  ),
                ),
              ),
              if (isPreparingNarrator)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF302934),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: const Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFFD6A1),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Preparing Smol for offline narration… first launch can take a moment.',
                          style: TextStyle(
                            color: Color(0xFFD4C8B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (models.isEmpty)
                Container(
                  width: double.infinity,
                  color: const Color(0xFF302934),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.offline_bolt_outlined,
                        color: Color(0xFFFFD6A1),
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Play offline: import a GGUF model any time.',
                          style: TextStyle(
                            color: Color(0xFFD4C8B8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _showModels,
                        child: const Text('Import'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: game.messages.length + (game.isNarrating ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == game.messages.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          game.narratorDraft.isEmpty
                              ? 'The storyteller is considering your move…'
                              : game.narratorDraft,
                          style: const TextStyle(fontStyle: FontStyle.italic),
                        ),
                      );
                    }
                    final message = game.messages[index];
                    return Align(
                      alignment: message.isPlayer
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: message.isPlayer
                              ? const Color(0xFF9B4637)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: message.isPlayer
                                ? Colors.white
                                : const Color(0xFF29232D),
                            height: 1.4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!game.isNarrating && game.narrationError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Card(
                    color: const Color(0xFFF8E5E0),
                    surfaceTintColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Color(0xFF4A231E),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Narration did not arrive.\n${game.narrationError}',
                                  style: const TextStyle(
                                    color: Color(0xFF4A231E),
                                  ),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 4,
                            children: [
                              TextButton(
                                onPressed: game.retryNarration,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF4A231E),
                                ),
                                child: const Text('Retry original'),
                              ),
                              if (game.fallbackLabel != null)
                                TextButton(
                                  onPressed: game.useFallbackNarration,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF4A231E),
                                  ),
                                  child: Text('Use ${game.fallbackLabel}'),
                                )
                              else
                                TextButton(
                                  onPressed: _selectFallbackLane,
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF4A231E),
                                  ),
                                  child: const Text('Choose fallback'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (game.fallbackNotice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Card(
                    color: const Color(0xFFDDECD9),
                    surfaceTintColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: Color(0xFF15351C),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              game.fallbackNotice!,
                              style: const TextStyle(color: Color(0xFF15351C)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (game.freeModeRun case final freeRun?
                  when !freeRun.isComplete &&
                      freeRun.completedStepsForAct(freeRun.act) == 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: OutlinedButton.icon(
                    onPressed: () => _showFreeModeHint(freeRun),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Hint'),
                  ),
                ),
              if (game.freeModeRun case final freeRun? when !freeRun.isComplete)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: freeModeActSteps(freeRun, freeRun.act)
                        .asMap()
                        .entries
                        .map(
                          (entry) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Icon(
                                  entry.key <
                                          freeRun.completedStepsForAct(
                                            freeRun.act,
                                          )
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color:
                                      entry.key <
                                          freeRun.completedStepsForAct(
                                            freeRun.act,
                                          )
                                      ? const Color(0xFF83C992)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                      color:
                                          entry.key <
                                              freeRun.completedStepsForAct(
                                                freeRun.act,
                                              )
                                          ? const Color(0xFF83C992)
                                          : null,
                                      decoration:
                                          entry.key <
                                              freeRun.completedStepsForAct(
                                                freeRun.act,
                                              )
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (game.freeModeRun == null &&
                  !game.isNarrating &&
                  game.state.ending == null &&
                  game.scene.choices.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                  child: OutlinedButton.icon(
                    onPressed: () => _showGuidedHint(game),
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Hint'),
                  ),
                ),
              if (game.freeModeStatusNotice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
                  child: Text(
                    game.freeModeStatusNotice!,
                    style: TextStyle(
                      color: game.freeModeRun?.isComplete == true
                          ? const Color(0xFF2E6B3C)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (game.isNarrating)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 5,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: game.cancelNarration,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop narration'),
                    ),
                  ),
                ),
              if (game.state.ending != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Venture complete',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(game.state.ending!),
                          if (game.freeModeRun case final freeRun?) ...[
                            const SizedBox(height: 12),
                            Text(
                              freeRun.bible.endingImage,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Alongside ${freeRun.bible.supportingCharacter}.',
                            ),
                            if (freeRun.epilogue case final afterword?) ...[
                              const SizedBox(height: 12),
                              Text(
                                'AFTERWORD',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              const SizedBox(height: 4),
                              Text(afterword),
                            ],
                            const SizedBox(height: 12),
                            ...freeRun.completedObjectives.map(
                              (act) => Text(
                                'Act ${act + 1} complete: ${freeRun.bible.objectives[act]}',
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => _chooseAdventure(game),
                            icon: const Icon(Icons.explore_outlined),
                            label: const Text('Start another venture'),
                          ),
                          if (game.freeModeRun != null) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: game.restart,
                              icon: const Icon(Icons.replay_outlined),
                              label: const Text('Begin this adventure again'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextField(
                    controller: composer,
                    enabled: !game.isNarrating && game.state.ending == null,
                    style: const TextStyle(
                      color: Color(0xFF111111),
                      fontWeight: FontWeight.w500,
                    ),
                    cursorColor: const Color(0xFF111111),
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: game.state.ending == null
                          ? 'Try something else…'
                          : 'This tale is complete.',
                      hintStyle: const TextStyle(color: Color(0xFF4A403C)),
                      filled: true,
                      fillColor: const Color(0xFFFFFBFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        onPressed: game.isNarrating || game.state.ending != null
                            ? null
                            : _send,
                        icon: const Icon(
                          Icons.arrow_upward_rounded,
                          color: Color(0xFF4A403C),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _showFreeModeHint(FreeModeRun run) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ACT ${run.act + 1} OF 3',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                run.bible.objectives[run.act],
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text('Current location: ${run.bible.locations[run.act]}'),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _showGuidedHint(
    AdventureController game,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Possible moves', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text(
            'These are optional leads, not the only way forward. You can always write your own action.',
          ),
          const SizedBox(height: 14),
          ...game.scene.choices.map(
            (choice) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  game.choose(choice);
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: Text(choice.label, textAlign: TextAlign.center),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _chooseAdventure(AdventureController game) async {
    final selected = await showModalBottomSheet<StoryTemplate>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Free Mode'),
            subtitle: const Text(
              'A fresh three-act adventure made for this run.',
            ),
            onTap: () {
              Navigator.pop(context);
              Future<void>.microtask(() => _startFreeMode(game));
            },
          ),
          const Divider(),
          ...AdventureCatalog.adventures.map(
            (template) => ListTile(
              title: Text(template.title),
              subtitle: Text(template.pitch),
              onTap: () => Navigator.pop(context, template),
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await _startGuidedAdventure(selected);
  }

  Future<void> _startGuidedAdventure(StoryTemplate selected) async {
    final setup = await showDialog<({String role, String tone})>(
      context: context,
      builder: (context) {
        final role = TextEditingController(text: 'A curious traveller');
        var tone = 'mysterious';
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(selected.title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: role,
                  decoration: const InputDecoration(labelText: 'Your role'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: tone,
                  decoration: const InputDecoration(labelText: 'Tone'),
                  items: const ['mysterious', 'hopeful', 'tense']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => update(() => tone = value ?? tone),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, (
                  role: role.text.trim().isEmpty
                      ? 'A curious traveller'
                      : role.text.trim(),
                  tone: tone,
                )),
                child: const Text('Begin'),
              ),
            ],
          ),
        );
      },
    );
    if (setup != null) {
      await widget.controller.startAdventure(
        selected,
        role: setup.role,
        tone: setup.tone,
      );
    }
  }

  Future<void> _startFreeMode(AdventureController game) async {
    final template = FreeModeCatalog.random();
    var narrator = game.narrator;
    FreeModeBible? bible;
    Object? error;
    while (mounted && bible == null) {
      try {
        bible = await _generateFreeModeBible(narrator, template);
      } catch (caught) {
        error = caught;
      }
      if (bible != null || !mounted) break;
      final recovery = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Adventure setup did not arrive'),
          content: Text('$error\n\nNo story has been started or changed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'retry'),
              child: const Text('Retry'),
            ),
            if (game.fallbackNarrator != null)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'fallback'),
                child: Text('Use ${game.fallbackLabel ?? 'fallback'}'),
              ),
          ],
        ),
      );
      if (recovery == 'fallback') {
        narrator = game.fallbackNarrator!;
      } else if (recovery != 'retry') {
        return;
      }
    }
    if (bible == null || !mounted) return;
    final frozen = await _previewFreeModeBible(bible, template);
    if (frozen != null && mounted) {
      await game.startFreeMode(template, frozen);
    }
  }

  Future<FreeModeBible> _generateFreeModeBible(
    AiDungeonMaster narrator,
    FreeModeTemplate template,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('Creating your adventure…')),
          ],
        ),
      ),
    );
    try {
      return await FreeModeProposalService().generate(narrator, template);
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<FreeModeBible?> _previewFreeModeBible(
    FreeModeBible bible,
    FreeModeTemplate template,
  ) async {
    var current = bible;
    while (true) {
      if (!mounted) return null;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Generated adventure'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(current.premise),
                const SizedBox(height: 12),
                Text('Problem: ${current.problem}'),
                Text('Key detail: ${current.keyAnchor}'),
                Text('With: ${current.supportingCharacter}'),
                const SizedBox(height: 8),
                Text('What is at stake: ${current.stakes}'),
                Text('Pressure: ${current.escalation}'),
                Text('If you prevail: ${current.endingImage}'),
                const SizedBox(height: 12),
                for (var index = 0; index < 3; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Act ${index + 1} — ${current.locations[index]}\n${current.objectives[index]}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Edit'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'proceed'),
              child: const Text('Proceed'),
            ),
          ],
        ),
      );
      if (action == 'proceed') return current;
      if (action != 'edit') return null;
      final edited = await _editFreeModeBible(current, template);
      if (edited != null) current = edited;
    }
  }

  Future<FreeModeBible?> _editFreeModeBible(
    FreeModeBible bible,
    FreeModeTemplate template,
  ) async {
    final title = TextEditingController(text: bible.title);
    final premise = TextEditingController(text: bible.premise);
    final problem = TextEditingController(text: bible.problem);
    final anchor = TextEditingController(text: bible.keyAnchor);
    final supportingCharacter = TextEditingController(
      text: bible.supportingCharacter,
    );
    final stakes = TextEditingController(text: bible.stakes);
    final escalation = TextEditingController(text: bible.escalation);
    final endingImage = TextEditingController(text: bible.endingImage);
    final flavour = TextEditingController(text: bible.flavour);
    final locations = bible.locations
        .map((value) => TextEditingController(text: value))
        .toList();
    final objectives = bible.objectives
        .map((value) => TextEditingController(text: value))
        .toList();
    final result = await showDialog<FreeModeBible>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit adventure'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: premise,
                  decoration: const InputDecoration(labelText: 'Premise'),
                ),
                TextField(
                  controller: problem,
                  decoration: const InputDecoration(labelText: 'Problem'),
                ),
                TextField(
                  controller: anchor,
                  decoration: const InputDecoration(labelText: 'Key detail'),
                ),
                TextField(
                  controller: supportingCharacter,
                  decoration: const InputDecoration(
                    labelText: 'Supporting character',
                  ),
                ),
                TextField(
                  controller: stakes,
                  decoration: const InputDecoration(
                    labelText: 'What is at stake',
                  ),
                ),
                TextField(
                  controller: escalation,
                  decoration: const InputDecoration(labelText: 'Escalation'),
                ),
                TextField(
                  controller: endingImage,
                  decoration: const InputDecoration(labelText: 'Ending image'),
                ),
                TextField(
                  controller: flavour,
                  decoration: const InputDecoration(labelText: 'Flavour'),
                ),
                for (var index = 0; index < 3; index++) ...[
                  TextField(
                    controller: locations[index],
                    decoration: InputDecoration(
                      labelText: 'Act ${index + 1} location',
                    ),
                  ),
                  TextField(
                    controller: objectives[index],
                    decoration: InputDecoration(
                      labelText: 'Act ${index + 1} objective',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              FreeModeBible(
                title: title.text.trim(),
                premise: premise.text.trim(),
                problem: problem.text.trim(),
                keyAnchor: anchor.text.trim(),
                supportingCharacter: supportingCharacter.text.trim(),
                stakes: stakes.text.trim(),
                escalation: escalation.text.trim(),
                endingImage: endingImage.text.trim(),
                flavour: flavour.text.trim(),
                locations: locations
                    .map((controller) => controller.text.trim())
                    .toList(),
                objectives: objectives
                    .map((controller) => controller.text.trim())
                    .toList(),
              ),
            ),
            child: const Text('Use these details'),
          ),
        ],
      ),
    );
    for (final controller in [
      title,
      premise,
      problem,
      anchor,
      supportingCharacter,
      stakes,
      escalation,
      endingImage,
      flavour,
      ...locations,
      ...objectives,
    ]) {
      controller.dispose();
    }
    return result?.isUsable == true ? result : null;
  }

  void _journal(
    BuildContext context,
    AdventureController game,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            'Story journal',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (game.freeModeRun case final freeRun?) ...[
            Text(
              'YOUR ADVENTURE',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Text(
              freeRun.bible.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(freeRun.bible.premise),
            const SizedBox(height: 8),
            Text('With ${freeRun.bible.supportingCharacter}'),
            Text('Stakes: ${freeRun.bible.stakes}'),
            Text('Pressure: ${freeRun.bible.escalation}'),
            if (freeRun.history.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'LAST MOMENT',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(freeRun.history.last),
            ],
            const SizedBox(height: 12),
          ],
          Text('OPEN THREADS', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          if (game.state.threads.isEmpty)
            const Text('Nothing is pressing yet. Keep exploring.')
          else
            ...game.state.threads.values.map(
              (thread) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(thread.label),
                subtitle: Text(thread.status),
              ),
            ),
          const SizedBox(height: 12),
          Text('RECENTLY', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          ...game.state.recap.reversed
              .take(5)
              .map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $line'),
                ),
              ),
          const SizedBox(height: 12),
          Text('DM', style: Theme.of(context).textTheme.labelMedium),
          Text('${game.narrator.label} · model-agnostic narrator seam'),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.storage_outlined),
            title: const Text('Storage & data'),
            subtitle: const Text('Manage local models and private app data'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              Future<void>.microtask(() => _showStorageData(game));
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark mode'),
            secondary: Icon(
              widget.darkMode ? Icons.dark_mode : Icons.light_mode,
            ),
            value: widget.darkMode,
            onChanged: (_) => widget.onToggleTheme(),
          ),
        ],
      ),
    ),
  );

  // Kept for a future in-adventure reset affordance.
  // ignore: unused_element
  Future<void> _confirmRestart(AdventureController game) async {
    final shouldRestart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Begin again?'),
        content: const Text('This replaces the current saved story.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep story'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Begin again'),
          ),
        ],
      ),
    );
    if (shouldRestart == true) await game.restart();
  }
}
