import 'dart:convert';
import 'dart:math';

import '../narration/narrator.dart';
import '../narration/narration_guard.dart';
import 'solo_adventure.dart';
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

  static final _placeholder = RegExp(
    r'\{\{|\}\}|\$\{[^}]+\}|'
    r'[\[{<]\s*(?:insert\s+[^\]}>]+|(?:act[ _]\d+[ _])?'
    r'(?:location|objective|title|name|item|character|premise|problem|stakes|'
    r'flavour|escalation|key[ _]anchor|supporting[ _]character|ending[ _]image)'
    r'(?:[ _]name)?)\s*[\]}>]',
    caseSensitive: false,
  );
  static final _machineId = RegExp(
    r'\b(?:[a-z][a-z0-9]*_)*id_[a-z0-9_]+\b|'
    r'\b(?:[a-z][a-z0-9]*_){2,}\d+\b|'
    r'\b[a-z][a-z0-9_]*_\d{8,}\b|'
    r'\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b',
    caseSensitive: false,
  );

  // Applied before preview and when edits are accepted. Frozen saves retain
  // their original story details on resume.
  String? get setupError {
    for (final field in storyFields) {
      if (_placeholder.hasMatch(field) || _machineId.hasMatch(field)) {
        return 'An adventure detail contains a placeholder or generated ID.';
      }
    }
    if (!premise.trimLeft().toLowerCase().startsWith('you ')) {
      return 'Start the premise with “You” and describe one adventurer.';
    }
    if (storyFields.any(SoloAdventure.assignsParty)) {
      return 'Give the adventure and its objectives to one adventurer.';
    }
    return null;
  }

  Iterable<String> get storyFields => [
    ...toJson().values.whereType<String>(),
    ...locations,
    ...objectives,
  ];

  Iterable<String> get hintText sync* {
    for (var act = 0; act < objectives.length; act++) {
      final objective = objectives[act];
      final clauses = _objectiveClauses(objective);
      yield objective;
      // "Find and rescue the local..." has a shared target. The rescue clause
      // still gives away the task even when the narrator omits "Find and".
      yield* clauses;
      if (clauses.length < 2) yield _surveyStep(locations[act]);
    }
  }

  factory FreeModeBible.fromJson(Map source) {
    String read(String key) =>
        source[key] is String ? (source[key] as String).trim() : '';
    List<String> list(String key) => switch (source[key]) {
      List values => [
        for (final value in values) value is String ? value.trim() : '',
      ],
      _ => [],
    };
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
    final details = FreeModeBible.fromJson(bible);
    final id = source['template_id'];
    final act = savedCounter(source['act'] ?? 0);
    if (!details.isUsable ||
        id is! String ||
        id.trim().isEmpty ||
        act == null ||
        act < 0 ||
        act > details.locations.length) {
      throw const FormatException('Invalid Free Mode run.');
    }
    // Earlier versions could admit model formatting or hidden instructions.
    bool canDisplay(String text) =>
        !NarrationGuard.containsJsonOutput(text) &&
        !NarrationGuard.repeatsHint(text, details.hintText) &&
        !NarrationGuard.containsInstructionLeak(text);
    final afterword = source['epilogue'];
    List entries(String key) =>
        source[key] is List ? source[key] as List : const [];
    return FreeModeRun(
      templateId: id,
      bible: details,
      act: act,
      completedObjectives: entries('completed_objectives')
          .map(savedCounter)
          .whereType<int>()
          .where((index) => index >= 0 && index < act)
          .toSet()
          .toList(),
      // Each slot belongs to one act. Dropping a bad slot would move later progress.
      completedSteps: [
        for (final count in entries(
          'completed_steps',
        ).take(details.locations.length))
          (savedCounter(count) ?? 0).clamp(0, 2),
      ],
      history: entries(
        'history',
      ).whereType<String>().where(canDisplay).toList(),
      epilogue:
          afterword is String &&
              afterword.trim().isNotEmpty &&
              canDisplay(afterword)
          ? afterword
          : null,
    );
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
    final targets = _relevantTerms(run, run.act);
    // An objective often includes its own action verb. Require a separate
    // target word so "discover" cannot satisfy both halves of the action.
    final verbs = words
        .where((word) => completionWords.any((verb) => _isNear(word, verb)))
        .toSet();
    return verbs.isNotEmpty && _containsNear(words.difference(verbs), targets);
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
  final objective = run.bible.objectives[act];
  final clauses = _objectiveClauses(objective);
  if (clauses.length == 2) return clauses;
  return [_surveyStep(run.bible.locations[act]), objective];
}

// Keep temporal details such as "before nightfall" with their action.
final _stepSeparator = RegExp(
  r'\s+(?:and\s+then|then|and)\s+',
  caseSensitive: false,
);
final _storyWord = RegExp(r'[\p{L}\p{N}]+', unicode: true);
List<String> _objectiveClauses(String text) {
  final separator = _stepSeparator.firstMatch(text);
  if (separator == null) return const [];
  return [
    text.substring(0, separator.start).trim(),
    text.substring(separator.end).trim(),
  ].where((part) => _storyWord.allMatches(part).skip(1).isNotEmpty).toList();
}

String _surveyStep(String location) =>
    'Survey $location and assess the situation';

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
    if (bible.storyFields.any(
      (field) => NarrationGuard.containsInstructionLeak(
        field,
        instructions: [context.cloudInstructionOverride!],
      ),
    )) {
      throw const FormatException(
        'The generated adventure repeated instructions. Please retry.',
      );
    }
    if (bible.setupError case final error?) throw FormatException(error);
    return bible;
  }

  FreeModeBible _parse(String source) {
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(source)?.group(1);
    final Object? decoded;
    try {
      decoded = jsonDecode(fenced ?? source);
    } on FormatException {
      throw const FormatException(
        'The narrator did not return valid adventure JSON. Please retry.',
      );
    }
    if (decoded is! Map) {
      throw const FormatException('Generated adventure was not an object.');
    }
    // Save migration may fill old optional fields, but a new proposal must
    // actually supply them. Never turn malformed model output into saved canon.
    for (final key in const [
      'title',
      'premise',
      'problem',
      'key_anchor',
      'supporting_character',
      'stakes',
      'escalation',
      'ending_image',
      'flavour',
    ]) {
      if (decoded[key] is! String) {
        throw FormatException('Generated adventure is missing text for $key.');
      }
    }
    for (final key in const ['locations', 'objectives']) {
      final values = decoded[key];
      if (values is! List ||
          values.length != 3 ||
          values.any((value) => value is! String)) {
        throw FormatException('Generated adventure needs exactly three $key.');
      }
    }
    return FreeModeBible.fromJson(decoded);
  }

  FreeModeBible _demo(FreeModeTemplate template) => FreeModeBible(
    title: '${template.label} at Ember Crossing',
    premise: 'You reach Ember Crossing just as its last lantern goes dark.',
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
