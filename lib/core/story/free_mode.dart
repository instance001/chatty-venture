import 'dart:convert';
import 'dart:math';

import '../narration/narrator.dart';
import 'story_models.dart';

class FreeModeTemplate {
  const FreeModeTemplate({
    required this.id,
    required this.label,
    required this.pitch,
    required this.actGoals,
    required this.completionKeywords,
  });
  final String id;
  final String label;
  final String pitch;
  final List<String> actGoals;
  final List<List<String>> completionKeywords;
}

class FreeModeCatalog {
  static const templates = [
    FreeModeTemplate(
      id: 'mystery',
      label: 'Mystery',
      pitch: 'Discover a problem, trace its cause, and resolve it.',
      actGoals: [
        'discover the problem',
        'uncover the cause',
        'confront and resolve it',
      ],
      completionKeywords: [
        ['discover', 'find', 'investigate', 'identify', 'reveal'],
        ['trace', 'uncover', 'reach', 'expose', 'learn'],
        ['confront', 'resolve', 'stop', 'settle', 'finish'],
      ],
    ),
    FreeModeTemplate(
      id: 'retrieval',
      label: 'Retrieval',
      pitch:
          'Learn what is needed, obtain it, then use it to resolve the crisis.',
      actGoals: [
        'learn what is needed',
        'reach and obtain it',
        'return and use it',
      ],
      completionKeywords: [
        ['learn', 'find', 'identify', 'discover', 'ask'],
        ['reach', 'obtain', 'take', 'retrieve', 'secure'],
        ['return', 'use', 'deliver', 'restore', 'resolve'],
      ],
    ),
    FreeModeTemplate(
      id: 'escape',
      label: 'Escape',
      pitch:
          'Understand the trap, overcome its obstruction, then reach safety.',
      actGoals: [
        'establish the trap',
        'overcome the obstruction',
        'reach safety',
      ],
      completionKeywords: [
        ['learn', 'discover', 'understand', 'identify', 'find'],
        ['overcome', 'unlock', 'bypass', 'defeat', 'clear'],
        ['escape', 'reach', 'flee', 'arrive', 'survive'],
      ],
    ),
  ];

  static FreeModeTemplate byId(String id) => templates.firstWhere(
    (template) => template.id == id,
    orElse: () => templates.first,
  );

  static FreeModeTemplate random([Random? random]) =>
      templates[(random ?? Random()).nextInt(templates.length)];
}

class FreeModeBible {
  const FreeModeBible({
    required this.title,
    required this.premise,
    required this.problem,
    required this.keyAnchor,
    required this.supportingCharacter,
    required this.stakes,
    required this.escalation,
    required this.endingImage,
    required this.locations,
    required this.objectives,
    required this.flavour,
  });
  final String title;
  final String premise;
  final String problem;
  final String keyAnchor;
  final String supportingCharacter;
  final String stakes;
  final String escalation;
  final String endingImage;
  final List<String> locations;
  final List<String> objectives;
  final String flavour;

  bool get isUsable =>
      [
        title,
        premise,
        problem,
        keyAnchor,
        supportingCharacter,
        stakes,
        escalation,
        endingImage,
        flavour,
      ].every((value) => value.trim().length >= 3) &&
      locations.length == 3 &&
      objectives.length == 3 &&
      locations.every((value) => value.trim().length >= 3) &&
      objectives.every((value) => value.trim().length >= 3);

  Map<String, Object?> toJson() => {
    'title': title,
    'premise': premise,
    'problem': problem,
    'key_anchor': keyAnchor,
    'supporting_character': supportingCharacter,
    'stakes': stakes,
    'escalation': escalation,
    'ending_image': endingImage,
    'locations': locations,
    'objectives': objectives,
    'flavour': flavour,
  };

  factory FreeModeBible.fromJson(Map source) {
    String read(String key) => source[key]?.toString().trim() ?? '';
    List<String> list(String key) => (source[key] as List? ?? const [])
        .map((value) => value.toString().trim())
        .toList();
    return FreeModeBible(
      title: read('title'),
      premise: read('premise'),
      problem: read('problem'),
      keyAnchor: read('key_anchor'),
      // Older Free Mode saves predate these optional dramatic anchors. Keep
      // their established canon intact rather than dropping the whole run.
      supportingCharacter: read('supporting_character').isEmpty
          ? 'No companion was recorded.'
          : read('supporting_character'),
      stakes: read('stakes').isEmpty
          ? 'The original stakes were not recorded.'
          : read('stakes'),
      escalation: read('escalation').isEmpty
          ? 'The original pressure was not recorded.'
          : read('escalation'),
      endingImage: read('ending_image').isEmpty
          ? 'The original ending image was not recorded.'
          : read('ending_image'),
      locations: list('locations'),
      objectives: list('objectives'),
      flavour: read('flavour'),
    );
  }

  FreeModeBible copyWith({
    String? title,
    String? premise,
    String? problem,
    String? keyAnchor,
    String? supportingCharacter,
    String? stakes,
    String? escalation,
    String? endingImage,
    List<String>? locations,
    List<String>? objectives,
    String? flavour,
  }) => FreeModeBible(
    title: title ?? this.title,
    premise: premise ?? this.premise,
    problem: problem ?? this.problem,
    keyAnchor: keyAnchor ?? this.keyAnchor,
    supportingCharacter: supportingCharacter ?? this.supportingCharacter,
    stakes: stakes ?? this.stakes,
    escalation: escalation ?? this.escalation,
    endingImage: endingImage ?? this.endingImage,
    locations: locations ?? this.locations,
    objectives: objectives ?? this.objectives,
    flavour: flavour ?? this.flavour,
  );
}

class FreeModeRun {
  const FreeModeRun({
    required this.templateId,
    required this.bible,
    this.act = 0,
    this.completedObjectives = const [],
    this.completedSteps = const [],
    this.history = const [],
    this.epilogue,
  });
  final String templateId;
  final FreeModeBible bible;
  final int act;
  final List<int> completedObjectives;

  /// Number of host-confirmed beats completed in each act (always 0–2).
  final List<int> completedSteps;
  final List<String> history;
  final String? epilogue;
  bool get isComplete => act >= 3;

  int completedStepsForAct(int targetAct) =>
      targetAct < completedSteps.length ? completedSteps[targetAct] : 0;

  FreeModeRun copyWith({
    int? act,
    List<int>? completedObjectives,
    List<int>? completedSteps,
    List<String>? history,
    String? epilogue,
  }) => FreeModeRun(
    templateId: templateId,
    bible: bible,
    act: act ?? this.act,
    completedObjectives: completedObjectives ?? this.completedObjectives,
    completedSteps: completedSteps ?? this.completedSteps,
    history: history ?? this.history,
    epilogue: epilogue ?? this.epilogue,
  );

  Map<String, Object?> toJson() => {
    'template_id': templateId,
    'bible': bible.toJson(),
    'act': act,
    'completed_objectives': completedObjectives,
    'completed_steps': completedSteps,
    'history': history,
    'epilogue': epilogue,
  };

  factory FreeModeRun.fromJson(Map source) {
    final bible = source['bible'];
    if (bible is! Map) throw const FormatException('Invalid Free Mode bible.');
    final result = FreeModeRun(
      templateId: source['template_id']?.toString() ?? '',
      bible: FreeModeBible.fromJson(bible),
      act: source['act'] as int? ?? 0,
      completedObjectives: (source['completed_objectives'] as List? ?? const [])
          .whereType<int>()
          .toList(),
      completedSteps: (source['completed_steps'] as List? ?? const [])
          .whereType<int>()
          .map((count) => count.clamp(0, 2))
          .toList(),
      history: (source['history'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      epilogue: source['epilogue'] as String?,
    );
    if (result.templateId.isEmpty || !result.bible.isUsable) {
      throw const FormatException('Invalid Free Mode run.');
    }
    return result;
  }
}

class FreeModeReduction {
  const FreeModeReduction({
    required this.run,
    required this.completed,
    required this.progressed,
    required this.ended,
    required this.detail,
  });
  final FreeModeRun run;
  final bool completed;
  final bool progressed;
  final bool ended;
  final String detail;
}

/// A bounded intent seam: only the player's text is inspected. Narrator prose
/// is never an input here and therefore cannot complete an act.
class FreeModeReducer {
  FreeModeReduction apply(FreeModeRun run, String playerText) {
    if (run.isComplete) {
      return FreeModeReduction(
        run: run,
        completed: false,
        progressed: false,
        ended: true,
        detail: 'This adventure is complete.',
      );
    }
    final steps = freeModeActSteps(run, run.act);
    final completedSteps = run.completedStepsForAct(run.act);
    final matches = _matchesStep(run, playerText, completedSteps);
    if (!matches) {
      return FreeModeReduction(
        run: run,
        completed: false,
        progressed: false,
        ended: false,
        detail: 'You continue working toward: ${run.bible.objectives[run.act]}',
      );
    }
    final nextStepCount = completedSteps + 1;
    final updatedSteps = List<int>.from(run.completedSteps);
    while (updatedSteps.length <= run.act) {
      updatedSteps.add(0);
    }
    updatedSteps[run.act] = nextStepCount;
    if (nextStepCount < steps.length) {
      return FreeModeReduction(
        run: run.copyWith(completedSteps: updatedSteps),
        completed: false,
        progressed: true,
        ended: false,
        detail: 'Progress recorded: ${steps[completedSteps]}',
      );
    }
    final completed = [...run.completedObjectives, run.act];
    final nextAct = run.act + 1;
    return FreeModeReduction(
      run: run.copyWith(
        act: nextAct,
        completedObjectives: completed,
        completedSteps: updatedSteps,
      ),
      completed: true,
      progressed: true,
      ended: nextAct == 3,
      detail: nextAct == 3
          ? 'You complete the final objective: ${run.bible.objectives[2]}'
          : 'You complete: ${run.bible.objectives[run.act]}',
    );
  }

  bool _matchesStep(FreeModeRun run, String playerText, int step) {
    final words = _words(playerText);
    if (words.isEmpty) return false;
    // Beat one is deliberately forgiving: "look around", "inspect it", and
    // similarly rough mobile input all establish that the player engaged with
    // the current situation. Beat two is the guarded objective completion.
    if (step == 0) return _containsNear(words, _scoutingWords);
    final template = FreeModeCatalog.byId(run.templateId);
    final completionWords = {
      ...template.completionKeywords[run.act],
      'get',
      'take',
      'collect',
      'repair',
      'fix',
      'secure',
      'retrieve',
      'obtain',
      'use',
      'establish',
    };
    return _containsNear(words, completionWords) &&
        _containsNear(words, _relevantTerms(run, run.act));
  }

  static const _scoutingWords = {
    'look',
    'search',
    'inspect',
    'investigate',
    'examine',
    'check',
    'approach',
    'enter',
    'explore',
    'ask',
    'listen',
    'diagnose',
    'assess',
  };

  Set<String> _relevantTerms(FreeModeRun run, int act) {
    final text = [
      run.bible.objectives[act],
      run.bible.locations[act],
      run.bible.problem,
      run.bible.keyAnchor,
    ].join(' ').toLowerCase();
    return _words(text)
        .where((word) => word.length >= 4)
        .where((word) => !_scoutingWords.contains(word))
        .where(
          (word) =>
              !{'with', 'from', 'that', 'this', 'then', 'into'}.contains(word),
        )
        .toSet()
        .toSet();
  }

  Set<String> _words(String value) => value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toSet();

  bool _containsNear(Set<String> input, Iterable<String> targets) =>
      input.any((word) => targets.any((target) => _isNear(word, target)));

  bool _isNear(String word, String target) {
    if (word == target) return true;
    if (word.length < 4 || target.length < 4) return false;
    final allowedDistance = target.length >= 8 ? 2 : 1;
    if ((word.length - target.length).abs() > allowedDistance) return false;
    var previous = List<int>.generate(target.length + 1, (index) => index);
    for (var row = 1; row <= word.length; row++) {
      final current = List<int>.filled(target.length + 1, 0)..[0] = row;
      for (var column = 1; column <= target.length; column++) {
        final substitution =
            previous[column - 1] +
            (word[row - 1] == target[column - 1] ? 0 : 1);
        current[column] = [
          previous[column] + 1,
          current[column - 1] + 1,
          substitution,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return previous.last <= allowedDistance;
  }
}

/// A visible, host-owned two-beat route for every act. A generated objective
/// that already has two clauses keeps them; otherwise reconnaissance is added
/// before the model-authored objective.
List<String> freeModeActSteps(FreeModeRun run, int act) {
  final clauses = run.bible.objectives[act]
      .split(RegExp(r'\b(?:and then|then|and|before)\b', caseSensitive: false))
      .map((clause) => clause.trim())
      .where((clause) => clause.length >= 3)
      .toList();
  if (clauses.length >= 2) {
    return [clauses.first, clauses.skip(1).join(' then ')];
  }
  return [
    'Survey ${run.bible.locations[act]} and assess the situation',
    run.bible.objectives[act],
  ];
}

class FreeModeProposalService {
  Future<FreeModeBible> generate(
    AiDungeonMaster narrator,
    FreeModeTemplate template,
  ) async {
    if (narrator is DemoDungeonMaster) return _demo(template);
    final context = NarratorContext.freeModeProposal(
      '${template.label}: ${template.actGoals.join(' → ')}',
    );
    final response = await narrator.narrate(context);
    final bible = _parse(response);
    if (!bible.isUsable) {
      throw StateError('The generated adventure is missing required details.');
    }
    return bible;
  }

  FreeModeBible _parse(String source) {
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(source)?.group(1);
    final decoded = jsonDecode(fenced ?? source);
    if (decoded is! Map) {
      throw const FormatException('Generated adventure was not an object.');
    }
    return FreeModeBible.fromJson(decoded);
  }

  FreeModeBible _demo(FreeModeTemplate template) => FreeModeBible(
    title: '${template.label} at Ember Crossing',
    premise: 'A quiet settlement needs your help before nightfall.',
    problem: 'The Lantern Engine has fallen silent.',
    keyAnchor: 'a brass compass',
    supportingCharacter: 'Mara, the tired signal keeper',
    stakes: 'The crossing will flood if the Lantern Engine stays dark.',
    escalation: 'At the second act, the river begins to breach the old works.',
    endingImage:
        'At dawn, the river gate opens beneath a returning line of lanterns.',
    locations: const ['Ember Crossing', 'The old works', 'The river gate'],
    objectives: template.actGoals,
    flavour: 'Warm rain, old brick, and a distant bell.',
  );
}

StoryTemplate freeModeStoryTemplate(FreeModeRun run) => StoryTemplate(
  id: 'free_mode',
  title: run.bible.title,
  pitch: run.bible.premise,
  initialSceneId: 'free_act_1',
  scenes: {
    for (var index = 0; index < 3; index++)
      'free_act_${index + 1}': StoryScene(
        id: 'free_act_${index + 1}',
        title: 'Act ${index + 1}: ${run.bible.locations[index]}',
        description:
            '${run.bible.flavour}\n\nYou arrive at ${run.bible.locations[index]}.',
        choices: const [],
      ),
  },
  routes: const {},
);
