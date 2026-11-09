import 'dart:async';

import 'package:chatty_venture/core/narration/narrator_profiles.dart';
import 'package:chatty_venture/core/narration/narrator_prompt_settings.dart';
import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/adventure/adventure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/narration_fixtures.dart';

class _TestSaves extends StorySaveStore {
  @override
  Future<void> save(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) async {}
}

void main() {
  for (final action in ['Save', 'Reset to default', 'Cancel']) {
    testWidgets('$action while a local reply is pending', (tester) async {
      const original = 'Original voice. {{story_packet}}';
      const edited = 'Edited voice. {{story_packet}}';
      SharedPreferences.setMockInitialValues({
        'bundled_smol_disabled': true,
        'gguf_narration_template': original,
      });
      await tester.binding.setSurfaceSize(const Size(600, 960));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const gguf = MethodChannel('chatty_venture/local_gguf');
      const events = MethodChannel('chatty_venture/local_gguf_events');
      final messenger = tester.binding.defaultBinaryMessenger;
      final release = Completer<void>();
      final prompts = <String>[];
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(gguf, (call) async {
        prompts.add(call.arguments['prompt'] as String);
        if (prompts.length == 1) {
          await release.future;
        }
        return {'text': cleanNarration};
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(gguf, null);
        messenger.setMockMethodCallHandler(events, null);
      });
      final game = AdventureController(saves: _TestSaves());
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
      game.setNarrator(LocalGgufDungeonMaster('local', 'test.gguf'));
      late Future<void> first;
      await tester.runAsync(() async {
        first = game.submit('look around');
      });
      await tester.pumpAndSettle();
      expect(prompts.single, startsWith('Original voice.'));
      await tester.tap(find.byTooltip('Choose Dungeon Master'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Narration prompts'));
      await tester.tap(find.text('Narration prompts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Local GGUF prompt'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, edited);
      await tester.tap(find.text(action));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 30);
      await tester.pump();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(game.isNarrating, isTrue);
      await tester.runAsync(() async {
        release.complete();
        await first;
      });
      await tester.pumpAndSettle();
      expect(game.state.turn, 1);
      expect(game.isNarrating, isFalse);
      expect(game.messages.where((m) => !m.isPlayer).map((m) => m.text), [
        cleanNarration,
      ]);
      await tester.runAsync(() => game.submit('listen'));
      await tester.pumpAndSettle();
      final expected = switch (action) {
        'Save' => edited,
        'Reset to default' => NarratorPromptSettings.defaultGgufTemplate,
        _ => original,
      };
      expect(prompts, hasLength(2));
      expect(
        prompts.last,
        startsWith(expected.split('{{story_packet}}').first),
      );
      expect(game.narrationError, isNull);
      await tester.pumpWidget(const SizedBox());
      game.dispose();
    });
  }
}
