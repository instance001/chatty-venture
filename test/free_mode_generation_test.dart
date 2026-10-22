import 'dart:convert';

import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:chatty_venture/core/narration/narrator_profiles.dart';
import 'package:chatty_venture/core/story/free_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      return {'text': 'A bell rings.'};
    });
    await LocalGgufDungeonMaster(
      'test',
      'model.gguf',
    ).narrate(NarratorContext.freeModeEpilogue('The bell was restored.'));
  });

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

  test('cloud setup also excludes prose style instructions', () {
    expect(
      NarratorContext.freeModeProposal(
        'Mystery',
      ).toCloudInstruction(styleNote: 'Prose only'),
      isNot(contains('Prose only')),
    );
  });
}
