import 'dart:convert';

import '../story/solo_adventure.dart';
import 'narrator_prompt_settings.dart';

/// Admission checks for model text, before it becomes visible or saved.
/// This detects instruction echoes, not arbitrary contradictions of story canon.
class NarrationGuard {
  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp('[’‘]'), "'")
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ')
      .trim();

  static bool repeatsHint(String text, Iterable<String> hints) {
    final words = ' ${_normalize(text)} ';
    return hints
        .map(_normalize)
        .any((hint) => hint.isNotEmpty && words.contains(' $hint '));
  }

  // GGUF may cut ordinary replies off at the last sentence, stripping the
  // closing quote and brace. Recognize an object member even in a fragment.
  static final _jsonMarker = RegExp(
    r'```[ \t]*json\b|\{\s*"(?:[^"\\]|\\.)*"\s*:|\[\s*(?:"|\{|\[)',
    caseSensitive: false,
  );

  static bool containsJsonOutput(String text) {
    if (_jsonMarker.hasMatch(text)) return true;
    final trimmed = text.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return false;
    try {
      return jsonDecode(trimmed) is List;
    } on FormatException {
      return false; // Bracketed prose can be an ordinary stage direction.
    }
  }

  // Recognize direct reports of a physical handoff. Require an item noun so
  // ordinary reactions such as "the local gives you a wary glance" stay valid.
  static const _item =
      r'(?:the|a|an)\s+((?:[a-z-]+\s+){0,2}(?:map|key|compass|book|letter|'
      r'note|coin|token|lantern|knife|pouch|scroll|ring|ticket))';
  static final _handoff = RegExp(
    r'^(?:(?:the|a|an)\s+([a-z]+(?:\s+[a-z]+){0,2})|([a-z]+))'
    r'\s+(?:hands?|handed|gives?|gave|passes|pass|passed)\s+'
    '(?:you\\s+$_item|(?:over\\s+)?$_item\\s+to\\s+you)'
    r'(?=\s*[,!.…—]|\s*$|\s+(?:and|as|before|from|of|with)\b)',
    caseSensitive: false,
  );

  static Iterable<(String, String)> _reportedHandoffs(String text) sync* {
    for (final sentence in text.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
      if (sentence.trimRight().endsWith('?')) continue;
      final match = _handoff.firstMatch(sentence.trim());
      if (match == null) continue;
      final giver = _normalize((match[1] ?? match[2])!);
      if (RegExp(r'\b(?:never|not|nobody|nothing|who)\b').hasMatch(giver)) {
        continue;
      }
      yield (giver, _normalize((match[3] ?? match[4])!));
    }
  }

  static bool hasUnconfirmedArrivalHandoff(
    String arrival, {
    required Iterable<String> confirmedEvents,
  }) {
    final confirmed = confirmedEvents.expand(_reportedHandoffs).toSet();
    return _reportedHandoffs(
      arrival,
    ).any((handoff) => !confirmed.contains(handoff));
  }

  static final _pendingAction = RegExp(
    r"^(?:(?:but|and|now)\s+)*(?:(?:it(?:'s| is) (?:now )?time to|"
    r"you (?:still )?(?:must|need to|have to|have yet to))\s+)?",
  );

  static String _actionWords(String text) => _normalize(text)
      .split(' ')
      .where((word) => !const {'a', 'an', 'the'}.contains(word))
      .join(' ');

  static bool reopensCompletedObjective(String closing, String objective) {
    final clauses = _actionWords(
      objective,
    ).split(RegExp(r' (?:and then|and|then) '));
    final actions = <String>{};
    for (var i = 0; i < clauses.length; i++) {
      final clause = clauses[i];
      if (clause.contains(' ')) {
        actions.add(clause);
      } else if (i + 1 < clauses.length && clauses[i + 1].contains(' ')) {
        // "Find and escape the hidden entrance" assigns both verbs one target.
        final next = clauses[i + 1];
        actions.add(clause + next.substring(next.indexOf(' ')));
      }
    }
    // Compare complete requests. A matching verb, a remembered obligation or
    // a mention of the old target in an unrelated request is insufficient.
    for (final sentence in RegExp(r'[^.!?;\n]+[?]?').allMatches(closing)) {
      final line = sentence[0]!.trim().toLowerCase().replaceAll('’', "'");
      if (line.endsWith('?')) continue;
      final request = line
          .replaceFirst(_pendingAction, '')
          .replaceFirst(RegExp(r'\s+again$'), '');
      final words = _actionWords(request);
      if (words.contains(' ') &&
          actions.any(
            (action) =>
                action == words ||
                action.startsWith('$words to ') ||
                action.startsWith('$words of '),
          )) {
        return true;
      }
    }
    return false;
  }

  static bool repeatsClosingNarration(String bridge, String closing) {
    final candidate = _normalize(bridge);
    final previous = ' ${_normalize(closing)} ';
    if (' $candidate ' == previous) return true;
    final words = candidate.split(' ');
    if (words.length < 12) return false;
    // Count overlapping six-word phrases. An occasional shared place name
    // is fine, while a copied paragraph with a new opening still fails.
    final phrases = words.length - 5;
    var copied = 0;
    for (var i = 0; i < phrases; i++) {
      if (previous.contains(' ${words.sublist(i, i + 6).join(' ')} ')) copied++;
    }
    return copied * 2 > phrases;
  }

  static bool containsInstructionLeak(
    String text, {
    Iterable<String> instructions = const [],
  }) {
    final normalized = ' ${_normalize(text)} ';
    // Short, distinctive directives also catch partial/paraphrased echoes.
    for (final phrase in const [
      'you are the narrator',
      'write narration for',
      'your job is to',
      'fleeting sensory texture',
      'do not rename anything',
      'do not give the player',
      'if a detail is not confirmed',
      'unless it appears verbatim below',
      'return narration only',
      'return prose only',
      'return json only',
      'never alter these frozen details',
      'keep the objective unresolved',
      'confirmed by the host',
      'host confirmed outcome',
      'treat this as delivery guidance',
    ]) {
      if (normalized.contains(' $phrase ')) return true;
    }
    if (RegExp(
      r'\b(?:scene(?: description)?|confirmed turn|durable facts|open threads|'
      r'recent recap|ending|dm style note|free mode frozen bible|'
      r'key anchor|local character|ending image|previous act outcome|final narration|'
      r'progress recorded|you continue working toward|you complete(?: the final objective)?|'
      r'player action|narration job|recent narration|next fixed (?:location|objective)|'
      r'act \d+ (?:location|objective))\s*(?:\([^\n)]*\))?\s*:',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    // Common nouns such as "problem" are only distinctive as field headings.
    if (RegExp(
      r'(?:^|[.!?]\s+|\n)\s*(?:title|premise|problem|stakes|escalation|flavour)\s*:',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }
    // Compare instruction-only spans, never the canonical story packet. Eight
    // consecutive words catch copies even with changed case or punctuation.
    for (final source in [
      SoloAdventure.narrationRule,
      NarratorPromptSettings.completedActionInstruction,
      NarratorPromptSettings.defaultCloudInstruction,
      NarratorPromptSettings.defaultGgufTemplate,
      ...instructions,
    ]) {
      for (final span in source.split(
        NarratorPromptSettings.storyPacketToken,
      )) {
        final words = _normalize(span).split(' ');
        for (var i = 0; i + 8 <= words.length; i++) {
          if (normalized.contains(' ${words.sublist(i, i + 8).join(' ')} ')) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static bool isUsable(
    String text, {
    Iterable<String> instructions = const [],
    int minimumWords = 30,
  }) => _rejection(text, instructions, minimumWords) == null;

  static void requireUsable(
    String text, {
    Iterable<String> instructions = const [],
    int minimumWords = 30,
  }) {
    final reason = _rejection(text, instructions, minimumWords);
    if (reason != null) throw StateError(reason);
  }

  static String? _rejection(
    String text,
    Iterable<String> instructions,
    int minimumWords,
  ) {
    if (containsJsonOutput(text)) {
      return 'The narrator returned JSON during a story turn. Please retry or choose another narrator.';
    }
    if (SoloAdventure.assignsParty(text)) {
      return 'The narrator gave you a party in a solo adventure. Please retry.';
    }
    if (text.trim().isEmpty ||
        text.trim().split(RegExp(r'\s+')).length < minimumWords ||
        containsInstructionLeak(text, instructions: instructions)) {
      return 'The narrator returned instructions or incomplete narration. Please retry or choose another narrator.';
    }
    return null;
  }
}
