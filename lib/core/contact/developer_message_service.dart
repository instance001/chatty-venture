import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

class DeveloperMessageService {
  const DeveloperMessageService({http.Client? client}) : this._(client);

  const DeveloperMessageService._(this._client);

  static final Uri _endpoint = Uri.parse(
    'https://script.google.com/macros/s/AKfycbwd0B4hhlg4JuHcVyyYQbGSGA900ddm0rPl6yQXANXrm6OharW5rGc8h_0ES6iTqSBFLg/exec',
  );

  final http.Client? _client;

  Future<void> send({required String subject, required String message}) async {
    final client = _client ?? http.Client();
    try {
      final response = await _postAndFollowGoogleRedirect(client, {
        'schemaVersion': 1,
        'messageId': 'msg_${_randomId()}',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'app': {
          'name': 'Chatty-Venture',
          'packageId': 'io.instance001.chatty_venture',
          'version': '1.0.0+1',
        },
        'message': {'subject': subject, 'body': message},
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'The publisher service returned ${response.statusCode}.',
        );
      }
      final body = jsonDecode(response.body);
      if (body is! Map || body['ok'] != true) {
        throw StateError('The publisher service did not accept the message.');
      }
    } on FormatException {
      throw StateError('The publisher service returned an invalid response.');
    } finally {
      if (_client == null) client.close();
    }
  }

  String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<http.Response> _postAndFollowGoogleRedirect(
    http.Client client,
    Map<String, Object> payload,
  ) async {
    final request = http.Request('POST', _endpoint)
      ..headers['Content-Type'] = 'text/plain; charset=utf-8'
      ..body = jsonEncode(payload);
    final first = await client.send(request);
    if (first.statusCode < 300 || first.statusCode >= 400) {
      return http.Response.fromStream(first);
    }

    final location = first.headers['location'];
    if (location == null) {
      throw StateError(
        'The publisher service redirected without a response URL.',
      );
    }
    final target = first.request!.url.resolve(location);
    if (target.scheme != 'https' ||
        !target.host.endsWith('googleusercontent.com')) {
      throw StateError(
        'The publisher service redirected to an unexpected host.',
      );
    }
    return http.Response.fromStream(
      await client.send(http.Request('GET', target)),
    );
  }
}
