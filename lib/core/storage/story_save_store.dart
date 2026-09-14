import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../story/story_models.dart';
import '../story/free_mode.dart';

/// A save contains canonical story truth only. Chat bubbles are presentation
/// and can always be rebuilt from the compact ledger.
class StorySaveStore {
  static const _fileName = 'active_story.json';

  Future<StoryState?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      return StorySaveCodec.decode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  Future<void> save(StoryState state, {FreeModeRun? freeMode}) async {
    final file = await _file();
    await file.writeAsString(
      StorySaveCodec.encode(state, freeMode: freeMode),
      flush: true,
    );
  }

  Future<FreeModeRun?> loadFreeMode() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      return StorySaveCodec.decodeFreeMode(await file.readAsString());
    } on FormatException {
      return null;
    }
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  Future<int> byteSize() async {
    final file = await _file();
    return await file.exists() ? file.length() : 0;
  }

  Future<File> _file() async => File(
    '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}$_fileName',
  );
}

class StorySaveCodec {
  static const version = 1;

  static String encode(StoryState state, {FreeModeRun? freeMode}) =>
      const JsonEncoder.withIndent('  ').convert({
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
      });

  static FreeModeRun? decodeFreeMode(String source) {
    final root = jsonDecode(source);
    if (root is! Map || root['free_mode'] == null) {
      return null;
    }
    if (root['free_mode'] is! Map) {
      throw const FormatException('Invalid Free Mode save.');
    }
    return FreeModeRun.fromJson(root['free_mode'] as Map);
  }

  static StoryState decode(String source) {
    final root = jsonDecode(source);
    if (root is! Map ||
        root['save_version'] != version ||
        root['state'] is! Map) {
      throw const FormatException('Unsupported story save.');
    }
    final state = Map<String, dynamic>.from(root['state'] as Map);
    final rawThreads = state['threads'];
    final threads = <String, StoryThread>{};
    if (rawThreads is List) {
      for (final raw in rawThreads.whereType<Map>()) {
        final item = Map<String, dynamic>.from(raw);
        final id = item['id'] as String?;
        final label = item['label'] as String?;
        final status = item['status'] as String?;
        if (id != null && label != null && status != null) {
          threads[id] = StoryThread(id: id, label: label, status: status);
        }
      }
    }
    final sceneId = state['scene_id'] as String?;
    final turn = state['turn'] as int?;
    if (sceneId == null || turn == null) {
      throw const FormatException('Invalid story save.');
    }
    return StoryState(
      sceneId: sceneId,
      turn: turn,
      facts: (state['facts'] as List? ?? const []).whereType<String>().toSet(),
      threads: threads,
      recap: (state['recap'] as List? ?? const []).whereType<String>().toList(),
      ending: state['ending'] as String?,
    );
  }
}
