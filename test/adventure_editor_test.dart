import 'package:chatty_venture/core/narration/cloud_narrator.dart';
import 'package:chatty_venture/core/narration/narrator_style_settings.dart';
import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/adventure/adventure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSaves extends StorySaveStore {
  @override
  Future<void> save(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) async {}
}

Future<AdventureController> _openScreen(
  WidgetTester tester, {
  bool freeMode = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(600, 960));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final game = AdventureController(saves: _TestSaves());
  await tester.pumpWidget(
    MaterialApp(
      home: AdventureScreen(
        controller: game,
        darkMode: false,
        onToggleTheme: () {},
        startFreeMode: freeMode,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return game;
}

Future<void> _closeWhileKeyboardHides(
  WidgetTester tester,
  String action,
) async {
  await tester.tap(find.text(action));
  await tester.pump();
  tester.view.viewInsets = const FakeViewPadding(bottom: 30);
  await tester.pump();
  tester.view.resetViewInsets();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Finder get _dialogFields => find.descendant(
  of: find.byType(AlertDialog).last,
  matching: find.byType(TextField),
);

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'bundled_smol_disabled': true,
      'narrator_style_note': 'Original voice',
    }),
  );

  for (final action in ['Save', 'Clear', 'Cancel']) {
    testWidgets('Style editor: $action while the keyboard hides', (
      tester,
    ) async {
      await _openScreen(tester);
      await tester.tap(find.byTooltip('Choose Dungeon Master'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Dungeon Master style'));
      await tester.tap(find.text('Dungeon Master style'));
      await tester.pumpAndSettle();
      await tester.enterText(_dialogFields, 'Weathered');
      await _closeWhileKeyboardHides(tester, action);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await NarratorStyleSettings().load(), switch (action) {
        'Save' => 'Weathered',
        'Clear' => '',
        _ => 'Original voice',
      });
    });
  }

  for (final save in [true, false]) {
    testWidgets('Adventure editor: save=$save while the keyboard hides', (
      tester,
    ) async {
      final game = await _openScreen(tester, freeMode: true);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final originalTitle = tester
          .widget<TextField>(_dialogFields.first)
          .controller!
          .text;
      final hint = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Hint'),
      );
      await tester.ensureVisible(hint);
      await tester.tap(hint);
      await tester.pumpAndSettle();
      final originalObjective = tester
          .widget<TextField>(_dialogFields.first)
          .controller!
          .text;
      await tester.enterText(_dialogFields.first, 'Recover the moonstone');
      await _closeWhileKeyboardHides(tester, 'Done');
      expect(find.text('Recover the moonstone'), findsNothing);
      await tester.ensureVisible(_dialogFields.first);
      await tester.enterText(_dialogFields.first, 'Moonstone Crossing');
      await _closeWhileKeyboardHides(
        tester,
        save ? 'Use these details' : 'Cancel',
      );
      expect(find.text('Generated adventure'), findsOneWidget);
      await tester.tap(find.text('Proceed'));
      await tester.pumpAndSettle();
      expect(
        game.freeModeRun!.bible.title,
        save ? 'Moonstone Crossing' : originalTitle,
      );
      expect(
        game.freeModeRun!.bible.objectives.first,
        save ? 'Recover the moonstone' : originalObjective,
      );
    });

    testWidgets('Cloud editor: save=$save while the keyboard hides', (
      tester,
    ) async {
      const channel = MethodChannel('chatty_venture/cloud_keys');
      final messenger = tester.binding.defaultBinaryMessenger;
      final writes = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'has') return false;
        writes.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _openScreen(tester);
      final original = await CloudNarratorConfig.load();
      await tester.tap(find.byTooltip('Choose Dungeon Master'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cloud provider'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Gemini').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(_dialogFields.at(0)).controller!.text,
        cloudProviderDefaults('gemini').baseUrl,
      );
      expect(
        tester.widget<TextField>(_dialogFields.at(1)).controller!.text,
        cloudProviderDefaults('gemini').model,
      );
      await tester.enterText(_dialogFields.at(0), 'https://example.test/v1');
      await tester.enterText(_dialogFields.at(1), 'custom-model');
      await tester.enterText(_dialogFields.at(2), 'test-key');
      await _closeWhileKeyboardHides(tester, save ? 'Save and use' : 'Cancel');
      final stored = await CloudNarratorConfig.load();
      expect(stored.provider, save ? 'gemini' : original.provider);
      expect(
        stored.baseUrl,
        save ? 'https://example.test/v1' : original.baseUrl,
      );
      expect(stored.model, save ? 'custom-model' : original.model);
      expect(writes.map((call) => call.method), save ? ['save'] : isEmpty);
      if (save) {
        expect(writes.single.arguments, {
          'providerId': 'gemini',
          'apiKey': 'test-key',
        });
      }
    });
  }
}
