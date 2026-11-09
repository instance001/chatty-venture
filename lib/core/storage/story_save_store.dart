import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../story/story_models.dart';
import '../story/story_engine.dart' show AdventureCatalog;
import '../story/free_mode.dart';

class PendingNarration {
  const PendingNarration(this.events, {this.playerAction});
  final List<StoryEvent> events;
  final String? playerAction;

  Map<String, Object?> toJson() => {
    if (playerAction != null) 'player_action': playerAction,
    'events': [
      for (final event in events) {'kind': event.kind, 'detail': event.detail},
    ],
  };

  static PendingNarration? read(Object? value, FreeModeRun? run) {
    if (value is! Map || value['events'] is! List) return null;
    final action = value['player_action'];
    if (action != null && action is! String) return null;
    final events = <StoryEvent>[];
    for (final item in value['events'] as List) {
      if (item case {'kind': String kind, 'detail': String detail}) {
        events.add(StoryEvent(kind, detail));
      } else {
        return null;
      }
    }
    if (events.isEmpty) return null;
    if (run != null) {
      if (events.length != 1 || run.epilogue != null) return null;
      final valid = switch (events.single.kind) {
        'attempted' => !run.isComplete && action is String,
        'objective_completed' => run.act > 0 && action is String,
        'transition' => run.act > 0 && !run.isComplete && action == null,
        _ => false,
      };
      if (!valid) return null;
    }
    return PendingNarration(events, playerAction: action as String?);
  }
}

typedef StorySnapshot = ({
  StoryState state,
  FreeModeRun? freeMode,
  PendingNarration? pending,
});

/// A save contains canonical story truth only. Chat bubbles are presentation
/// and can always be rebuilt from the compact ledger.
class StorySaveStore {
  StorySaveStore({File? file}) : _saveFile = file;

  static const _fileName = 'active_story.json';
  final File? _saveFile;
  Future<void> _pendingWrite = Future.value();

  // A previous turn may already be writing when an adventure is replaced.
  Future<void> _inOrder(Future<void> Function() operation) {
    final write = _pendingWrite.then((_) => operation());
    _pendingWrite = write.catchError((Object _) {});
    return write;
  }

  /// A missing file is a fresh start. A malformed file is reported to the
  /// title screen and left intact until the player starts another adventure.
  Future<StorySnapshot?> readSnapshot() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return StorySaveCodec.decodeSnapshot(utf8.decode(await file.readAsBytes()));
  }

  Future<StoryState?> load() async {
    try {
      return (await readSnapshot())?.state;
    } on FormatException {
      return null;
    }
  }

  Future<void> save(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) => _inOrder(() async {
    final file = await _file();
    // Replace the ledger and its retry marker together, even if Android
    // terminates the process during a write.
    final staging = File('${file.path}.tmp');
    await staging.writeAsString(
      StorySaveCodec.encode(state, freeMode: freeMode, pending: pending),
      flush: true,
    );
    await staging.rename(file.path);
  });

  Future<FreeModeRun?> loadFreeMode() async {
    try {
      return (await readSnapshot())?.freeMode;
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() => _inOrder(() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final staging = File('${file.path}.tmp');
    if (await staging.exists()) await staging.delete();
  });

  Future<int> byteSize() async {
    final file = await _file();
    return await file.exists() ? file.length() : 0;
  }

  Future<File> _file() async =>
      _saveFile ??
      File(
        '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}$_fileName',
      );
}

class StorySaveCodec {
  static const version = 1;

  static String encode(
    StoryState state, {
    FreeModeRun? freeMode,
    PendingNarration? pending,
  }) => const JsonEncoder.withIndent('  ').convert({
    'save_version': version,
    'state': {
      'scene_id': state.sceneId,
      'turn': state.turn,
      'facts': state.facts.toList()..sort(),
      'threads': state.threads.values
          .map(
            (thread) => {
              'id': thread.id,
              'label': thread.label,
              'status': thread.status,
            },
          )
          .toList(),
      'recap': state.recap,
      'ending': state.ending,
    },
    if (freeMode != null) 'free_mode': freeMode.toJson(),
    if (pending != null) 'pending_narration': pending.toJson(),
  });

  static StorySnapshot decodeSnapshot(String source) {
    final root = _root(source);
    final state = _state(root['state'] as Map);
    final run = _freeMode(root['free_mode']);
    if (run != null) {
      final sceneNumber = run.isComplete
          ? run.bible.locations.length
          : run.act + 1;
      if (state.sceneId != 'free_act_$sceneNumber' ||
          run.isComplete != (state.ending != null)) {
        throw const FormatException(
          'Free Mode progress does not match the saved scene.',
        );
      }
    } else if (!AdventureCatalog.adventures.any(
      (story) => story.scenes.containsKey(state.sceneId),
    )) {
      throw const FormatException('Unrecognized saved scene.');
    }
    return (
      state: state,
      freeMode: run,
      pending: PendingNarration.read(root['pending_narration'], run),
    );
  }

  static FreeModeRun? decodeFreeMode(String source) =>
      _freeMode(_root(source)['free_mode']);

  static FreeModeRun? _freeMode(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const FormatException('Invalid Free Mode save.');
    }
    return FreeModeRun.fromJson(value);
  }

  static Map _root(String source) {
    final root = jsonDecode(source);
    if (root is! Map ||
        root['save_version'] != version ||
        root['state'] is! Map) {
      throw const FormatException('Unsupported story save.');
    }
    return root;
  }

  static StoryState decode(String source) =>
      _state(_root(source)['state'] as Map);

  static StoryState _state(Map state) {
    final rawThreads = state['threads'];
    final threads = <String, StoryThread>{};
    if (rawThreads is List) {
      for (final raw in rawThreads.whereType<Map>()) {
        final id = raw['id'];
        final label = raw['label'];
        final status = raw['status'];
        if (id is String && label is String && status is String) {
          threads[id] = StoryThread(id: id, label: label, status: status);
        }
      }
    }
    final sceneId = state['scene_id'];
    final turn = savedCounter(state['turn']);
    final ending = state['ending'];
    if (sceneId is! String ||
        sceneId.trim().isEmpty ||
        turn == null ||
        turn < 0 ||
        (ending != null && ending is! String)) {
      throw const FormatException('Invalid story save.');
    }
    Iterable<String> strings(String key) => state[key] is List
        ? (state[key] as List).whereType<String>()
        : const [];
    return StoryState(
      sceneId: sceneId,
      turn: turn,
      facts: strings('facts').toSet(),
      threads: threads,
      recap: strings('recap').toList(),
      ending: ending as String?,
    );
  }
}
