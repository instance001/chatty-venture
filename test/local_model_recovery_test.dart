import 'dart:convert';
import 'dart:io';

import 'package:chatty_venture/core/storage/local_model_store.dart';
import 'package:chatty_venture/features/adventure/adventure_controller.dart';
import 'package:chatty_venture/features/adventure/adventure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a broken model list does not interrupt adventure startup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bundled_smol_disabled': true,
      'local_gguf_models': '[{',
    });
    final game = AdventureController();
    addTearDown(game.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AdventureScreen(
          controller: game,
          darkMode: false,
          onToggleTheme: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  test(
    'usable imported models survive a damaged neighbouring record',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'venture-model-list',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/kept.gguf').writeAsBytes([1]);
      final good = {
        'id': 'kept',
        'name': 'kept.gguf',
        'path': file.path,
        'bytes': 1,
      };
      SharedPreferences.setMockInitialValues({
        'local_gguf_models': jsonEncode([
          null,
          {...good, 'bytes': {}},
          good,
        ]),
      });
      final models = await LocalModelStore().load();
      expect(models.map((model) => model.id), ['kept']);
      expect(await file.exists(), isTrue);
    },
  );
}
