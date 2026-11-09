import 'dart:convert';
import 'dart:io';

import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:chatty_venture/core/story/story_engine.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/title/title_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TitleSaves extends StorySaveStore {
  String source = '{';
  @override
  Future<StorySnapshot?> readSnapshot() async =>
      StorySaveCodec.decodeSnapshot(source);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'startup leaves an unreadable file intact and a new adventure can replace it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'venture-save-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/active_story.json');
      final saves = StorySaveStore(file: file);
      expect(await saves.readSnapshot(), isNull);
      for (final bytes in [
        utf8.encode(
          '{"save_version":1,"state":{"turn":{},"scene_id":"old_archive"}}',
        ),
        utf8.encode('{"save_version":1,'),
        utf8.encode('{"save_version":7,"state":{}}'),
        [0xff, 0xfe],
      ]) {
        await file.writeAsBytes(bytes);
        final game = AdventureController(saves: saves);
        await game.begin();
        expect(game.state.turn, 0);
        expect(await saves.load(), isNull);
        expect(await saves.loadFreeMode(), isNull);
        expect(await file.readAsBytes(), bytes);
        game.dispose();
      }
      final game = AdventureController(saves: saves);
      addTearDown(game.dispose);
      await game.startAdventure(
        AdventureCatalog.adventures[1],
        role: 'guard',
        tone: 'quiet',
      );
      expect((await saves.readSnapshot())!.state.sceneId, 'platform_zero');
    },
  );

  test(
    'damaged optional fields keep valid story facts, threads and act slots',
    () async {
      final template = FreeModeCatalog.templates.first;
      final bible = await FreeModeProposalService().generate(
        DemoDungeonMaster(),
        template,
      );
      final run = FreeModeRun(templateId: template.id, bible: bible, act: 1);
      final root = {
        'save_version': 1,
        'state': {
          'scene_id': 'free_act_2',
          'turn': '4',
          'facts': ['kept', null],
          'recap': false,
          'threads': [
            {'id': 1, 'label': 'broken', 'status': 'open'},
            {'id': 'bell', 'label': 'Bell', 'status': 'open'},
          ],
        },
        'free_mode': {
          ...run.toJson(),
          'act': '1',
          'completed_steps': [null, '1'],
          'completed_objectives': [-1, '0', 9],
          'epilogue': [],
          'history': {},
        },
      };
      final snapshot = StorySaveCodec.decodeSnapshot(jsonEncode(root));
      expect(snapshot.state.turn, 4);
      expect(snapshot.state.facts, {'kept'});
      expect(snapshot.state.threads.keys, ['bell']);
      expect(snapshot.state.recap, isEmpty);
      expect(snapshot.freeMode!.completedSteps, [0, 1]);
      expect(snapshot.freeMode!.completedObjectives, [0]);
      expect(snapshot.freeMode!.history, isEmpty);
      expect(snapshot.freeMode!.epilogue, isNull);

      for (final damage in [
        {'act': -1},
        {'act': 4},
        {'act': 0},
        {'act': 'bad'},
        {
          'bible': {...bible.toJson(), 'locations': 'bad'},
        },
        {
          'bible': {
            ...bible.toJson(),
            'objectives': ['first', null, 'last'],
          },
        },
      ]) {
        final damaged = {
          ...root,
          'free_mode': {...run.toJson(), ...damage},
        };
        expect(
          () => StorySaveCodec.decodeSnapshot(jsonEncode(damaged)),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'unreadable save offers a fresh adventure then refreshes Continue',
    (tester) async {
      final saves = _TitleSaves();
      final game = AdventureController(saves: saves);
      addTearDown(game.dispose);
      await game.begin();
      await tester.pumpWidget(
        MaterialApp(
          home: TitleScreen(
            controller: game,
            darkMode: false,
            onToggleTheme: () {},
            onContinue: () async {},
            onFreeMode: () async {},
            onAdventure: (story) async {
              saves.source = StorySaveCodec.encode(
                StoryState.initial().copyWith(sceneId: story.initialSceneId),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be read'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      final choice = find.text(AdventureCatalog.adventures.first.title);
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        (await saves.readSnapshot())!.state.sceneId,
        AdventureCatalog.adventures.first.initialSceneId,
      );
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not be read'), findsNothing);
      expect(find.text('Continue'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
