import '../story/story_models.dart';
import 'narrator_prompt_settings.dart';

abstract interface class AiDungeonMaster {
  String get label;
  void cancel();
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  });
}

class NarratorContext {
  const NarratorContext({
    required this.scene,
    required this.events,
    required this.facts,
    required this.threads,
    required this.recap,
    required this.ending,
    this.cloudInstructionOverride,
    this.ggufTemplateOverride,
    this.structuredOutput = false,
    this.canonicalAddendum,
  });
  final StoryScene scene;
  final List<StoryEvent> events;
  final Set<String> facts;
  final Map<String, StoryThread> threads;
  final List<String> recap;
  final String? ending;
  final String? cloudInstructionOverride;
  final String? ggufTemplateOverride;
  final bool structuredOutput;
  final String? canonicalAddendum;

  factory NarratorContext.freeModeProposal(String geometry) => NarratorContext(
    scene: const StoryScene(
      id: 'free_mode_setup',
      title: 'Free Mode setup',
      description: 'Create a compact, self-contained adventure proposal.',
      choices: [],
    ),
    events: const [StoryEvent('proposal', 'Generate the requested run bible.')],
    facts: const {},
    threads: const {},
    recap: [geometry],
    ending: null,
    structuredOutput: true,
    cloudInstructionOverride:
        'Return JSON only. Create a small self-contained three-act adventure using the supplied geometry. Do not write narration or markdown. Required fields: title, premise, problem, key_anchor, supporting_character, stakes, escalation, ending_image, locations (exactly 3 strings), objectives (exactly 3 strings), flavour. Keep every field concrete and short.',
    ggufTemplateOverride:
        '''Return JSON only. Create a small self-contained three-act adventure using the supplied geometry. Do not write narration or markdown. Required fields: title, premise, problem, key_anchor, supporting_character, stakes, escalation, ending_image, locations (exactly 3 strings), objectives (exactly 3 strings), flavour. Keep every field concrete and short.

{{story_packet}}''',
  );

  factory NarratorContext.freeModeEpilogue(
    String canonicalSummary,
  ) => NarratorContext(
    scene: const StoryScene(
      id: 'free_mode_afterword',
      title: 'Afterword',
      description: 'The adventure has reached its confirmed ending.',
      choices: [],
    ),
    events: const [
      StoryEvent('ended', 'All three host-owned objectives are complete.'),
    ],
    facts: const {},
    threads: const {},
    recap: const [],
    ending: null,
    canonicalAddendum: canonicalSummary,
    cloudInstructionOverride:
        'Write one warm, surprising afterword paragraph for a completed casual text adventure. Reflect on the confirmed completed objectives and ending image. You may imaginatively riff on the adventurer’s later life, reputation, fortunes, or peaceful old age, but do not rewrite any completed fact. Return prose only, no heading or analysis.',
    ggufTemplateOverride:
        '''Write one warm, surprising afterword paragraph for a completed casual text adventure. Reflect on the confirmed completed objectives and ending image. You may imaginatively riff on the adventurer’s later life, reputation, fortunes, or peaceful old age, but do not rewrite any completed fact. Return prose only, no heading or analysis.

{{story_packet}}''',
  );

  String toCloudInstruction({String? instruction, String? styleNote}) {
    final effectiveInstruction = instruction ?? cloudInstructionOverride;
    final baseInstruction = effectiveInstruction?.trim().isNotEmpty == true
        ? effectiveInstruction!.trim()
        : NarratorPromptSettings.defaultCloudInstruction;
    return _withStyleNote(baseInstruction, styleNote);
  }

  String toStoryPacket() =>
      '''SCENE: ${scene.title}
SCENE DESCRIPTION: ${scene.description}
CONFIRMED TURN: ${events.map((event) => event.detail).join(' ')}
DURABLE FACTS: ${facts.isEmpty ? 'none' : facts.join(', ')}
OPEN THREADS: ${threads.values.map((thread) => '${thread.label}: ${thread.status}').join(' | ')}
RECENT RECAP: ${recap.join(' | ')}
ENDING: ${ending ?? 'none'}''';
  String toCanonicalPacket() =>
      '${toStoryPacket()}${canonicalAddendum == null || canonicalAddendum!.trim().isEmpty ? '' : '\n$canonicalAddendum'}';

  /// Exact prompt used by the last known-good 360M GGUF narration path.
  /// Cloud formatting remains separate below this canonical state packet.
  String toGgufPrompt({String? template, String? styleNote}) {
    final suppliedTemplate = template ?? ggufTemplateOverride;
    final effectiveTemplate = suppliedTemplate?.trim().isNotEmpty == true
        ? suppliedTemplate!.trim()
        : NarratorPromptSettings.defaultGgufTemplate;
    // The editor requires the token. This defensive branch also protects the
    // ledger if a manually-corrupted stored value lacks it.
    final packet = _withStyleNote(toCanonicalPacket(), styleNote);
    return effectiveTemplate.contains(NarratorPromptSettings.storyPacketToken)
        ? effectiveTemplate.replaceAll(
            NarratorPromptSettings.storyPacketToken,
            packet,
          )
        : '$effectiveTemplate\n\n$packet';
  }

  String _withStyleNote(String value, String? styleNote) {
    final style = styleNote?.trim() ?? '';
    if (style.isEmpty) return value;
    return '$value\n\nDM STYLE NOTE: $style\nTreat this as delivery guidance only. Do not change established facts, routes, objectives, or outcomes.';
  }

  /// Compatibility alias for existing prompt consumers.
  String toPrompt() => toGgufPrompt();

  static bool isUsableNarration(String text) {
    final words = text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    if (words.length < 30) return false;
    final lower = text.toLowerCase();
    return !lower.contains('you are the narrator') &&
        !lower.contains('write narration for') &&
        !lower.contains('scene description:') &&
        !lower.contains('confirmed turn:') &&
        !lower.contains('durable facts:') &&
        !lower.contains('fleeting sensory texture allowed');
  }
}

class DemoDungeonMaster implements AiDungeonMaster {
  @override
  String get label => 'Storyteller demo';

  @override
  void cancel() {}
  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (context.scene.id == 'free_mode_afterword') {
      const response =
          'Years later, the traveller was still remembered for the night they kept going when the way ahead had gone dark. Their practical courage became a small local legend, and they lived long enough to enjoy its telling.';
      onToken?.call(response);
      return response;
    }
    if (context.ending case final ending?) return ending;
    final event = context.events.first;
    final response = switch (event.kind) {
      'blocked' =>
        '${event.detail} The night offers no shortcut, only another choice.',
      'moved' => '${event.detail}\n\n${context.scene.description}',
      'learned' =>
        '${event.detail} Somewhere in the rain, the blue lantern brightens.',
      'discovered' =>
        '${event.detail} Ink ripples around it, as though the harbour has been holding its breath.',
      // Free Mode routes carry detailed host packets for cloud and GGUF
      // narrators. The demo lane must never expose those implementation
      // details when it is serving as the player's safe fallback.
      'attempted' =>
        'You test the situation carefully, watching for what changes.\n\n${context.scene.description}',
      'objective_completed' =>
        'The immediate work is done, and the path ahead comes into focus.\n\n${context.scene.description}',
      'transition' =>
        'A new stretch of the journey opens before you.\n\n${context.scene.description}',
      _ => '${event.detail}\n\n${context.scene.description}',
    };
    onToken?.call(response);
    return response;
  }
}
