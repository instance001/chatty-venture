import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'narrator.dart';
import 'cloud_narrator.dart';
import 'narrator_prompt_settings.dart';
import 'narrator_style_settings.dart';

enum NarratorKind { demo, localGguf, cloud }

enum NarratorFallbackKind { ask, localThenDemo, demo }

class NarratorProfile {
  const NarratorProfile({
    required this.id,
    required this.kind,
    required this.label,
    required this.description,
    this.ready = false,
  });
  final String id;
  final NarratorKind kind;
  final String label;
  final String description;
  final bool ready;
}

/// Model selection is separate from game state. Credentials are deliberately
/// not stored here; cloud credentials need an Android Keystore service.
class NarratorCatalog {
  static const profiles = [
    NarratorProfile(
      id: 'demo',
      kind: NarratorKind.demo,
      label: 'Storyteller demo',
      description: 'A built-in deterministic narrator for testing adventures.',
      ready: true,
    ),
    NarratorProfile(
      id: 'local_gguf',
      kind: NarratorKind.localGguf,
      label: 'Local GGUF',
      description: 'On-device narration through the bundled native runtime.',
      ready: false,
    ),
    NarratorProfile(
      id: 'cloud',
      kind: NarratorKind.cloud,
      label: 'Cloud provider',
      description:
          'A direct OpenAI-compatible endpoint configured on this device.',
      ready: true,
    ),
  ];

  static NarratorProfile byId(String id) => profiles.firstWhere(
    (profile) => profile.id == id,
    orElse: () => profiles.first,
  );
  static AiDungeonMaster create(
    NarratorProfile profile, {
    String? localModelPath,
  }) => switch (profile.kind) {
    NarratorKind.demo => DemoDungeonMaster(),
    NarratorKind.localGguf when localModelPath != null =>
      LocalGgufDungeonMaster(profile.label, localModelPath),
    NarratorKind.localGguf => UnavailableDungeonMaster(
      profile.label,
      'No GGUF model has been imported and assigned yet.',
    ),
    NarratorKind.cloud => CloudDungeonMaster(),
  };
}

class NarratorSelection {
  static const _key = 'selected_narrator_profile';

  Future<bool> hasSavedProfile() async =>
      (await SharedPreferences.getInstance()).containsKey(_key);

  Future<NarratorProfile> load() async => NarratorCatalog.byId(
    (await SharedPreferences.getInstance()).getString(_key) ?? 'demo',
  );
  Future<void> save(NarratorProfile profile) async =>
      (await SharedPreferences.getInstance()).setString(_key, profile.id);
}

class NarratorFallbackSelection {
  static const _key = 'selected_narrator_fallback';

  Future<NarratorFallbackKind> load() async =>
      switch ((await SharedPreferences.getInstance()).getString(_key)) {
        'local_then_demo' => NarratorFallbackKind.localThenDemo,
        'demo' => NarratorFallbackKind.demo,
        _ => NarratorFallbackKind.ask,
      };

  Future<void> save(NarratorFallbackKind fallback) async =>
      (await SharedPreferences.getInstance()).setString(
        _key,
        switch (fallback) {
          NarratorFallbackKind.localThenDemo => 'local_then_demo',
          NarratorFallbackKind.demo => 'demo',
          NarratorFallbackKind.ask => 'ask',
        },
      );
}

/// The Flutter-to-native handoff is intentionally narrow: the native layer gets
/// a bounded prompt and returns only narration text. It cannot mutate a run.
class LocalGgufDungeonMaster implements AiDungeonMaster {
  LocalGgufDungeonMaster(this.label, this.modelPath);
  @override
  final String label;
  final String modelPath;
  static const _channel = MethodChannel('chatty_venture/local_gguf');

  @override
  void cancel() {
    _channel.invokeMethod<void>('cancel');
  }

  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async {
    final promptTemplate =
        context.ggufTemplateOverride ??
        await NarratorPromptSettings().load(NarratorPromptLane.localGguf);
    final styleNote = await NarratorStyleSettings().load();
    final draft = StringBuffer();
    final subscription = _events.receiveBroadcastStream().cast<Map>().listen((
      event,
    ) {
      if (event['type'] == 'token') {
        final token = event['text'] as String? ?? '';
        draft.write(token);
        onToken?.call(token);
      }
    });
    final result = await _channel.invokeMapMethod<String, dynamic>('generate', {
      'prompt': context.toGgufPrompt(
        template: promptTemplate,
        styleNote: styleNote,
      ),
      'modelPath': modelPath,
      // A Free Mode bible is structured JSON rather than a short scene. Give
      // it room to finish without changing the fast, mobile-friendly turn
      // settings used during normal play.
      'contextSize': context.structuredOutput ? 2048 : 1536,
      'maxTokens': context.structuredOutput ? 480 : 120,
    });
    await subscription.cancel();
    final text = result?['text'] as String? ?? draft.toString();
    if (text.trim().isEmpty) {
      throw StateError('The local narrator returned no text.');
    }
    return text;
  }

  static const _events = EventChannel('chatty_venture/local_gguf_events');
}

class UnavailableDungeonMaster implements AiDungeonMaster {
  const UnavailableDungeonMaster(this.label, this.reason);
  @override
  final String label;
  final String reason;
  @override
  void cancel() {}
  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) => Future<String>.error(StateError(reason));
}
