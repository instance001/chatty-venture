import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalModelRecord {
  const LocalModelRecord({
    required this.id,
    required this.name,
    required this.path,
    required this.bytes,
  });
  final String id;
  final String name;
  final String path;
  final int bytes;
  String get _normalizedName => name.toLowerCase();
  bool get isBundledSmol => false;
  bool get isRecommendedBaseline =>
      _normalizedName.contains('smollm2') && _normalizedName.contains('360m');
  bool get isConstrainedFallback =>
      _normalizedName.contains('smollm2') && _normalizedName.contains('135m');
  String get suitability =>
      switch ((isBundledSmol, isRecommendedBaseline, isConstrainedFallback)) {
        (true, _, _) => 'Local model',
        (_, true, _) => 'Recommended baseline · tested on older phones',
        (_, _, true) =>
          'Fallback only · may repeat prompt text instead of narrating',
        _ => 'Custom model · test a short adventure turn after import',
      };
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'bytes': bytes,
  };
  factory LocalModelRecord.fromJson(Map<String, dynamic> json) =>
      LocalModelRecord(
        id: json['id'] as String,
        name: json['name'] as String,
        path: json['path'] as String,
        bytes: json['bytes'] as int,
      );
}

class LocalModelStore {
  static const _modelsKey = 'local_gguf_models';
  static const selectedKey = 'selected_local_gguf_model';
  static const bundledSmolFileName = 'SmolLM2-360M-Instruct-Q4_K_M.gguf';

  /// Public source builds deliberately contain no model weights. Models are
  /// imported by the user into private app storage.
  Future<LocalModelRecord?> ensureBundledSmol() async => null;

  Future<List<LocalModelRecord>> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_modelsKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map(
          (item) => LocalModelRecord.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((model) => File(model.path).existsSync())
        .toList();
  }

  Future<LocalModelRecord?> importGguf() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['gguf'],
    );
    if (selected == null || selected.path == null) return null;
    final sourcePath = selected.path!;
    final source = File(sourcePath);
    final name = selected.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final directory = await _modelsDirectory();
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$name',
    );
    await source.copy(destination.path);
    final record = LocalModelRecord(
      id: destination.path,
      name: name,
      path: destination.path,
      bytes: await destination.length(),
    );
    final models = await load();
    models.add(record);
    await _save(models);
    return record;
  }

  Future<void> select(String? id) async =>
      (await SharedPreferences.getInstance()).setString(selectedKey, id ?? '');
  Future<void> remove(LocalModelRecord model) async {
    final file = File(model.path);
    if (await file.exists()) await file.delete();
    final models = await load();
    models.removeWhere((entry) => entry.id == model.id);
    await _save(models);
    if (await selectedId() == model.id) await select(null);
  }

  Future<bool> isBundledSmolDisabled() async => true;

  Future<void> removeBundledSmol() async {}

  Future<LocalModelRecord?> restoreBundledSmol() async => null;

  /// Deletes only the app-owned GGUF directory. It deliberately leaves the
  /// documents root itself intact.
  Future<void> clearAllModels() async {
    final directory = await _modelsDirectory();
    if (await directory.exists()) await directory.delete(recursive: true);
    await (await SharedPreferences.getInstance()).remove(_modelsKey);
    await select(null);
  }

  Future<void> keepBundledSmolRemoved() async {}

  Future<String?> selectedId() async {
    final id = (await SharedPreferences.getInstance()).getString(selectedKey);
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _save(List<LocalModelRecord> models) async =>
      (await SharedPreferences.getInstance()).setString(
        _modelsKey,
        jsonEncode(models.map((model) => model.toJson()).toList()),
      );

  Future<Directory> _modelsDirectory() async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}${Platform.pathSeparator}models',
    );
    await directory.create(recursive: true);
    return directory;
  }
}
