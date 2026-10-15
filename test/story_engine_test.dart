import 'package:chatty_venture/core/story/story_engine.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:flutter_test/flutter_test.dart';

class _InvalidProposalNarrator implements AiDungeonMaster {
  @override
  String get label => 'invalid';

  @override
  void cancel() {}

  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async => 'This is narration, not a valid run bible.';
}

class _FencedProposalNarrator implements AiDungeonMaster {
  @override
  String get label => 'fenced-json';

  @override
  void cancel() {}

  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async => '''```json
{
  "title": "The Quiet Bell",
  "premise": "A silent bell leaves the harbour unguarded.",
  "problem": "The bell rope has vanished.",
  "key_anchor": "a blue knot",
  "supporting_character": "Iris the keeper",
  "stakes": "The tide will catch the town unaware.",
  "escalation": "The storm is moving in.",
  "ending_image": "The bell rings through the dawn.",
  "locations": ["Quay", "Archive", "Bell tower"],
  "objectives": ["Find the missing rope", "Trace it to the archive", "Restore the bell"],
  "flavour": "Rain and salt air."
}
```''';
}

void main() {
  final engine = StoryEngine();

  test('the ledger keeps a discovered fact across scenes', () {
    var state = StoryState.initial();
    state = engine
        .apply(
          state,
          const StoryAction(
            kind: StoryActionKind.choose,
            target: 'speak_keeper',
            playerText: 'Speak',
          ),
        )
        .state;
    state = engine
        .apply(
          state,
          const StoryAction(
            kind: StoryActionKind.choose,
            target: 'follow_lantern',
            playerText: 'Follow',
          ),
        )
        .state;
    state = engine
        .apply(
          state,
          const StoryAction(
            kind: StoryActionKind.choose,
            target: 'read_ledger',
            playerText: 'Read',
          ),
        )
        .state;
    expect(state.sceneId, 'old_archive');
    expect(state.hasFact('missing_name_found'), isTrue);
    expect(state.threads['the_unpaid_debt']!.status, contains('Elian Voss'));
  });

  test('the reducer rejects an ending before its fact is discovered', () {
    final result = engine.apply(
      StoryState.initial(),
      const StoryAction(
        kind: StoryActionKind.choose,
        target: 'ring_bell',
        playerText: 'Ring',
      ),
    );
    expect(result.accepted, isFalse);
    expect(result.state.turn, 0);
    expect(result.events.single.kind, 'blocked');
  });

  test('a story save preserves only canonical ledger truth', () {
    final original = StoryState(
      sceneId: 'old_archive',
      turn: 7,
      facts: const {'missing_name_found'},
      threads: const {
        'debt': StoryThread(id: 'debt', label: 'A debt', status: 'Open'),
      },
      recap: const ['A name was found.'],
    );
    final restored = StorySaveCodec.decode(StorySaveCodec.encode(original));
    expect(restored.sceneId, original.sceneId);
    expect(restored.turn, 7);
    expect(restored.facts, {'missing_name_found'});
    expect(restored.threads['debt']!.status, 'Open');
  });

  test('the GGUF formatter preserves the known-good narrator prompt', () {
    final state = StoryState.initial();
    final prompt = NarratorContext(
      scene: engine.template.scene(state.sceneId),
      events: const [StoryEvent('moved', 'The player enters.')],
      facts: state.facts,
      threads: state.threads,
      recap: state.recap,
      ending: state.ending,
    ).toPrompt();
    expect(
      prompt,
      contains('Your job is to make the CONFIRMED TURN feel immediate'),
    );
    expect(prompt, contains('Never introduce or name an item'));
    expect(prompt, contains('Return narration only'));
    expect(prompt, contains('never quote it, summarize it'));
    expect(prompt, contains('SCENE: Lantern Quay'));
    expect(NarratorContext.isUsableNarration('One two three.'), isFalse);
  });

  test('a DM style note reaches both narration formatters', () {
    final context = NarratorContext(
      scene: engine.template.scene(StoryState.initial().sceneId),
      events: const [StoryEvent('moved', 'The player enters.')],
      facts: const {},
      threads: const {},
      recap: const [],
      ending: null,
    );
    const style = 'Dry, warm, and gently mischievous.';

    expect(context.toCloudInstruction(styleNote: style), contains(style));
    expect(context.toGgufPrompt(styleNote: style), contains(style));
    expect(
      context.toGgufPrompt(styleNote: style),
      contains('Do not change established facts'),
    );
  });

  test(
    'Free Mode selects a complete geometry and freezes editable bible data',
    () {
      final template = FreeModeCatalog.templates.first;
      final bible = FreeModeBible(
        title: 'The Silent Gate',
        premise: 'A gate fails before the river rises.',
        problem: 'The gate mechanism is jammed.',
        keyAnchor: 'a brass key',
        supportingCharacter: 'Nia the keeper',
        stakes: 'The river will flood the town.',
        escalation: 'The water is rising fast.',
        endingImage: 'The gate opens at sunrise.',
        locations: const ['Flooded square', 'Pump house', 'River gate'],
        objectives: const [
          'Find the fault',
          'Reach the pump house',
          'Open the gate',
        ],
        flavour: 'Cold rain and iron bells.',
      );
      final run = FreeModeRun(templateId: template.id, bible: bible);
      expect(bible.isUsable, isTrue);
      expect(FreeModeCatalog.byId(run.templateId).actGoals, hasLength(3));
      expect(run.bible.title, 'The Silent Gate');
    },
  );

  test('Free Mode save preserves frozen details unchanged', () {
    final run = FreeModeRun(
      templateId: 'retrieval',
      bible: FreeModeBible(
        title: 'A Lost Compass',
        premise: 'Find it before dawn.',
        problem: 'A guide is stranded.',
        keyAnchor: 'silver compass',
        supportingCharacter: 'Tomas the guide',
        stakes: 'A guide is stranded.',
        escalation: 'The weather is closing in.',
        endingImage: 'A safe light appears at home.',
        locations: const ['Dock', 'Marsh', 'Watchtower'],
        objectives: const [
          'Learn the route',
          'Recover the compass',
          'Bring it home',
        ],
        flavour: 'Mist and salt.',
      ),
      act: 1,
      completedObjectives: const [0],
      completedSteps: const [2, 0, 0],
      epilogue: 'Years later, the compass still pointed home.',
    );
    final encoded = StorySaveCodec.encode(StoryState.initial(), freeMode: run);
    final restored = StorySaveCodec.decodeFreeMode(encoded)!;
    expect(restored.templateId, 'retrieval');
    expect(restored.bible.locations, run.bible.locations);
    expect(restored.bible.objectives, run.bible.objectives);
    expect(restored.bible.stakes, run.bible.stakes);
    expect(restored.bible.endingImage, run.bible.endingImage);
    expect(restored.act, 1);
    expect(restored.completedSteps, [2, 0, 0]);
    expect(restored.epilogue, 'Years later, the compass still pointed home.');
  });

  test(
    'Free Mode only advances one act after a host-detected player intent',
    () {
      final run = FreeModeRun(
        templateId: 'mystery',
        bible: FreeModeBible(
          title: 'The Missing Bell',
          premise: 'A bell has vanished.',
          problem: 'No one can hear the tide.',
          keyAnchor: 'blue rope',
          supportingCharacter: 'Iris the keeper',
          stakes: 'The tide cannot be heard.',
          escalation: 'The storm grows louder.',
          endingImage: 'The bell rings at dawn.',
          locations: const ['Quay', 'Archive', 'Bell tower'],
          objectives: const [
            'Discover the theft',
            'Trace the culprit',
            'Resolve the theft',
          ],
          flavour: 'Rain and lanterns.',
        ),
      );
      final reducer = FreeModeReducer();
      expect(reducer.apply(run, 'I wait and listen.').run.act, 0);
      final firstBeat = reducer.apply(run, 'I investigate the theft.');
      expect(firstBeat.progressed, isTrue);
      expect(firstBeat.completed, isFalse);
      expect(firstBeat.run.act, 0);
      expect(firstBeat.run.completedStepsForAct(0), 1);

      // One small typo in each useful word is still a valid mobile action.
      final advanced = reducer.apply(firstBeat.run, 'I finde the blue roep.');
      expect(advanced.completed, isTrue);
      expect(advanced.run.act, 1);
      expect(advanced.run.completedObjectives, [0]);
    },
  );

  test('Free Mode ends only after its third host-owned objective', () {
    final template = FreeModeCatalog.byId('escape');
    final bible = FreeModeBible(
      title: 'Locked Below',
      premise: 'Find a way out.',
      problem: 'The vault is sealed.',
      keyAnchor: 'a cracked map',
      supportingCharacter: 'Vale the scout',
      stakes: 'The vault remains sealed.',
      escalation: 'The air is running thin.',
      endingImage: 'The ridge opens to daylight.',
      locations: const ['Cell', 'Shaft', 'Ridge'],
      objectives: const [
        'Understand the trap',
        'Bypass the lock',
        'Reach safety',
      ],
      flavour: 'Dust and wind.',
    );
    var run = FreeModeRun(templateId: template.id, bible: bible);
    run = FreeModeReducer().apply(run, 'I inspect the vault.').run;
    run = FreeModeReducer().apply(run, 'I discover the cracked map.').run;
    run = FreeModeReducer().apply(run, 'I look around.').run;
    run = FreeModeReducer().apply(run, 'I bypass the lock.').run;
    run = FreeModeReducer().apply(run, 'I examine the ridge.').run;
    final finalResult = FreeModeReducer().apply(run, 'I escape into safety.');
    expect(finalResult.ended, isTrue);
    expect(finalResult.run.isComplete, isTrue);
  });

  test('Free Mode accepts a near-miss verb from an Escape objective', () {
    final run = FreeModeRun(
      templateId: 'escape',
      bible: FreeModeBible(
        title: 'Ember Crossing',
        premise: 'A crossing must be saved before nightfall.',
        problem: 'The Lantern Engine has fallen silent.',
        keyAnchor: 'a brass compass',
        supportingCharacter: 'Mara the signal keeper',
        stakes: 'The crossing will flood.',
        escalation: 'The river is breaching the old works.',
        endingImage: 'The river gate opens at dawn.',
        locations: const ['Crossing', 'Old works', 'River gate'],
        objectives: const [
          'establish the trap',
          'overcome the obstruction',
          'reach safety',
        ],
        flavour: 'Warm rain and old brick.',
      ),
      completedSteps: const [1],
    );

    final result = FreeModeReducer().apply(run, 'I establsh the trap.');
    expect(result.completed, isTrue);
    expect(result.run.act, 1);
  });

  test('narrator prose cannot advance a Free Mode act', () {
    final run = FreeModeRun(
      templateId: 'mystery',
      bible: FreeModeBible(
        title: 'The Quiet Case',
        premise: 'Something is wrong.',
        problem: 'A light is out.',
        keyAnchor: 'a matchbook',
        supportingCharacter: 'June the witness',
        stakes: 'The street stays dark.',
        escalation: 'The rain begins to fall.',
        endingImage: 'A lamp returns to the street.',
        locations: const ['Street', 'Basement', 'Roof'],
        objectives: const ['Discover it', 'Trace it', 'Resolve it'],
        flavour: 'Wet pavement.',
      ),
    );
    final result = FreeModeReducer().apply(
      run,
      'The narrator declares that the objective is complete.',
    );
    expect(result.completed, isFalse);
    expect(result.run.act, 0);
  });

  test('cloud and GGUF prompt paths stay distinct', () {
    final state = StoryState.initial();
    final context = NarratorContext(
      scene: engine.template.scene(state.sceneId),
      events: const [StoryEvent('attempted', 'The player waits.')],
      facts: state.facts,
      threads: state.threads,
      recap: state.recap,
      ending: null,
    );
    expect(context.toCloudInstruction(), isNot(contains('SCENE:')));
    expect(context.toGgufPrompt(), contains('SCENE: Lantern Quay'));
  });

  test('a narration packet can carry host-owned action and bridge details', () {
    final state = StoryState.initial();
    final context = NarratorContext(
      scene: engine.template.scene(state.sceneId),
      events: const [StoryEvent('transition', 'Act one is complete.')],
      facts: state.facts,
      threads: state.threads,
      recap: state.recap,
      ending: null,
      canonicalAddendum:
          'PLAYER ACTION: investigate the bell\nHOST-CONFIRMED OUTCOME: clue found\nNEXT FIXED LOCATION: archive',
    );
    expect(context.toCanonicalPacket(), contains('PLAYER ACTION: investigate'));
    expect(
      context.toCanonicalPacket(),
      contains('NEXT FIXED LOCATION: archive'),
    );
  });

  test(
    'an invalid Free Mode proposal fails before a run can be created',
    () async {
      await expectLater(
        FreeModeProposalService().generate(
          _InvalidProposalNarrator(),
          FreeModeCatalog.templates.first,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('a fenced Free Mode proposal is parsed as JSON', () async {
    final bible = await FreeModeProposalService().generate(
      _FencedProposalNarrator(),
      FreeModeCatalog.templates.first,
    );

    expect(bible.title, 'The Quiet Bell');
    expect(bible.locations, ['Quay', 'Archive', 'Bell tower']);
  });

  test('an older Free Mode save keeps its frozen core details', () {
    final legacy = FreeModeRun.fromJson({
      'template_id': 'mystery',
      'bible': {
        'title': 'The Old Signal',
        'premise': 'A signal is missing.',
        'problem': 'The beacon is silent.',
        'key_anchor': 'a copper wire',
        'locations': ['Pier', 'Tower', 'Cliff'],
        'objectives': ['Find it', 'Trace it', 'Fix it'],
        'flavour': 'Salt wind.',
      },
      'act': 1,
      'completed_objectives': [0],
      'history': ['The signal fades.'],
    });
    expect(legacy.bible.title, 'The Old Signal');
    expect(legacy.bible.supportingCharacter, 'No companion was recorded.');
    expect(legacy.act, 1);
  });

  test('the Free Mode afterword is a distinct narrator request', () {
    final context = NarratorContext.freeModeEpilogue(
      'Completed objectives: find, recover, return.\nENDING IMAGE: dawn over the gate.',
    );
    expect(context.scene.title, 'Afterword');
    expect(context.structuredOutput, isFalse);
    expect(context.toCloudInstruction(), contains('afterword paragraph'));
    expect(
      context.toGgufPrompt(),
      contains('ENDING IMAGE: dawn over the gate.'),
    );
  });
}
