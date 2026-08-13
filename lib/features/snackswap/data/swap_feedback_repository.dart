import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bitewise/core/database/app_database.dart';

class SwapFeedbackRepository {
  const SwapFeedbackRepository(this._db);

  final AppDatabase _db;

  Future<void> save({
    required String fromBarcode,
    required String toBarcode,
    required bool positive,
    required String goal,
    String? reason,
    String? note,
  }) =>
      _db.into(_db.swapFeedbacks).insert(
            SwapFeedbacksCompanion.insert(
              fromBarcode: fromBarcode,
              toBarcode: toBarcode,
              positive: positive,
              reason: Value(reason),
              note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
              goal: Value(goal),
              appVersion: const Value('0.3.0-beta.1'),
            ),
          );

  Future<String> exportJson() async {
    final rows = await _db.select(_db.swapFeedbacks).get();
    return const JsonEncoder.withIndent('  ').convert({
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'app_version': '0.3.0-beta.1',
      'privacy': 'Geen profiel, naam of gezondheidsdoelen opgenomen.',
      'feedback': [
        for (final row in rows)
          {
            'from_barcode': row.fromBarcode,
            'to_barcode': row.toBarcode,
            'positive': row.positive,
            'reason': row.reason,
            'note': row.note,
            'goal': row.goal,
            'created_at': row.createdAt.toUtc().toIso8601String(),
          },
      ],
    });
  }
}

final swapFeedbackRepositoryProvider = Provider<SwapFeedbackRepository>(
  (ref) => SwapFeedbackRepository(ref.watch(appDatabaseProvider)),
);
