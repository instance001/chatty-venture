import 'dart:convert';

import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:chatty_venture/core/narration/narrator_profiles.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/narration_fixtures.dart';

class _ProposalNarrator implements AiDungeonMaster {
  _ProposalNarrator(this.response);
  final String response;
  @override
  String get label => 'test';
  @override
  void cancel() {}
  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async => response;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final template = FreeModeCatalog.templates.first;
  const channel = MethodChannel('chatty_venture/local_gguf');
  const events = MethodChannel('chatty_venture/local_gguf_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, Object?> proposal;
  late List<String> eventCalls;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'narrator_style_note': 'Write prose only with a dramatic heading.',
    });
    proposal = (await FreeModeProposalService().generate(
      DemoDungeonMaster(),
      template,
    )).toJson();
    eventCalls = [];
    messenger.setMockMethodCallHandler(events, (call) async {
      eventCalls.add(call.method);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  test(
    'local setup requests constrained output and preserves the full JSON',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'generate');
        final args = call.arguments as Map;
        expect(args['structuredOutput'], isTrue);
        expect(args['contextSize'], 2048);
        expect(args['maxTokens'], greaterThanOrEqualTo(768));
        expect(args['prompt'], contains('Return JSON only'));
        expect(args['prompt'], isNot(contains('dramatic heading')));
        return {'text': jsonEncode(proposal)};
      });
      final bible = await FreeModeProposalService().generate(
        LocalGgufDungeonMaster('test', 'model.gguf'),
        template,
      );
      expect(bible.toJson(), proposal);
      expect(eventCalls, ['listen', 'cancel']);
    },
  );

  test('normal narration keeps its prose settings and style', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      expect(args['structuredOutput'], isFalse);
      expect(args['contextSize'], 1536);
      expect(args['maxTokens'], 120);
      expect(args['prompt'], contains('dramatic heading'));
      return {'text': cleanNarration};
    });
    await LocalGgufDungeonMaster(
      'test',
      'model.gguf',
    ).narrate(NarratorContext.freeModeEpilogue('The bell was restored.'));
  });

  test(
    'local narration rejects a sentence-trimmed JSON wrapper before callbacks',
    () async {
      final published = <String>[];
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'text': '{"narration": "$cleanNarration'},
      );
      await expectLater(
        LocalGgufDungeonMaster('test', 'model.gguf').narrate(
          NarratorContext.freeModeEpilogue('The bell was restored.'),
          onToken: published.add,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('JSON'),
          ),
        ),
      );
      expect(published, isEmpty);
      expect(eventCalls, ['listen', 'cancel']);
    },
  );

  test(
    'a failed local setup releases its event subscription for retry',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: 'generation_failed');
      });
      await expectLater(
        FreeModeProposalService().generate(
          LocalGgufDungeonMaster('test', 'model.gguf'),
          template,
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(eventCalls, ['listen', 'cancel']);
    },
  );

  test('plain text from the reported failure is rejected clearly', () async {
    await expectLater(
      FreeModeProposalService().generate(
        _ProposalNarrator('Title: The Lost City of Eldoria'),
        template,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('valid adventure JSON'),
        ),
      ),
    );
  });

  test(
    'local narration rejects echoes before callbacks and releases events',
    () async {
      final published = <String>[];
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'text': reportedLeak},
      );
      await expectLater(
        LocalGgufDungeonMaster('test', 'model.gguf').narrate(
          NarratorContext.freeModeEpilogue('The bell was restored.'),
          onToken: published.add,
        ),
        throwsA(isA<StateError>()),
      );
      expect(published, isEmpty);
      expect(eventCalls, ['listen', 'cancel']);
    },
  );

  test('local narration checks the saved custom template and style', () async {
    const custom =
        'Describe each passing moment using exactly two economical paragraphs';
    for (final key in ['gguf_narration_template', 'narrator_style_note']) {
      SharedPreferences.setMockInitialValues({
        key: '$custom\n{{story_packet}}',
      });
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'text': '$cleanNarration $custom.'},
      );
      await expectLater(
        LocalGgufDungeonMaster('test', 'model.gguf').narrate(
          NarratorContext(
            scene: NarratorContext.freeModeEpilogue('').scene,
            events: const [],
            facts: const {},
            threads: const {},
            recap: const [],
            ending: null,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    }
  });

  test(
    'proposal text and array fields cannot smuggle instruction echoes',
    () async {
      for (final key in ['premise', 'locations', 'objectives']) {
        final contaminated = {...proposal};
        contaminated[key] = key == 'premise'
            ? reportedLeak
            : [
                'Quay',
                'Tower',
                'Return JSON only. Create a small self-contained three-act adventure.',
              ];
        await expectLater(
          FreeModeProposalService().generate(
            _ProposalNarrator(jsonEncode(contaminated)),
            template,
          ),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test(
    'new proposals cannot use save migration to invent missing details',
    () async {
      proposal.remove('stakes');
      await expectLater(
        FreeModeProposalService().generate(
          _ProposalNarrator(jsonEncode(proposal)),
          template,
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('malformed act lists fail without a runtime cast error', () async {
    for (final invalid in [
      'Quay, Archive, Tower',
      ['Quay', 'Tower'],
      [1, 2, 3],
    ]) {
      proposal['locations'] = invalid;
      await expectLater(
        FreeModeProposalService().generate(
          _ProposalNarrator(jsonEncode(proposal)),
          template,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('setup rejects unfinished story details before preview', () async {
    // These two defects occurred together in the Aria's Quest emulator run.
    // Exercise them independently so the first rejection cannot mask the other.
    final textureId = 'flame_texture_id_${'1234567890' * 14}123';
    for (final change in [
      {
        'locations': ['Quay', '{{location}}', 'Tower'],
      },
      {
        'objectives': ['Read the bell', 'Find {{objective}}', 'Ring it'],
      },
      {
        'objectives': ['Read the bell', 'Trace the line', textureId],
      },
      {'key_anchor': 'An inscription marked [insert item name here]'},
      {'flavour': 'A faint glow from asset_id_913.'},
      {'ending_image': 'A light above ruin_gate_001.'},
    ]) {
      await expectLater(
        FreeModeProposalService().generate(
          _ProposalNarrator(jsonEncode({...proposal, ...change})),
          template,
        ),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test('setup accepts numbered locations and in-world call signs', () async {
    final valid = {
      ...proposal,
      'key_anchor': 'a radio marked R2-D2',
      'locations': ['Platform 9', 'Vault B-12', 'Relay Station 2049'],
      'objectives': ['Read signal 42', 'Find the operator', 'Contact Echo_7'],
    };
    final bible = await FreeModeProposalService().generate(
      _ProposalNarrator(jsonEncode(valid)),
      template,
    );
    expect(bible.toJson(), valid);
  });

  test('cloud setup also excludes prose style instructions', () {
    expect(
      NarratorContext.freeModeProposal(
        'Mystery',
      ).toCloudInstruction(styleNote: 'Prose only'),
      isNot(contains('Prose only')),
    );
  });

  test(
    'new adventures reject the emulator party premise and party objectives',
    () async {
      for (final change in [
        {
          'premise':
              'A group of friends discover a hidden path to safety in a magical forest.',
        },
        {
          'premise':
              'You are a group of adventurers searching for the silent bell.',
        },
        {'premise': 'You travel with three companions to Ember Crossing.'},
        {
          'objectives': [
            'Find the bell',
            'Gather your party at the tower',
            'Ring the bell',
          ],
        },
      ]) {
        await expectLater(
          FreeModeProposalService().generate(
            _ProposalNarrator(jsonEncode({...proposal, ...change})),
            template,
          ),
          throwsA(isA<FormatException>()),
        );
      }
      proposal['premise'] =
          'You search for a group of friends lost in the forest.';
      final bible = await FreeModeProposalService().generate(
        _ProposalNarrator(jsonEncode(proposal)),
        template,
      );
      expect(bible.premise, proposal['premise']);
    },
  );
}
