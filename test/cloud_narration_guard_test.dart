import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chatty_venture/core/narration/cloud_key_service.dart';
import 'package:chatty_venture/core/narration/cloud_narrator.dart';
import 'package:chatty_venture/core/narration/narrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/narration_fixtures.dart';

class _Keys extends CloudKeyService {
  @override
  Future<String?> read(String providerId) async => 'test-key';
}

class _Headers implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.chunks, this.beforeChunk);
  final List<String> chunks;
  final void Function() beforeChunk;
  @override
  int get statusCode => 200;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.fromIterable(chunks)
      .map((chunk) {
        beforeChunk();
        return utf8.encode(chunk);
      })
      .listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final _Response response;
  @override
  final headers = _Headers();
  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.response);
  final _Response response;
  bool closed = false;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async => _Request(response);
  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final provider in ['openai_compatible', 'gemini']) {
    for (final (description, suffix) in [
      ('plain prose', ''),
      ('an instruction echo', ' $reportedLeak'),
      ('a JSON suffix', '\n{"narration":"$cleanNarration"}'),
    ]) {
      test(
        '$provider buffers and checks $description before publishing',
        () async {
          SharedPreferences.setMockInitialValues({
            'cloud_provider': provider,
            'cloud_base_url': 'https://example.invalid/v1',
          });
          final published = <String>[];
          String delta(String text) =>
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': text},
                  },
                ],
              })}\n\n';
          final client = _Client(
            _Response(
              provider == 'gemini'
                  ? [
                      jsonEncode({'output_text': '$cleanNarration$suffix'}),
                    ]
                  : [delta(cleanNarration), delta(suffix), 'data: [DONE]\n\n'],
              () => expect(published, isEmpty),
            ),
          );
          await HttpOverrides.runZoned(() async {
            final pending = CloudDungeonMaster(keys: _Keys()).narrate(
              NarratorContext.freeModeEpilogue('The bell was restored.'),
              onToken: published.add,
            );
            if (suffix.isNotEmpty) {
              await expectLater(pending, throwsA(isA<StateError>()));
              expect(published, isEmpty);
            } else {
              expect(await pending, cleanNarration);
              expect(published, [cleanNarration]);
            }
          }, createHttpClient: (_) => client);
          expect(client.closed, isTrue);
        },
      );
    }
  }
}
