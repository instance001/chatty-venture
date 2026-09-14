import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/narration/narrator.dart';
import '../../core/storage/story_save_store.dart';
import '../../core/story/story_engine.dart';
import '../../core/story/free_mode.dart';
import '../../core/story/story_models.dart';

class AdventureMessage {
  const AdventureMessage({required this.text, required this.isPlayer});
  final String text;
  final bool isPlayer;
}

class AdventureController extends ChangeNotifier {
  AdventureController({
    StoryEngine? engine,
    AiDungeonMaster? narrator,
    StorySaveStore? saves,
  }) : engine = engine ?? StoryEngine(),
       narrator = narrator ?? DemoDungeonMaster(),
       saves = saves ?? StorySaveStore(),
       state = StoryState.initial();
  StoryEngine engine;
  AiDungeonMaster narrator;
  final StorySaveStore saves;
  StoryState state;
  final List<AdventureMessage> messages = [];
  bool isNarrating = false;
  String narratorDraft = '';
  String? narrationError;
  String? fallbackNotice;
  NarratorContext? _retryContext;
  AiDungeonMaster? _fallbackNarrator;
  String? fallbackLabel;
  FreeModeRun? freeModeRun;
  String? freeModeStatusNotice;
  AiDungeonMaster? get fallbackNarrator => _fallbackNarrator;
  StoryScene get scene => engine.template.scene(state.sceneId);

  void setNarrator(AiDungeonMaster value) {
    narrator = value;
    notifyListeners();
  }

  void setFallbackNarrator(AiDungeonMaster? value, {String? label}) {
    _fallbackNarrator = value;
    fallbackLabel = label;
    notifyListeners();
  }

  Future<void> begin() async {
    final adventureId =
        (await SharedPreferences.getInstance()).getString(
          'selected_adventure',
        ) ??
        AdventureCatalog.defaultAdventure.id;
    final savedFreeMode = await saves.loadFreeMode();
    if (adventureId == 'free_mode' && savedFreeMode != null) {
      freeModeRun = savedFreeMode;
      engine = StoryEngine(template: freeModeStoryTemplate(savedFreeMode));
    } else {
      freeModeRun = null;
      freeModeStatusNotice = null;
      engine = StoryEngine(template: AdventureCatalog.byId(adventureId));
    }
    final restored = await saves.load();
    if (restored != null &&
        engine.template.scenes.containsKey(restored.sceneId)) {
      state = restored;
      messages.add(
        AdventureMessage(
          text: 'Welcome back.\n\n${scene.title}\n\n${scene.description}',
          isPlayer: false,
        ),
      );
    } else {
      messages.add(
        AdventureMessage(
          text: '${scene.title}\n\n${scene.description}',
          isPlayer: false,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> restart() async {
    if (freeModeRun case final run?) {
      final restarted = run.copyWith(
        act: 0,
        completedObjectives: const [],
        completedSteps: const [],
        history: const [],
      );
      freeModeRun = restarted;
      engine = StoryEngine(template: freeModeStoryTemplate(restarted));
      state = StoryState.initial().copyWith(
        sceneId: 'free_act_1',
        facts: {
          'Free Mode: ${FreeModeCatalog.byId(run.templateId).label}',
          'Problem: ${run.bible.problem}',
          'Anchor: ${run.bible.keyAnchor}',
        },
        recap: ['${run.bible.title}: ${run.bible.premise}'],
      );
      messages
        ..clear()
        ..add(
          AdventureMessage(
            text:
                '${run.bible.title}\n\n${run.bible.premise}\n\n${scene.description}',
            isPlayer: false,
          ),
        );
      narrationError = null;
      fallbackNotice = null;
      freeModeStatusNotice = null;
      _retryContext = null;
      await saves.save(state, freeMode: restarted);
      notifyListeners();
      return;
    }
    state = StoryState.initial().copyWith(
      sceneId: engine.template.initialSceneId,
    );
    messages.clear();
    narrationError = null;
    fallbackNotice = null;
    _retryContext = null;
    await saves.clear();
    await begin();
  }

  /// Resets only the in-memory adventure after private storage has been
  /// erased. It intentionally does not write a replacement save.
  void resetAfterPrivateDataClear() {
    engine = StoryEngine();
    state = StoryState.initial();
    freeModeRun = null;
    freeModeStatusNotice = null;
    messages
      ..clear()
      ..add(
        AdventureMessage(
          text: '${scene.title}\n\n${scene.description}',
          isPlayer: false,
        ),
      );
    isNarrating = false;
    narratorDraft = '';
    narrationError = null;
    fallbackNotice = null;
    _retryContext = null;
    notifyListeners();
  }

  Future<void> startAdventure(
    StoryTemplate template, {
    required String role,
    required String tone,
  }) async {
    engine = StoryEngine(template: template);
    freeModeRun = null;
    freeModeStatusNotice = null;
    state = StoryState.initial().copyWith(
      sceneId: template.initialSceneId,
      facts: {'Your role: $role', 'Story tone: $tone'},
      recap: ['You begin as $role in a $tone tale.'],
    );
    messages.clear();
    narrationError = null;
    fallbackNotice = null;
    _retryContext = null;
    await saves.clear();
    await (await SharedPreferences.getInstance()).setString(
      'selected_adventure',
      template.id,
    );
    messages.add(
      AdventureMessage(
        text: '${scene.title}\n\n${scene.description}',
        isPlayer: false,
      ),
    );
    notifyListeners();
  }

  Future<void> choose(StoryChoice choice) => _take(
    StoryAction(
      kind: StoryActionKind.choose,
      target: choice.id,
      playerText: choice.label,
    ),
  );
  Future<void> submit(String text) => _take(
    StoryAction(
      kind: StoryActionKind.freeform,
      target: 'freeform',
      playerText: text,
    ),
  );

  Future<void> startFreeMode(
    FreeModeTemplate template,
    FreeModeBible bible,
  ) async {
    if (!bible.isUsable) {
      throw StateError('The generated adventure is incomplete.');
    }
    freeModeRun = FreeModeRun(templateId: template.id, bible: bible);
    freeModeStatusNotice = null;
    engine = StoryEngine(template: freeModeStoryTemplate(freeModeRun!));
    state = StoryState.initial().copyWith(
      sceneId: 'free_act_1',
      facts: {
        'Free Mode: ${template.label}',
        'Problem: ${bible.problem}',
        'Anchor: ${bible.keyAnchor}',
      },
      recap: ['${bible.title}: ${bible.premise}'],
    );
    messages.clear();
    narrationError = null;
    fallbackNotice = null;
    _retryContext = null;
    await saves.clear();
    await (await SharedPreferences.getInstance()).setString(
      'selected_adventure',
      'free_mode',
    );
    await saves.save(state, freeMode: freeModeRun);
    messages.add(
      AdventureMessage(
        text: '${bible.title}\n\n${bible.premise}\n\n${scene.description}',
        isPlayer: false,
      ),
    );
    notifyListeners();
  }

  void cancelNarration() {
    if (!isNarrating) return;
    narrator.cancel();
  }

  Future<void> retryNarration() async {
    final context = _retryContext;
    if (context == null || isNarrating) return;
    await _narrate(context);
  }

  Future<void> useFallbackNarration() async {
    final context = _retryContext;
    final fallback = _fallbackNarrator;
    if (context == null || fallback == null || isNarrating) return;
    final failedLabel = narrator.label;
    final failure = narrationError;
    final primary = narrator;
    narrator = fallback;
    await _narrate(context);
    narrator = primary;
    if (narrationError == null) {
      final reason = failure
          ?.replaceFirst('Bad state: ', '')
          .replaceFirst('StateError: ', '')
          .trim();
      fallbackNotice =
          '${fallbackLabel ?? fallback.label} narrated this turn because $failedLabel failed${reason == null || reason.isEmpty ? '.' : ': $reason'}';
      notifyListeners();
    }
  }

  Future<void> _take(StoryAction action) async {
    if (isNarrating || action.playerText.trim().isEmpty) return;
    if (freeModeRun != null) {
      await _takeFreeMode(action);
      return;
    }
    messages.add(AdventureMessage(text: action.playerText, isPlayer: true));
    final result = engine.apply(state, action);
    state = result.state;
    await saves.save(state);
    narrationError = null;
    fallbackNotice = null;
    final context = NarratorContext(
      scene: scene,
      events: result.events,
      facts: state.facts,
      threads: state.threads,
      recap: state.recap,
      ending: state.ending,
    );
    _retryContext = context;
    await _narrate(context);
  }

  Future<void> _takeFreeMode(StoryAction action) async {
    final run = freeModeRun!;
    final oldScene = scene;
    messages.add(AdventureMessage(text: action.playerText, isPlayer: true));
    final reduction = FreeModeReducer().apply(run, action.playerText);
    freeModeRun = reduction.run;
    final nextSceneId = reduction.ended
        ? state.sceneId
        : 'free_act_${reduction.run.act + 1}';
    final facts = {...state.facts};
    if (reduction.completed) {
      facts.add('Completed: ${run.bible.objectives[run.act]}');
    }
    if (reduction.progressed && !reduction.completed) {
      facts.add(reduction.detail);
    }
    final recap = [...state.recap, reduction.detail];
    if (recap.length > 12) recap.removeRange(0, recap.length - 12);
    state = state.copyWith(
      sceneId: nextSceneId,
      turn: state.turn + 1,
      facts: facts,
      recap: recap,
      ending: reduction.ended
          ? 'You resolve ${run.bible.problem.replaceFirst(RegExp(r'[.!?]+$'), '')}.'
          : null,
    );
    freeModeStatusNotice = reduction.ended
        ? 'Final objective complete. The story reaches its ending.'
        : reduction.completed
        ? 'Objective complete. The story moves to ${reduction.run.bible.locations[reduction.run.act]}.'
        : reduction.progressed
        ? reduction.detail
        : 'Still working toward: ${run.bible.objectives[run.act]}';
    await saves.save(state, freeMode: freeModeRun);
    final actionContext = NarratorContext(
      scene: oldScene,
      events: [
        StoryEvent(
          reduction.completed ? 'objective_completed' : 'attempted',
          reduction.detail,
        ),
      ],
      facts: state.facts,
      threads: state.threads,
      recap: state.recap,
      ending: null,
      canonicalAddendum: _freeModeAddendum(
        reduction.run,
        playerAction: action.playerText,
        hostOutcome: reduction.detail,
      ),
    );
    _retryContext = actionContext;
    final finalActNarration = await _narrate(actionContext);
    if (reduction.completed && !reduction.ended && finalActNarration != null) {
      final nextRun = freeModeRun!;
      final bridgeContext = NarratorContext(
        scene: scene,
        events: [
          StoryEvent(
            'transition',
            'Previous act outcome: ${reduction.detail}\nFinal narration: $finalActNarration\nNext fixed location: ${nextRun.bible.locations[nextRun.act]}\nNext fixed objective: ${nextRun.bible.objectives[nextRun.act]}',
          ),
        ],
        facts: state.facts,
        threads: state.threads,
        recap: state.recap,
        ending: null,
        canonicalAddendum: _freeModeAddendum(
          nextRun,
          hostOutcome: reduction.detail,
          bridge: true,
        ),
      );
      await _narrate(bridgeContext);
    }
    if (reduction.ended && finalActNarration != null) {
      final completedRun = freeModeRun!;
      final afterword = await _narrate(
        NarratorContext.freeModeEpilogue(
          _freeModeAddendum(
            completedRun,
            hostOutcome:
                'Completed objectives: ${completedRun.completedObjectives.map((act) => completedRun.bible.objectives[act]).join(' | ')}',
          ),
        ),
      );
      if (afterword != null) {
        freeModeRun = freeModeRun!.copyWith(epilogue: afterword);
        await saves.save(state, freeMode: freeModeRun);
        notifyListeners();
      }
    }
  }

  Future<String?> _narrate(NarratorContext context) async {
    isNarrating = true;
    narratorDraft = '';
    narrationError = null;
    notifyListeners();
    String? completedText;
    try {
      final text = await narrator.narrate(
        context,
        onToken: (token) {
          narratorDraft += token;
          notifyListeners();
        },
      );
      messages.add(AdventureMessage(text: text, isPlayer: false));
      if (freeModeRun case final run?) {
        final history = [...run.history, text];
        if (history.length > 12) history.removeRange(0, history.length - 12);
        freeModeRun = run.copyWith(history: history);
        await saves.save(state, freeMode: freeModeRun);
      }
      _retryContext = null;
      completedText = text;
    } catch (error) {
      narrationError = '$error';
    } finally {
      // Both success and failure must release the composer and discard the
      // streaming-only draft. A completed message above is the durable DM
      // bubble; leaving the draft visible duplicates it on screen.
      isNarrating = false;
      narratorDraft = '';
      notifyListeners();
    }
    return completedText;
  }

  String _freeModeAddendum(
    FreeModeRun run, {
    String? playerAction,
    String? hostOutcome,
    bool bridge = false,
  }) =>
      '''FREE MODE FROZEN BIBLE:
TITLE: ${run.bible.title}
PREMISE: ${run.bible.premise}
PROBLEM: ${run.bible.problem}
KEY ANCHOR: ${run.bible.keyAnchor}
SUPPORTING CHARACTER: ${run.bible.supportingCharacter}
STAKES: ${run.bible.stakes}
ESCALATION: ${run.bible.escalation}
ENDING IMAGE: ${run.bible.endingImage}
ACT ${run.act + 1} LOCATION: ${run.isComplete ? 'resolved' : run.bible.locations[run.act]}
ACT ${run.act + 1} OBJECTIVE: ${run.isComplete ? 'resolved' : run.bible.objectives[run.act]}
FLAVOUR: ${run.bible.flavour}
${playerAction == null ? '' : 'PLAYER ACTION: $playerAction'}
${hostOutcome == null ? '' : 'HOST-CONFIRMED OUTCOME: $hostOutcome'}
${run.history.isEmpty ? '' : 'RECENT NARRATION (do not repeat its phrasing): ${run.history.reversed.take(3).join(' | ')}'}
${bridge ? 'NARRATION JOB: Write one short connective bridge from the confirmed outcome into the fixed next location and objective. Do not claim a new fact, solution, or outcome.' : 'NARRATION JOB: Respond directly to the player action. Keep the objective unresolved unless the host-confirmed outcome says it is complete.'}
Never alter these frozen details.''';
}
