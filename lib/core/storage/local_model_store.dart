import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
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
  bool get isBundledSmol =>
      name == LocalModelStore.bundledSmolFileName &&
      path.endsWith(
        '${Platform.pathSeparator}models${Platform.pathSeparator}${LocalModelStore.bundledSmolFileName}',
      );
  bool get isRecommendedBaseline =>
      _normalizedName.contains('smollm2') && _normalizedName.contains('360m');
  bool get isConstrainedFallback =>
      _normalizedName.contains('smollm2') && _normalizedName.contains('135m');
  String get suitability =>
      switch ((isBundledSmol, isRecommendedBaseline, isConstrainedFallback)) {
        (true, _, _) => 'Included with Chatty-Venture · recommended baseline',
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
  static const _bundledSmolDisabledKey = 'bundled_smol_disabled';
  static const bundledSmolFileName = 'SmolLM2-360M-Instruct-Q4_K_M.gguf';
  static const _bundledSmolAsset = 'assets/models/$bundledSmolFileName';

  /// Uses the bundled model only in a release which explicitly includes the
  /// optional asset. Public source builds omit that asset and safely return
  /// null, leaving the user-imported GGUF lane unchanged.
  Future<LocalModelRecord?> ensureBundledSmol() async {
    try {
      if (await isBundledSmolDisabled()) return null;
      final directory = await _modelsDirectory();
      final destination = File(
        '${directory.path}${Platform.pathSeparator}$bundledSmolFileName',
      );
      final data = await rootBundle.load(_bundledSmolAsset);
      if (!await destination.exists() ||
          await destination.length() != data.lengthInBytes) {
        final temporary = File('${destination.path}.installing');
        if (await temporary.exists()) await temporary.delete();
        await temporary.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        if (await destination.exists()) await destination.delete();
        await temporary.rename(destination.path);
      }
      final record = LocalModelRecord(
        id: destination.path,
        name: bundledSmolFileName,
        path: destination.path,
        bytes: await destination.length(),
      );
      final models = await load();
      if (!models.any((model) => model.id == record.id)) {
        models.add(record);
        await _save(models);
      }
      return record;
    } catch (_) {
      return null;
    }
  }

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

  Future<bool> isBundledSmolDisabled() async =>
      (await SharedPreferences.getInstance()).getBool(
        _bundledSmolDisabledKey,
      ) ??
      false;

  Future<void> removeBundledSmol() async {
    final directory = await _modelsDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}$bundledSmolFileName',
    );
    if (await file.exists()) await file.delete();
    final models = await load();
    models.removeWhere((model) => model.path == file.path);
    await _save(models);
    if (await selectedId() == file.path) await select(null);
    await (await SharedPreferences.getInstance()).setBool(
      _bundledSmolDisabledKey,
      true,
    );
  }

  Future<LocalModelRecord?> restoreBundledSmol() async {
    await (await SharedPreferences.getInstance()).remove(
      _bundledSmolDisabledKey,
    );
    return ensureBundledSmol();
  }

  /// Deletes only the app-owned GGUF directory. It deliberately leaves the
  /// documents root itself intact.
  Future<void> clearAllModels() async {
    final directory = await _modelsDirectory();
    if (await directory.exists()) await directory.delete(recursive: true);
    await (await SharedPreferences.getInstance()).remove(_modelsKey);
    await select(null);
  }

  Future<void> keepBundledSmolRemoved() async =>
      (await SharedPreferences.getInstance()).setBool(
        _bundledSmolDisabledKey,
        true,
      );

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
