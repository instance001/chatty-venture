/// Shared by setup, turns, bridges and afterwords, including custom prompts.
class SoloAdventure {
  static const narrationRule =
      'Address one adventurer as "you". You travel alone and carry out each '
      'objective yourself. Other characters stay local to their scenes.';

  // Look for a party assigned to the player. A crowd, a missing friend, or
  // someone speaking to the player is perfectly ordinary in a solo adventure.
  static final _playerParty = RegExp(
    r'\byou and your (?:party|team|crew|group|friends?|companions?|teammates?)\b|'
    r'\b(?:your|our|my) (?:party|team|group|crew|companions?|teammates?) '
    r'(?:must|follow|travel|head|set out|gather|enter|approach|decide|explore|escape)\w*\b|'
    r'\b(?:join|joins|joined|lead|gather|assemble|recruit|rally) (?:your|our|my) (?:adventuring )?party\b|'
    r'\byou (?:travel|journey|adventure|set (?:off|out)) (?:with|alongside) '
    r'(?:(?:your|the|a|an|one|two|three|four|five|several|some|\d+) ){0,2}'
    r'(?:companions?|teammates?|fellow adventurers?|friends?)\b|'
    r'\b(?:companions?|teammates?|fellow adventurers?) (?:travel|journey|adventure|set out) '
    r'(?:with|alongside|beside) you\b|'
    r'\byou (?:are|are part of|are one of|and|travel with|lead) (?:a|the) (?:party|band|group|team) of (?:friends|adventurers|explorers)\b',
    caseSensitive: false,
  );

  static bool assignsParty(String text) =>
      _playerParty.hasMatch(text.replaceAll(RegExp(r'\s+'), ' '));
}
