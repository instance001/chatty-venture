import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatty_venture/core/narration/narration_guard.dart';
import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:chatty_venture/core/story/story_engine.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/adventure/adventure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/narration_fixtures.dart';

class _Narrator implements AiDungeonMaster {
  _Narrator(this.response);
  String response;
  String? bridgeResponse;
  final contexts = <NarratorContext>[];
  void Function()? duringGeneration;
  Completer<void>? delay;
  @override
  String get label => 'test narrator';
  @override
  void cancel() {}
  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async {
    contexts.add(context);
    // A clean prefix must not be published before a leaking suffix arrives.
    onToken?.call(cleanNarration);
    duringGeneration?.call();
    if (delay != null) await delay!.future;
    onToken?.call(response);
    return context.events.first.kind == 'transition'
        ? bridgeResponse ?? response
        : response;
  }
}

class _MemorySaves extends StorySaveStore {
  FreeModeRun? run;
  PendingNarration? pendingRequest;
  StoryState? savedState;
  @override
  Future<StorySnapshot?> readSnapshot() async => savedState == null
      ? null
      : (state: savedState!, freeMode: run, pending: pendingRequest);
  @override
  Future<StoryState?> load() async => savedState;
  @override
  Future<FreeModeRun?> loadFreeMode() async => run;
  @override
  Future<void> save(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) async {
    pendingRequest = pending;
    savedState = state;
    run = freeMode;
  }

  @override
  Future<void> clear() async {
    run = null;
    savedState = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rejects the device report and individual instruction fragments', () {
    expect(NarrationGuard.isUsable(reportedLeak), isFalse);
    for (final fragment in [
      'You may add only fleeting sensory texture: weather and light.',
      'DO NOT RENAME ANYTHING!',
      'Do not give the player a past.',
      'If a detail is not confirmed, leave it undescribed.',
      'Your job is to keep the player’s objective unresolved.',
      'NARRATION JOB: Respond directly to the player action.',
      'RECENT NARRATION (do not repeat its phrasing): rain.',
      'ACT 2 OBJECTIVE: open the gate.',
      'CONFIRMED TURN: You wait.',
      'DM STYLE NOTE: playful.',
      'KEY ANCHOR: a brass compass.',
      'ENDING IMAGE: a bright doorway.',
      'You continue working toward: a quiet night.',
    ]) {
      expect(
        NarrationGuard.isUsable('$cleanNarration $fragment'),
        isFalse,
        reason: fragment,
      );
    }
  });

  test(
    'JSON narration stays out of chat, saves and restored history',
    () async {
      final wrapped = jsonEncode({'narration': cleanNarration});
      final narrator = _Narrator(wrapped);
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      expect(game.narrationError, contains('JSON'));
      expect(game.messages.last.isPlayer, isTrue);
      expect(saves.run!.history, isEmpty);
      narrator.response = cleanNarration;
      await game.retryNarration();
      expect(game.narrationError, isNull);
      expect(game.state.turn, 1);
      expect(game.messages.last.text, cleanNarration);
      expect(saves.run!.history, [cleanNarration]);
      final restored = FreeModeRun.fromJson({
        ...saves.run!.toJson(),
        'history': [wrapped, cleanNarration],
        'epilogue': wrapped,
      });
      expect(restored.history, [cleanNarration]);
      expect(restored.epilogue, isNull);
      expect(restored.completedSteps, saves.run!.completedSteps);
    },
  );

  test('JSON fences, arrays and partial objects cannot pass as prose', () {
    for (final response in [
      '```json\n$cleanNarration\n```',
      jsonEncode([cleanNarration]),
      '$cleanNarration\n{"choices": ["Stay", "Leave"]}',
      '{"narration": "$cleanNarration',
      jsonEncode(List.filled(32, 1)),
    ]) {
      expect(NarrationGuard.isUsable(response), isFalse, reason: response);
    }
    for (final prose in [
      '"Wait," you whisper. $cleanNarration',
      '[At dusk] $cleanNarration',
      '$cleanNarration A mark on the door reads [1].',
    ]) {
      expect(NarrationGuard.isUsable(prose), isTrue, reason: prose);
    }
  });

  test('matches active custom instructions without comparing canonical prose', () {
    const instruction =
        'Describe each passing moment using exactly two economical paragraphs';
    expect(
      NarrationGuard.isUsable(
        '$cleanNarration DESCRIBE each passing moment, using exactly two economical paragraphs.',
        instructions: [instruction],
      ),
      isFalse,
    );
    expect(NarrationGuard.isUsable(cleanNarration), isTrue);
    expect(
      NarrationGuard.isUsable('$cleanNarration Your job at the quay is over.'),
      isTrue,
    );
    expect(NarrationGuard.isUsable('A bell rings.'), isFalse);
  });

  test(
    'host rejects before display/history/save and retry keeps the same turn',
    () async {
      final narrator = _Narrator(reportedLeak);
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      final initialMessages = game.messages.length;
      narrator.duringGeneration = () {
        expect(game.narratorDraft, isEmpty);
        expect(game.messages.length, initialMessages + 1);
      };
      await game.submit('look around');
      expect(game.narrationError, contains('returned instructions'));
      expect(game.messages.length, initialMessages + 1);
      expect(game.freeModeRun!.history, isEmpty);
      expect(saves.run!.history, isEmpty);
      expect(game.isNarrating, isFalse);
      final committedTurn = game.state.turn;
      narrator.response = cleanNarration;
      await game.retryNarration();
      expect(narrator.contexts.last, same(narrator.contexts.first));
      expect(game.state.turn, committedTurn);
      expect(game.narrationError, isNull);
      expect(game.messages.last.text, cleanNarration);
      expect(saves.run!.history, [cleanNarration]);
    },
  );

  test(
    'Free Mode keeps hints out of turn, bridge and afterword packets and rejects copied steps',
    () async {
      final narrator = _Narrator(cleanNarration)
        ..bridgeResponse = arrivalNarration;
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.templates.first;
      final demo = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      final bible = demo.copyWith(
        endingImage: 'Dawn breaks over the restored observatory.',
        objectives: [
          'Read the inscription and lift the latch',
          'Decipher the cipher',
          'Ring the silver bell',
        ],
      );
      await game.startFreeMode(template, bible);
      narrator.response = '$cleanNarration LIFT—the latch!';
      await game.submit('wait quietly');
      expect(game.narrationError, contains('hidden hint'));
      expect(game.messages.last.isPlayer, isTrue);
      expect(saves.run!.history, isEmpty);
      narrator.response = '$cleanNarration Ring the silver bell.';
      await game.retryNarration();
      expect(game.narrationError, contains('hidden hint'));
      expect(saves.run!.history, isEmpty);
      narrator.response = cleanNarration;
      await game.retryNarration();
      for (final verb in ['find', 'trace', 'resolve']) {
        await game.submit('look around');
        await game.submit('$verb the compass');
      }
      expect(game.narrationError, isNull);
      expect(saves.run!.completedObjectives, [0, 1, 2]);
      expect(saves.run!.epilogue, cleanNarration);
      expect(
        narrator.contexts.where((c) => c.events.first.kind == 'transition'),
        hasLength(2),
      );
      for (final context in narrator.contexts) {
        final packet = context.toCanonicalPacket();
        if (context.scene.id == 'free_mode_afterword') {
          expect(packet, contains('ENDING IMAGE: ${bible.endingImage}'));
        } else {
          expect(packet, isNot(contains('ENDING IMAGE:')));
          expect(packet, isNot(contains(bible.endingImage)));
        }
        for (final hint in bible.hintText) {
          expect(
            context.toCanonicalPacket().toLowerCase(),
            isNot(contains(hint.toLowerCase())),
          );
        }
      }
      final legacy = FreeModeRun.fromJson({
        ...saves.run!.toJson(),
        'history': [cleanNarration, 'Read the inscription.'],
        'epilogue': 'Ring the silver bell.',
      });
      expect(legacy.history, [cleanNarration]);
      expect(legacy.epilogue, isNull);
      expect(legacy.completedObjectives, [0, 1, 2]);
    },
  );

  test(
    'retry resumes the act transition and fallback saves a rejected afterword',
    () async {
      final narrator = _Narrator(cleanNarration)
        ..bridgeResponse = arrivalNarration;
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      narrator.response = reportedLeak;
      await game.submit('find the compass');
      final turn = game.state.turn;
      expect(game.narrationError, isNotNull);
      narrator.response = cleanNarration;
      await game.retryNarration();
      expect(game.state.turn, turn);
      expect(narrator.contexts.last.events.first.kind, 'transition');
      final closing = narrator.contexts[narrator.contexts.length - 2];
      expect(closing.scene.id, 'free_act_1');
      expect(
        closing.toCanonicalPacket(),
        contains('ACT 1 LOCATION: ${bible.locations[0]}'),
      );
      expect(closing.toCanonicalPacket(), isNot(contains('ACT 2 LOCATION:')));
      final bridge = narrator.contexts.last;
      expect(bridge.scene.id, 'free_act_2');
      expect(
        bridge.toCanonicalPacket(),
        contains('ACT 2 LOCATION: ${bible.locations[1]}'),
      );
      expect(saves.run!.history, hasLength(3));
      await game.submit('look around');
      await game.submit('trace the compass');
      await game.submit('look around');
      narrator.duringGeneration = () {
        if (narrator.contexts.last.scene.id == 'free_mode_afterword') {
          narrator.response = reportedLeak;
        }
      };
      await game.submit('resolve the compass');
      expect(game.narrationError, isNotNull);
      expect(saves.run!.epilogue, isNull);
      final beforeFallback = saves.run!.history.length;
      game.setFallbackNarrator(DemoDungeonMaster());
      await game.useFallbackNarration();
      expect(game.narrationError, isNull);
      expect(saves.run!.history, hasLength(beforeFallback + 1));
      expect(saves.run!.epilogue, game.messages.last.text);
      expect(game.state.turn, 6);
      await game.restart();
      expect(saves.run!.epilogue, isNull);
    },
  );

  test(
    'cold retries resume the saved action, closing or arrival exactly once',
    () async {
      final dir = await Directory.systemTemp.createTemp('venture-turn-retry');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/active_story.json');
      final saves = StorySaveStore(file: file);
      final narrator = _Narrator(cleanNarration)
        ..bridgeResponse = arrivalNarration;
      final game = AdventureController(saves: saves, narrator: narrator);
      addTearDown(game.dispose);
      // Capture the actual on-disk checkpoint while each request is in flight.
      final checkpoints = <({String save, String packet, String stage})>[];
      narrator.duringGeneration = () {
        final ctx = narrator.contexts.last;
        checkpoints.add((
          save: file.readAsStringSync(),
          packet: ctx.toCanonicalPacket(),
          stage: ctx.events.first.kind,
        ));
      };
      await game.startAdventure(
        AdventureCatalog.defaultAdventure,
        role: 'observer',
        tone: 'quiet',
      );
      await game.choose(game.scene.choices.first);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      await game.submit('find the compass');
      expect(checkpoints.map((c) => c.stage).toList().sublist(1), [
        'attempted',
        'objective_completed',
        'transition',
      ]);

      for (final checkpoint in checkpoints) {
        await file.writeAsString(checkpoint.save);
        final before = (await saves.readSnapshot())!;
        final lane = _Narrator(cleanNarration)
          ..bridgeResponse = arrivalNarration;
        final restored = AdventureController(saves: saves, narrator: lane);
        addTearDown(restored.dispose);
        await restored.begin();
        expect(lane.contexts, isEmpty);
        expect(restored.narrationError, contains('turn was saved'));
        await Future.wait([
          restored.retryNarration(),
          restored.retryNarration(),
        ]);
        expect(lane.contexts.first.toCanonicalPacket(), checkpoint.packet);
        expect(
          lane.contexts.length,
          checkpoint.stage == 'objective_completed' ? 2 : 1,
        );
        expect(restored.narrationError, isNull);
        final after = (await saves.readSnapshot())!;
        expect(
          StorySaveCodec.encode(after.state),
          StorySaveCodec.encode(before.state),
        );
        expect(after.freeMode?.completedSteps, before.freeMode?.completedSteps);
        if (after.freeMode != null) {
          expect(
            after.freeMode!.history.length,
            before.freeMode!.history.length + lane.contexts.length,
          );
        }
        expect(after.pending, isNull);
        final reopened = AdventureController(saves: saves, narrator: lane);
        addTearDown(reopened.dispose);
        await reopened.begin();
        expect(reopened.narrationError, isNull);
      }
    },
  );

  test('a cold restart offers only the missing afterword for retry', () async {
    final template = FreeModeCatalog.templates.first;
    final bible = await FreeModeProposalService().generate(
      DemoDungeonMaster(),
      template,
    );
    final narrator = _Narrator(cleanNarration)
      ..bridgeResponse = arrivalNarration;
    final saves = _MemorySaves();
    final game = AdventureController(saves: saves, narrator: narrator);
    addTearDown(game.dispose);
    await game.startFreeMode(template, bible);
    narrator.duringGeneration = () {
      if (narrator.contexts.last.scene.id == 'free_mode_afterword') {
        narrator.response = reportedLeak;
      }
    };
    for (final verb in ['find', 'trace', 'resolve']) {
      await game.submit('look around');
      await game.submit('$verb the compass');
    }
    expect(game.narrationError, isNotNull);
    expect(saves.run!.epilogue, isNull);
    final ledger = StorySaveCodec.encode(game.state);
    final history = List.of(saves.run!.history);

    Future<AdventureController> reopen(_Narrator lane) async {
      final snapshot = StorySaveCodec.encode(
        saves.savedState!,
        freeMode: saves.run,
      );
      saves.savedState = StorySaveCodec.decode(snapshot);
      saves.run = StorySaveCodec.decodeFreeMode(snapshot);
      final restored = AdventureController(saves: saves, narrator: lane);
      addTearDown(restored.dispose);
      await restored.begin();
      return restored;
    }

    final lane = _Narrator(cleanNarration);
    final restored = await reopen(lane);
    expect(restored.narrationError, contains('afterword'));
    expect(lane.contexts, isEmpty);
    await Future.wait([restored.retryNarration(), restored.retryNarration()]);
    expect(
      lane.contexts.single.toCanonicalPacket(),
      contains('ENDING IMAGE: ${bible.endingImage}'),
    );
    expect(
      lane.contexts.single.toCanonicalPacket(),
      narrator.contexts.last.toCanonicalPacket(),
    );
    expect(restored.narrationError, isNull);
    expect(saves.run!.history, [...history, cleanNarration]);
    expect(saves.run!.epilogue, cleanNarration);
    expect(saves.run!.completedObjectives, [0, 1, 2]);
    expect(StorySaveCodec.encode(restored.state), ledger);

    final complete = await reopen(lane);
    expect(complete.narrationError, isNull);
    await complete.retryNarration();
    expect(lane.contexts, hasLength(1));
    expect(complete.freeModeRun!.epilogue, cleanNarration);
  });

  testWidgets('the restored ending offers a fallback if retry fails', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'selected_adventure': 'free_mode',
      'selected_narrator_fallback': 'demo',
      'bundled_smol_disabled': true,
    });
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = FreeModeCatalog.templates.first;
    final bible = await FreeModeProposalService().generate(
      DemoDungeonMaster(),
      template,
    );
    final saves = _MemorySaves()
      ..savedState = StoryState.initial().copyWith(
        sceneId: 'free_act_3',
        turn: 6,
        ending: 'The bell rings.',
      )
      ..run = FreeModeRun(
        templateId: template.id,
        bible: bible,
        act: 3,
        completedObjectives: [0, 1, 2],
        history: [cleanNarration],
      );
    final game = AdventureController(saves: saves);
    await game.begin();
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureScreen(
          controller: game,
          darkMode: false,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    game.setNarrator(_Narrator(reportedLeak));
    await tester.tap(find.text('Retry original'));
    await tester.pumpAndSettle();
    expect(saves.run!.history, [cleanNarration]);
    expect(game.narrationError, contains('returned instructions'));
    await tester.tap(find.text('Use Storyteller demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('AFTERWORD'), findsOneWidget);
    expect(find.text('Retry original'), findsNothing);
    final restart = find.text('Begin this adventure again');
    await tester.ensureVisible(restart);
    await tester.pumpAndSettle();
    expect(restart.hitTestable(), findsOneWidget);
    expect(saves.run!.history, [cleanNarration, saves.run!.epilogue!]);
    expect(game.state.turn, 6);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    game.dispose();
  });

  test(
    'Forest bridge allows ordinary verbs while protecting the rescue objective',
    () async {
      final narrator = _Narrator(cleanNarration);
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.byId('escape');
      final base = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      const rescue = 'rescue the local who has been watching you all along';
      const arrival = 'You find yourself beneath the trees. $arrivalNarration';
      final bible = base.copyWith(
        locations: ['The Ruin', 'The Forest', 'The Forbidden Valley'],
        objectives: [
          'Find and escape the hidden entrance to the ruin',
          'Find and $rescue',
          "Get out of the forest before nightfall and avoid the trap that's closing in around you",
        ],
      );
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      narrator.bridgeResponse = '$cleanNarration You must $rescue.';
      await game.submit('use the compass');
      expect(game.narrationError, contains('hidden hint'));
      final history = List.of(saves.run!.history);
      narrator.bridgeResponse = arrival;
      await game.retryNarration();
      expect(game.narrationError, isNull);
      expect(saves.run!.history, [...history, arrival]);
      expect(game.state.turn, 2);
      final run = FreeModeRun.fromJson(saves.run!.toJson());
      expect(run.history.last, arrival);
      expect(freeModeActSteps(run, 1), [
        'Survey The Forest and assess the situation',
        'Find and $rescue',
      ]);
      expect(
        freeModeActSteps(run, 2).first,
        'Get out of the forest before nightfall',
      );
    },
  );

  test(
    'a Ruin closing cannot send the player back to find the entrance',
    () async {
      final narrator = _Narrator(cleanNarration)
        ..bridgeResponse = arrivalNarration;
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.byId('escape');
      final base = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      const goal = 'Find and escape the hidden entrance to the ruin';
      await game.startFreeMode(
        template,
        base.copyWith(
          locations: ['The Ruin', 'The Forest', 'The Forbidden Valley'],
          objectives: [goal, 'Rescue the local', 'Reach safety'],
        ),
      );
      await game.submit('look around');
      narrator.response = ruinClosing;
      await game.submit('use the map to find the ruin entrance');
      expect(game.narrationError, contains('reopened'));
      expect(game.messages.last.isPlayer, isTrue);
      expect(saves.run!.history, [cleanNarration]);
      expect(saves.run!.completedObjectives, [0]);
      final closing = narrator.contexts.last;
      expect(closing.events.first.kind, 'objective_completed');
      expect(closing.toCanonicalPacket(), isNot(contains(goal)));
      expect(
        closing.toCanonicalPacket(),
        isNot(contains('Keep the objective unresolved')),
      );
      const lookBack =
          'You glance back at the entrance you just found. $cleanNarration';
      narrator.response = lookBack;
      await game.retryNarration();
      expect(game.narrationError, isNull);
      expect(narrator.contexts[narrator.contexts.length - 2], same(closing));
      expect(saves.run!.history, [cleanNarration, lookBack, arrivalNarration]);
      expect(game.state.turn, 2);
    },
  );

  test(
    'a closing distinguishes pending instructions from reflection and new tasks',
    () {
      const goal = 'Find and escape the hidden entrance to the ruin';
      for (final direction in [
        'Find the hidden entrance to the ruin!',
        'Where is the local? You still need to find the hidden entrance.',
        'But it’s time to escape the hidden entrance to the ruin again.',
      ]) {
        expect(
          NarrationGuard.reopensCompletedObjective(direction, goal),
          isTrue,
          reason: direction,
        );
      }
      for (final prose in [
        'You glance back at the entrance you just found.',
        'You remember when you still had to find the hidden entrance to the ruin.',
        'You no longer need to find the hidden entrance to the ruin.',
        'You still need to find shelter near the hidden entrance to the ruin.',
        'You must seal the hidden entrance to the ruin.',
        'Is it time to find the hidden entrance to the ruin?',
      ]) {
        expect(
          NarrationGuard.reopensCompletedObjective(prose, goal),
          isFalse,
          reason: prose,
        );
      }
      expect(
        NarrationGuard.reopensCompletedObjective(
          'You have yet to repair the compass.',
          'Repair the compass and open the gate',
        ),
        isTrue,
      );
    },
  );

  test('Forest arrival cannot turn the known map into a gift', () async {
    final narrator = _Narrator(cleanNarration)..bridgeResponse = forestHandoff;
    final saves = _MemorySaves();
    final game = AdventureController(narrator: narrator, saves: saves);
    addTearDown(game.dispose);
    final template = FreeModeCatalog.byId('escape');
    final base = await FreeModeProposalService().generate(
      DemoDungeonMaster(),
      template,
    );
    await game.startFreeMode(
      template,
      base.copyWith(
        locations: ['The Ruin', 'The Forest', 'The Forbidden Valley'],
        objectives: [
          'Find the ruin entrance',
          'Rescue the local',
          'Reach safety',
        ],
        keyAnchor:
            "You stumble upon an old map that supposedly leads to the ruin's entrance.",
        supportingCharacter: 'A local who knows the forest well',
      ),
    );
    await game.submit('look around');
    await game.submit('use the map to find the ruin entrance');
    expect(game.narrationError, contains('item handoff'));
    expect(
      game.messages.any((message) => message.text == forestHandoff),
      isFalse,
    );
    expect(saves.run!.history, [cleanNarration, cleanNarration]);
    final bridge = narrator.contexts.last;
    const observation = 'The local glances at the map. $arrivalNarration';
    narrator.bridgeResponse = observation;
    await game.retryNarration();
    expect(narrator.contexts.last, same(bridge));
    expect(game.narrationError, isNull);
    expect(saves.run!.history, [cleanNarration, cleanNarration, observation]);
    expect(game.state.turn, 2);
  });

  test(
    'arrival handoffs need a confirmed exchange with the same giver and item',
    () {
      bool rejected(
        String text, [
        String event = 'You arrive at the forest.',
      ]) => NarrationGuard.hasUnconfirmedArrivalHandoff(
        text,
        confirmedEvents: [event],
      );
      const gift = 'The local hands you the map.';
      expect(rejected(gift), isTrue);
      expect(rejected(gift, 'The local gave you a map.'), isFalse);
      expect(rejected('The local passes the map to you.', gift), isFalse);
      expect(rejected(gift, 'The local gave you a compass.'), isTrue);
      expect(rejected(gift, 'The keeper gave you a map.'), isTrue);
      expect(rejected(gift, 'You ask the local for the map.'), isTrue);
      expect(rejected(gift, 'The local never hands you the map.'), isTrue);
      expect(rejected('$gift The local passes you a key.', gift), isTrue);
      for (final harmless in [
        'The local glances at the map.',
        'The local gives you a wary glance.',
        'The local never hands you the map.',
        'If the local hands you the map, you might find a way home.',
        'Who hands you the map?',
      ]) {
        expect(rejected(harmless), isFalse, reason: harmless);
      }
    },
  );

  test(
    'a copied bridge stays out of the transcript and retry resumes only the bridge',
    () async {
      final narrator = _Narrator(cleanNarration);
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      narrator.response = repeatedArtifactNarration;
      await game.submit('find the compass');
      expect(game.narrationError, contains('repeated'));
      final accepted = List.of(saves.run!.history);
      final count = game.messages.length;
      expect(accepted, [cleanNarration, repeatedArtifactNarration]);
      final bridge = narrator.contexts.last;
      expect(
        bridge.toCanonicalPacket(),
        isNot(contains(repeatedArtifactNarration)),
      );
      narrator.bridgeResponse =
          'Rain falls. ${repeatedArtifactNarration.toUpperCase()}';
      await game.retryNarration();
      expect(game.narrationError, contains('repeated'));
      expect(saves.run!.history, accepted);
      expect(game.messages, hasLength(count));
      narrator.bridgeResponse = arrivalNarration;
      await game.retryNarration();
      expect(narrator.contexts.last, same(bridge));
      expect(game.narrationError, isNull);
      expect(saves.run!.history, [...accepted, arrivalNarration]);
      expect(game.state.turn, 2);
      expect(game.freeModeRun!.act, 1);
      game.dispose();
    },
  );

  test(
    'guided turn zero restores the chosen setting including older missing saves',
    () async {
      final saves = _MemorySaves();
      final game = AdventureController(saves: saves);
      final train = AdventureCatalog.adventures[1];
      await game.startAdventure(train, role: 'conductor', tone: 'quiet');
      final restored = AdventureController(saves: saves);
      await restored.begin();
      expect(restored.scene.id, train.initialSceneId);
      expect(restored.state.turn, 0);
      expect(restored.state.facts, contains('Your role: conductor'));
      await saves.clear();
      final legacy = AdventureController(saves: saves);
      await legacy.begin();
      expect(legacy.scene.id, train.initialSceneId);
      expect(legacy.messages.single.text, contains(legacy.scene.title));
    },
  );

  test(
    'a late reply cannot enter a replacement adventure or release its composer',
    () async {
      final first = _Narrator(cleanNarration)..delay = Completer<void>();
      final started = Completer<void>();
      first.duringGeneration = started.complete;
      final saves = _MemorySaves();
      final game = AdventureController(narrator: first, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      await game.startFreeMode(template, bible);
      final oldTurn = game.submit('look around');
      await started.future;
      await game.startFreeMode(
        template,
        bible.copyWith(title: 'Second crossing'),
      );
      final second = _Narrator(cleanNarration)..delay = Completer<void>();
      final secondStarted = Completer<void>();
      second.duringGeneration = secondStarted.complete;
      game.setNarrator(second);
      final newTurn = game.submit('wait here');
      await secondStarted.future;
      first.delay!.complete();
      await oldTurn;
      expect(game.isNarrating, isTrue);
      expect(saves.run!.history, isEmpty);
      expect(game.messages, hasLength(2));
      second.delay!.complete();
      await newTurn;
      expect(saves.run!.history, [cleanNarration]);
    },
  );

  test(
    'explicit demo fallback admits short host prose after rejection',
    () async {
      final game = AdventureController(
        narrator: _Narrator(reportedLeak),
        saves: _MemorySaves(),
      );
      addTearDown(game.dispose);
      game.setFallbackNarrator(DemoDungeonMaster());
      await game.submit('look around');
      expect(game.narrationError, isNotNull);
      await game.useFallbackNarration();
      expect(game.narrationError, isNull);
      expect(game.fallbackNotice, isNotNull);
      expect(game.messages.last.text, isNot(contains('Your job is to')));
    },
  );

  test(
    'solo turns allow witnesses but reject a travelling party before saving',
    () async {
      final narrator = _Narrator(
        '$cleanNarration Your companions follow you to the gate.',
      );
      final saves = _MemorySaves();
      final game = AdventureController(narrator: narrator, saves: saves);
      addTearDown(game.dispose);
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      final partyEdit = bible.copyWith(
        premise: 'You and your companions explore the marsh.',
      );
      await expectLater(
        game.startFreeMode(template, partyEdit),
        throwsStateError,
      );
      expect(game.freeModeRun, isNull);
      final oldSave = FreeModeRun(
        templateId: template.id,
        bible: partyEdit,
      ).toJson();
      expect(FreeModeRun.fromJson(oldSave).bible.premise, partyEdit.premise);
      await game.startFreeMode(template, bible);
      await game.submit('look around');
      expect(game.narrationError, contains('solo adventure'));
      expect(saves.run!.history, isEmpty);
      for (final phrase in [
        'You travel with three companions to Ember Crossing.',
        'Two companions journey alongside you to the tower.',
      ]) {
        narrator.response = '$cleanNarration $phrase';
        await game.retryNarration();
        expect(game.narrationError, contains('solo adventure'));
        expect(saves.run!.history, isEmpty);
      }
      narrator.response =
          '$cleanNarration Three companions wait by the crossing. You ask them about the road.';
      await game.retryNarration();
      expect(game.narrationError, isNull);
      expect(saves.run!.history, [narrator.response]);
    },
  );
}
