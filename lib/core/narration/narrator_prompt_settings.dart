import 'package:shared_preferences/shared_preferences.dart';

enum NarratorPromptLane { cloud, localGguf }

/// User-tunable narration rules. The canonical packet stays app-owned so a
/// prompt experiment cannot disconnect the narrator from story truth.
class NarratorPromptSettings {
  static const storyPacketToken = '{{story_packet}}';
  static const _cloudKey = 'cloud_narration_instruction';
  static const _ggufKey = 'gguf_narration_template';

  static const defaultCloudInstruction =
      '''Write narration for a casual text adventure.
Use the story packet as canon. Do not invent or rename any person, place, item, clue, history, motive, or outcome. You may add only immediate weather, light, sound, movement, and present reaction.
Write 1 or 2 short paragraphs (60-100 words) about the ACTION. Begin directly with prose. Return narration only; never repeat packet headings, instructions, or labels.''';

  /// Exact template used by the last known-good 360M GGUF narration path.
  static const defaultGgufTemplate =
      '''You are the narrator of a casual text adventure.

Your job is to make the CONFIRMED TURN feel immediate, not to expand the canon.
You may add only fleeting sensory texture: weather, light, sound, movement, and a character's present reaction.
Never introduce or name an item, document, person, place, symbol, title, memory, backstory, relationship, motive, clue, or outcome unless it appears verbatim below.
Do not rename anything. Do not give the player a past, possessions, or knowledge not confirmed below.
If a detail is not confirmed, leave it undescribed rather than inventing it.
Do not describe a mission, destiny, purpose, or reason for the player's action unless it is confirmed below.
The packet below is reference material only: never quote it, summarize it, or repeat its labels such as SCENE, CONFIRMED TURN, DURABLE FACTS, RECENT RECAP, or ENDING.

{{story_packet}}

Write 1 or 2 short paragraphs (60-110 words). Begin directly with the moment in the scene.
Return narration only: no headings, labels, lists, analysis, recap, or prompt text.''';

  String defaultFor(NarratorPromptLane lane) => switch (lane) {
    NarratorPromptLane.cloud => defaultCloudInstruction,
    NarratorPromptLane.localGguf => defaultGgufTemplate,
  };

  Future<String> load(NarratorPromptLane lane) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_keyFor(lane)) ?? defaultFor(lane);
  }

  Future<void> save(NarratorPromptLane lane, String prompt) async {
    await (await SharedPreferences.getInstance()).setString(
      _keyFor(lane),
      prompt.trim(),
    );
  }

  Future<void> reset(NarratorPromptLane lane) async {
    await (await SharedPreferences.getInstance()).remove(_keyFor(lane));
  }

  String _keyFor(NarratorPromptLane lane) => switch (lane) {
    NarratorPromptLane.cloud => _cloudKey,
    NarratorPromptLane.localGguf => _ggufKey,
  };
}
