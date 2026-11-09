import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/narration/narrator.dart';
import '../../core/narration/narration_guard.dart';
import '../../core/narration/narrator_prompt_settings.dart';
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
  AiDungeonMaster? _activeNarrator;
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
    final previousEngine = engine;
    final adventureId =
        (await SharedPreferences.getInstance()).getString(
          'selected_adventure',
        ) ??
        AdventureCatalog.defaultAdventure.id;
    StorySnapshot? snapshot;
    try {
      snapshot = await saves.readSnapshot();
    } on FormatException {
      // The title screen explains that this file cannot be continued.
    }
    if (!identical(engine, previousEngine)) return;
    final restored = snapshot?.state;
    final savedFreeMode = snapshot?.freeMode;
    if (savedFreeMode != null) {
      freeModeRun = savedFreeMode;
      engine = StoryEngine(template: freeModeStoryTemplate(savedFreeMode));
    } else {
      freeModeRun = null;
      freeModeStatusNotice = null;
      final selected = AdventureCatalog.byId(adventureId);
      final template =
          restored == null || selected.scenes.containsKey(restored.sceneId)
          ? selected
          : AdventureCatalog.adventures.firstWhere(
              (story) => story.scenes.containsKey(restored.sceneId),
              orElse: () => selected,
            );
      engine = StoryEngine(template: template);
    }
    if (restored != null &&
        engine.template.scenes.containsKey(restored.sceneId)) {
      state = restored;
      final run = freeModeRun;
      final pending = snapshot?.pending;
      if (pending != null) {
        _retryContext = _turnContext(pending);
        narrationError = 'Your turn was saved. Retry to finish its narration.';
      } else if (state.ending != null &&
          run != null &&
          run.isComplete &&
          run.epilogue == null) {
        // The final turn was committed before the narrator finished. Rebuild
        // the afterword request from the save and wait for the player's retry.
        _retryContext = NarratorContext.freeModeEpilogue(
          _freeModeAddendum(run, afterword: true),
        );
        narrationError =
            'Your adventure is complete. Retry to add its afterword.';
      }
      messages.add(
        AdventureMessage(
          text: 'Welcome back.\n\n${scene.title}\n\n${scene.description}',
          isPlayer: false,
        ),
      );
      if (pending?.playerAction case final String action) {
        messages.add(AdventureMessage(text: action, isPlayer: true));
      }
    } else {
      state = StoryState.initial().copyWith(
        sceneId: engine.template.initialSceneId,
      );
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
    _releaseNarrator();
    if (freeModeRun case final run?) {
      final restarted = FreeModeRun(
        templateId: run.templateId,
        bible: run.bible,
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
    engine = StoryEngine(template: engine.template);
    state = StoryState.initial().copyWith(
      sceneId: engine.template.initialSceneId,
    );
    messages
      ..clear()
      ..add(
        AdventureMessage(
          text: '${scene.title}\n\n${scene.description}',
          isPlayer: false,
        ),
      );
    narrationError = null;
    fallbackNotice = null;
    _retryContext = null;
    await saves.save(state);
    notifyListeners();
  }

  /// Invalidates pending replies before private storage is erased.
  void resetAfterPrivateDataClear() {
    _releaseNarrator();
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
    _releaseNarrator();
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
    if (!await _saveNewAdventure()) return;
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
    if (bible.setupError case final error?) throw StateError(error);
    _releaseNarrator();
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
    if (!await _saveNewAdventure()) return;
    messages.add(
      AdventureMessage(
        text: '${bible.title}\n\n${bible.premise}\n\n${scene.description}',
        isPlayer: false,
      ),
    );
    notifyListeners();
  }

  void cancelNarration() {
    _activeNarrator?.cancel();
  }

  Future<bool> _saveNewAdventure() async {
    final adventure = engine;
    await saves.save(state, freeMode: freeModeRun);
    final preferences = await SharedPreferences.getInstance();
    if (!identical(engine, adventure)) return false;
    await preferences.setString('selected_adventure', adventure.template.id);
    return identical(engine, adventure);
  }

  void _releaseNarrator() {
    cancelNarration();
    _activeNarrator = null;
    isNarrating = false;
  }

  Future<void> retryNarration() async {
    final context = _retryContext;
    if (context == null || isNarrating) return;
    await _playNarration(context);
  }

  Future<void> useFallbackNarration() async {
    final context = _retryContext;
    final fallback = _fallbackNarrator;
    if (context == null || fallback == null || isNarrating) return;
    final failedLabel = narrator.label;
    final failure = narrationError;
    final adventure = engine;
    await _playNarration(context, lane: fallback);
    if (identical(engine, adventure) && narrationError == null) {
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
    fallbackNotice = null;
    await _playNarration(
      _turnContext(
        PendingNarration(result.events, playerAction: action.playerText),
      ),
    );
  }

  Future<void> _takeFreeMode(StoryAction action) async {
    final run = freeModeRun!;
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
        ? 'Progress recorded.'
        : null;
    // The ledger keeps detailed milestones for Hint. Narration only needs the
    // action, its confirmed outcome, and the scene's public story details.
    final outcome = reduction.completed
        ? 'The action succeeds and this part of the journey is complete.'
        : reduction.progressed
        ? 'The action makes progress. The situation remains unresolved.'
        : 'The situation remains unresolved.';
    await _playNarration(
      _turnContext(
        PendingNarration([
          StoryEvent(
            reduction.completed ? 'objective_completed' : 'attempted',
            outcome,
          ),
        ], playerAction: action.playerText),
      ),
    );
  }

  NarratorContext _turnContext(PendingNarration request) {
    final run = freeModeRun;
    final closing =
        run != null && request.events.first.kind == 'objective_completed';
    final sceneRun = closing ? run.copyWith(act: run.act - 1) : run;
    return NarratorContext(
      scene: closing ? engine.template.scene('free_act_${run.act}') : scene,
      events: request.events,
      playerAction: request.playerAction,
      // Match the deterministic fact order in the saved ledger on a cold retry.
      facts: run == null ? (state.facts.toList()..sort()).toSet() : const {},
      threads: state.threads,
      recap: run == null ? state.recap : const [],
      ending: run == null ? state.ending : null,
      canonicalAddendum: sceneRun == null
          ? null
          : _freeModeAddendum(
              sceneRun,
              playerAction: request.playerAction,
              completed: closing,
              bridge: request.events.first.kind == 'transition',
            ),
    );
  }

  PendingNarration _arrival(FreeModeRun run) => PendingNarration([
    StoryEvent(
      'transition',
      'You leave ${run.bible.locations[run.act - 1]} and arrive at ${run.bible.locations[run.act]}.',
    ),
  ]);

  // Original generation, Retry and fallback all resume at the supplied stage.
  Future<void> _playNarration(
    NarratorContext context, {
    AiDungeonMaster? lane,
  }) async {
    final adventure = engine;
    final text = await _narrate(context, lane: lane);
    final run = freeModeRun;
    if (!identical(engine, adventure) ||
        text == null ||
        run == null ||
        context.events.first.kind != 'objective_completed') {
      return;
    }
    final next = run.isComplete
        ? NarratorContext.freeModeEpilogue(
            _freeModeAddendum(run, afterword: true),
          )
        : _turnContext(_arrival(run));
    await _narrate(next, lane: lane);
  }

  Future<String?> _narrate(
    NarratorContext context, {
    AiDungeonMaster? lane,
  }) async {
    final adventure = engine;
    final selected = lane ?? narrator;
    _activeNarrator = selected;
    _retryContext = context;
    isNarrating = true;
    narratorDraft = '';
    narrationError = null;
    notifyListeners();
    String? completedText;
    try {
      // Do not publish draft tokens: a later chunk can turn otherwise valid
      // prose into an instruction echo. Admission precedes UI and persistence.
      final bible = freeModeRun?.bible;
      // The turn and its narration request must reach storage before inference.
      // Follow-up stages were already checkpointed with their accepted closing.
      if (freeModeRun == null ||
          (context.scene.id != 'free_mode_afterword' &&
              context.events.first.kind != 'transition')) {
        await saves.save(
          state,
          freeMode: freeModeRun,
          pending: PendingNarration(
            context.events,
            playerAction: context.playerAction,
          ),
        );
        if (!identical(engine, adventure)) return null;
      }
      final text = await selected.narrate(context);
      if (!identical(engine, adventure)) return null;
      if (bible != null && NarrationGuard.repeatsHint(text, bible.hintText)) {
        throw StateError('The narrator repeated a hidden hint. Please retry.');
      }
      NarrationGuard.requireUsable(
        text,
        minimumWords: selected is DemoDungeonMaster ? 1 : 30,
        instructions: [
          if (context.cloudInstructionOverride != null)
            context.cloudInstructionOverride!,
          if (context.ggufTemplateOverride != null)
            context.ggufTemplateOverride!,
        ],
      );
      if (freeModeRun case final run?) {
        if (selected is! DemoDungeonMaster &&
            context.events.first.kind == 'objective_completed' &&
            NarrationGuard.reopensCompletedObjective(
              text,
              run.bible.objectives[run.act - 1],
            )) {
          throw StateError(
            'The narrator reopened the completed objective. Please retry the closing.',
          );
        }
        if (selected is! DemoDungeonMaster &&
            context.events.first.kind == 'transition') {
          if (NarrationGuard.hasUnconfirmedArrivalHandoff(
            text,
            confirmedEvents: context.events.map((event) => event.detail),
          )) {
            throw StateError(
              'The narrator added an unconfirmed item handoff. Please retry the transition.',
            );
          }
          if (run.history.isNotEmpty &&
              NarrationGuard.repeatsClosingNarration(text, run.history.last)) {
            throw StateError(
              'The narrator repeated the previous scene. Please retry the transition.',
            );
          }
        }
        final history = [...run.history, text];
        if (history.length > 12) history.removeRange(0, history.length - 12);
        final updated = run.copyWith(
          history: history,
          epilogue: context.scene.id == 'free_mode_afterword' ? text : null,
        );
        final next =
            context.events.first.kind == 'objective_completed' &&
                !run.isComplete
            ? _arrival(run)
            : null;
        await saves.save(state, freeMode: updated, pending: next);
        if (!identical(engine, adventure)) return null;
        freeModeRun = updated;
      } else {
        await saves.save(state);
        if (!identical(engine, adventure)) return null;
      }
      messages.add(AdventureMessage(text: text, isPlayer: false));
      _retryContext = null;
      completedText = text;
    } catch (error) {
      if (identical(engine, adventure)) narrationError = '$error';
    } finally {
      // Both success and failure must release the composer and discard the
      // streaming-only draft. A completed message above is the durable DM
      // bubble; leaving the draft visible duplicates it on screen.
      if (identical(engine, adventure)) {
        _activeNarrator = null;
        isNarrating = false;
        narratorDraft = '';
        notifyListeners();
      }
    }
    return completedText;
  }

  String _freeModeAddendum(
    FreeModeRun run, {
    String? playerAction,
    bool bridge = false,
    bool completed = false,
    bool afterword = false,
  }) {
    // A planned ending is not a confirmed event, even on an act's closing turn.
    // Only the afterword receives it as reference material.
    final job = bridge
        ? 'Describe your arrival at the new location in one short paragraph. Begin with what you notice there.'
        : completed
        ? NarratorPromptSettings.completedActionInstruction
        : 'Respond directly to the player action. Keep the objective unresolved unless the host-confirmed outcome says it is complete.';
    return '''FREE MODE FROZEN BIBLE:
TITLE: ${run.bible.title}
PREMISE: ${run.bible.premise}
PROBLEM: ${run.bible.problem}
KEY ANCHOR: ${run.bible.keyAnchor}
LOCAL CHARACTER: ${run.bible.supportingCharacter}
STAKES: ${run.bible.stakes}
ESCALATION: ${run.bible.escalation}
${afterword ? 'ENDING IMAGE: ${run.bible.endingImage}\n' : ''}ACT ${run.act + 1} LOCATION: ${run.isComplete ? 'resolved' : run.bible.locations[run.act]}
FLAVOUR: ${run.bible.flavour}
${playerAction == null ? '' : 'PLAYER ACTION: $playerAction'}
${bridge || run.history.isEmpty ? '' : 'RECENT NARRATION (do not repeat its phrasing): ${run.history.reversed.take(3).join(' | ')}'}
NARRATION JOB: $job
Never alter these frozen details.''';
  }
}
