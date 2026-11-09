import 'package:chatty_venture/core/storage/story_save_store.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:chatty_venture/core/story/story_models.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/adventure/adventure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestSaves extends StorySaveStore {
  @override
  Future<void> clear() async {}
  @override
  Future<void> save(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) async {}
}

void main() {
  testWidgets('Free Mode reveals objective text only while Hint is open', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bundled_smol_disabled': true});
    final game = AdventureController(saves: _TestSaves());
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureScreen(
          controller: game,
          darkMode: false,
          onToggleTheme: () {},
          startFreeMode: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Generated adventure'), findsOneWidget);
    for (final goal in FreeModeCatalog.templates.expand((t) => t.actGoals)) {
      expect(find.textContaining(goal), findsNothing);
    }
    await tester.tap(find.text('Proceed'));
    await tester.pumpAndSettle();
    final run = game.freeModeRun!;
    final goal = run.bible.objectives.first;
    final step = freeModeActSteps(run, 0).first;
    void expectConcealed() {
      expect(find.textContaining(goal), findsNothing);
      expect(find.textContaining(step), findsNothing);
    }

    expectConcealed();
    await tester.tap(find.text('Hint'));
    await tester.pumpAndSettle();
    expect(find.text(goal), findsWidgets);
    expect(find.text(step), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expectConcealed();

    final turn = game.submit('look around');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await turn;
    await tester.pumpAndSettle();
    expect(game.freeModeRun!.completedStepsForAct(0), 1);
    expectConcealed();
    await tester.tap(find.byTooltip('Story journal'));
    await tester.pumpAndSettle();
    expectConcealed();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hint'));
    await tester.pumpAndSettle();
    expect(find.text(step), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text(goal), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expectConcealed();
    await tester.pumpWidget(const SizedBox());
    game.dispose();
  });
}
