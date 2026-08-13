import 'dart:convert';

import 'package:bitewise/core/database/app_database.dart';
import 'package:bitewise/features/snackswap/data/swap_feedback_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SwapFeedbackRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SwapFeedbackRepository(database);
  });

  tearDown(() => database.close());

  test('feedback wordt lokaal bewaard en privacyvriendelijk geëxporteerd',
      () async {
    await repository.save(
      fromBarcode: 'solero',
      toBarcode: 'cottage-cheese',
      positive: false,
      reason: 'ander_type',
      note: 'Dit is geen vergelijkbaar product.',
      goal: 'meer_eiwit',
    );

    final export = jsonDecode(await repository.exportJson())
        as Map<String, dynamic>;
    final feedback = (export['feedback'] as List).single
        as Map<String, dynamic>;

    expect(feedback['from_barcode'], 'solero');
    expect(feedback['to_barcode'], 'cottage-cheese');
    expect(feedback['positive'], isFalse);
    expect(feedback['reason'], 'ander_type');
    expect(feedback['goal'], 'meer_eiwit');
    expect(export.containsKey('profile'), isFalse);
    expect(export.containsKey('email'), isFalse);
  });
}
