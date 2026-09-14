import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_key_service.dart';
import 'narrator.dart';
import 'narrator_prompt_settings.dart';
import 'narrator_style_settings.dart';

class CloudProviderDefaults {
  const CloudProviderDefaults(this.label, this.baseUrl, this.model);

  final String label;
  final String baseUrl;
  final String model;
}

const cloudProviders = <String, CloudProviderDefaults>{
  'openai': CloudProviderDefaults(
    'OpenAI',
    'https://api.openai.com/v1',
    'gpt-5.6-luna',
  ),
  'anthropic': CloudProviderDefaults(
    'Anthropic',
    'https://api.anthropic.com/v1',
    'claude-sonnet-5',
  ),
  'gemini': CloudProviderDefaults(
    'Google Gemini',
    'https://generativelanguage.googleapis.com/v1beta',
    'gemini-3.8-flash',
  ),
  'xai': CloudProviderDefaults('xAI Grok', 'https://api.x.ai/v1', 'grok-4.6'),
  'deepseek': CloudProviderDefaults(
    'DeepSeek',
    'https://api.deepseek.com',
    'deepseek-v4-flash',
  ),
  'openai_compatible': CloudProviderDefaults(
    'Custom OpenAI-compatible',
    'https://example.com/v1',
    'model-name',
  ),
};

CloudProviderDefaults cloudProviderDefaults(String provider) =>
    cloudProviders[provider] ?? cloudProviders['openai_compatible']!;

class CloudNarratorConfig {
  const CloudNarratorConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
  });

  final String provider;
  final String baseUrl;
  final String model;

  static Future<CloudNarratorConfig> load() async {
    final preferences = await SharedPreferences.getInstance();
    // Keep the existing compatible setup working after this upgrade.
    final provider =
        preferences.getString('cloud_provider') ?? 'openai_compatible';
    final defaults = cloudProviderDefaults(provider);
    final savedModel = preferences.getString('cloud_model');
    return CloudNarratorConfig(
      provider: provider,
      baseUrl: preferences.getString('cloud_base_url') ?? defaults.baseUrl,
      // Migrate only the former in-app Gemini defaults, not a user's custom pick.
      model:
          provider == 'gemini' &&
              (savedModel == 'gemini-2.5-flash' ||
                  savedModel == 'gemini-3.6-flash')
          ? defaults.model
          : savedModel ?? defaults.model,
    );
  }

  Future<void> save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('cloud_provider', provider);
    await preferences.setString('cloud_base_url', baseUrl);
    await preferences.setString('cloud_model', model);
  }
}

class CloudDungeonMaster implements AiDungeonMaster {
  CloudDungeonMaster({CloudKeyService? keys})
    : _keys = keys ?? CloudKeyService();

  final CloudKeyService _keys;
  HttpClientRequest? _activeRequest;

  @override
  String get label => 'Cloud provider';

  @override
  void cancel() {
    _activeRequest?.abort(const HttpException('Narration cancelled.'));
    _activeRequest = null;
  }

  @override
  Future<String> narrate(
    NarratorContext context, {
    void Function(String token)? onToken,
  }) async {
    final config = await CloudNarratorConfig.load();
    final instruction =
        context.cloudInstructionOverride ??
        await NarratorPromptSettings().load(NarratorPromptLane.cloud);
    final styleNote = await NarratorStyleSettings().load();
    final key = await _keys.read(config.provider);
    if (key == null || key.trim().isEmpty) {
      throw StateError(
        'No API key is stored for ${cloudProviderDefaults(config.provider).label}.',
      );
    }

    final client = HttpClient();
    try {
      final baseUrl = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
      final endpoint = switch (config.provider) {
        'openai' => '$baseUrl/responses',
        'anthropic' => '$baseUrl/messages',
        // Gemini's current text API is Interactions, rather than the legacy
        // generateContent endpoint. Keep this non-streaming until the cloud
        // lane is proven reliable; onToken still receives the completed prose.
        'gemini' => '$baseUrl/interactions',
        _ => '$baseUrl/chat/completions',
      };
      final request = await client.postUrl(Uri.parse(endpoint));
      _activeRequest = request;
      request.headers
        ..contentType = ContentType.json
        ..set(
          HttpHeaders.acceptHeader,
          config.provider == 'gemini'
              ? ContentType.json.mimeType
              : 'text/event-stream',
        )
        ..set(HttpHeaders.userAgentHeader, 'Chatty Venture');
      _addAuthHeaders(request, config.provider, key);
      request.write(
        jsonEncode(_requestBody(config, context, instruction, styleNote)),
      );

      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        throw StateError(
          '${cloudProviderDefaults(config.provider).label} request failed (${response.statusCode}): ${_errorMessage(body)}',
        );
      }

      if (config.provider == 'gemini') {
        final body = await utf8.decoder.bind(response).join();
        final decoded = jsonDecode(body);
        final narration = _extractGeminiInteractionText(decoded);
        if (!context.structuredOutput &&
            !NarratorContext.isUsableNarration(narration)) {
          throw StateError(
            'The cloud narrator returned prompt text instead of a usable scene. Please try again.',
          );
        }
        onToken?.call(narration);
        return narration;
      }

      final output = StringBuffer();
      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring(5).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final decoded = jsonDecode(data);
        if (decoded is! Map) continue;
        final token = _extractToken(config.provider, decoded);
        if (token != null && token.isNotEmpty) {
          output.write(token);
          onToken?.call(token);
        }
      }
      final narration = output.toString().trim();
      if (!context.structuredOutput &&
          !NarratorContext.isUsableNarration(narration)) {
        throw StateError(
          'The cloud narrator returned prompt text instead of a usable scene. Please try again.',
        );
      }
      return narration;
    } finally {
      _activeRequest = null;
      client.close();
    }
  }

  Map<String, Object> _requestBody(
    CloudNarratorConfig config,
    NarratorContext context,
    String cloudInstruction,
    String styleNote,
  ) {
    // A regular turn is deliberately short for responsiveness. Free Mode's
    // run bible is JSON with eleven required fields, so the narration budget
    // is not enough to finish it reliably.
    final maxOutputTokens = context.structuredOutput ? 512 : 160;
    return switch (config.provider) {
      'openai' => {
        'model': config.model,
        'instructions': context.toCloudInstruction(
          instruction: cloudInstruction,
          styleNote: styleNote,
        ),
        'input': context.toCanonicalPacket(),
        'max_output_tokens': maxOutputTokens,
        'stream': true,
      },
      'anthropic' => {
        'model': config.model,
        'max_tokens': maxOutputTokens,
        'temperature': 0.48,
        'system': context.toCloudInstruction(
          instruction: cloudInstruction,
          styleNote: styleNote,
        ),
        'messages': [
          {
            'role': 'user',
            'content':
                'Canonical story packet. Write the narration now.\n\n${context.toCanonicalPacket()}',
          },
        ],
        'stream': true,
      },
      'gemini' => {
        'model': config.model.replaceFirst('models/', ''),
        'system_instruction': context.toCloudInstruction(
          instruction: cloudInstruction,
          styleNote: styleNote,
        ),
        'input': context.toCanonicalPacket(),
        'store': false,
        'generation_config': {
          'max_output_tokens': maxOutputTokens,
          'thinking_level': 'low',
          'thinking_summaries': 'none',
        },
        if (context.structuredOutput)
          'response_format': {
            'type': 'text',
            'mime_type': 'application/json',
            'schema': {
              'type': 'OBJECT',
              'properties': {
                'title': {'type': 'STRING'},
                'premise': {'type': 'STRING'},
                'problem': {'type': 'STRING'},
                'key_anchor': {'type': 'STRING'},
                'supporting_character': {'type': 'STRING'},
                'stakes': {'type': 'STRING'},
                'escalation': {'type': 'STRING'},
                'ending_image': {'type': 'STRING'},
                'locations': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'},
                },
                'objectives': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'},
                },
                'flavour': {'type': 'STRING'},
              },
              'required': [
                'title',
                'premise',
                'problem',
                'key_anchor',
                'supporting_character',
                'stakes',
                'escalation',
                'ending_image',
                'locations',
                'objectives',
                'flavour',
              ],
            },
          },
      },
      _ => {
        'model': config.model,
        'messages': [
          {
            'role': 'system',
            'content': context.toCloudInstruction(
              instruction: cloudInstruction,
              styleNote: styleNote,
            ),
          },
          {
            'role': 'user',
            'content':
                'Canonical story packet. Write the narration now.\n\n${context.toCanonicalPacket()}',
          },
        ],
        'max_tokens': maxOutputTokens,
        'temperature': 0.48,
        'stream': true,
      },
    };
  }

  void _addAuthHeaders(HttpClientRequest request, String provider, String key) {
    switch (provider) {
      case 'anthropic':
        request.headers
          ..set('x-api-key', key)
          ..set('anthropic-version', '2023-06-01');
      case 'gemini':
        request.headers.set('x-goog-api-key', key);
      default:
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
    }
  }

  String? _extractToken(String provider, Map decoded) {
    if (provider == 'openai') {
      return decoded['type'] == 'response.output_text.delta'
          ? decoded['delta'] as String?
          : null;
    }
    if (provider == 'anthropic') {
      final delta = decoded['delta'];
      return delta is Map && delta['type'] == 'text_delta'
          ? delta['text'] as String?
          : null;
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final delta = (choices.first as Map)['delta'];
    return delta is Map ? delta['content'] as String? : null;
  }

  String _extractGeminiInteractionText(Object? decoded) {
    if (decoded is! Map) return '';
    final outputText = decoded['output_text'];
    if (outputText is String) return outputText.trim();

    // `output_text` is the SDK convenience property. REST responses also
    // expose the same content in the final model_output step, so retain that
    // shape as a defensive fallback.
    final steps = decoded['steps'];
    if (steps is! List) return '';
    for (final step in steps.reversed) {
      if (step is! Map || step['type'] != 'model_output') continue;
      final content = step['content'];
      if (content is! List) continue;
      final text = content
          .whereType<Map>()
          .where((part) => part['type'] == 'text')
          .map((part) => part['text'])
          .whereType<String>()
          .join();
      if (text.isNotEmpty) return text.trim();
    }
    return '';
  }

  String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        return (decoded['error'] as Map)['message']?.toString() ?? body;
      }
    } catch (_) {}
    return body.length > 240 ? '${body.substring(0, 240)}…' : body;
  }
}
