import 'package:flutter_test/flutter_test.dart';

import 'package:bitewise/features/snackswap_v3/application/swap_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/data/offline_swap_candidate_repository_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfflineSwapCandidateRepositoryV3', () {
    final repository = OfflineSwapCandidateRepositoryV3();

    test('laadt de primaire gebruiksrol uit de meegebouwde dataset', () async {
      expect(await repository.primaryUsageRoleFor('00006550'), 'bread_topping');
      expect(await repository.primaryUsageRoleFor('bestaat-niet'), isNull);
    });

    test('bouwt directe kandidaten uitsluitend uit dezelfde v3-identiteit',
        () async {
      final input = await repository.loadInput(
        sourceBarcode: '00006550',
        usageRoleCode: 'bread_topping',
        goal: SwapGoalV3.lessCalories,
      );

      expect(input, isNotNull);
      final direct = input!.candidates
          .where((candidate) => candidate.lane == SwapLaneV3.direct)
          .toList();
      expect(direct, isNotEmpty);
      expect(
        direct.every((candidate) =>
            candidate.product.barcode != input.source.barcode &&
            candidate.product.directSwapGroupCode ==
                input.source.directSwapGroupCode &&
            candidate.product.usageRoleCodes.contains('bread_topping')),
        isTrue,
      );
    });

    test('alternatieven hebben altijd een expliciete directionele relatie',
        () async {
      final input = await repository.loadInput(
        sourceBarcode: '00006550',
        usageRoleCode: 'bread_topping',
        goal: SwapGoalV3.bestOverall,
      );

      expect(input, isNotNull);
      final alternatives = input!.candidates.where(
        (candidate) => candidate.lane == SwapLaneV3.compatibleAlternative,
      );
      for (final candidate in alternatives) {
        expect(candidate.relation, isNotNull);
        expect(candidate.relation!.sourceGroupCode,
            input.source.directSwapGroupCode);
        expect(candidate.relation!.targetGroupCode,
            candidate.product.directSwapGroupCode);
        expect(candidate.relation!.usageRoleCode, 'bread_topping');
      }
    });

    test('calculator lekt geen product naar de verkeerde lane', () async {
      final input = await repository.loadInput(
        sourceBarcode: '8718452804955',
        usageRoleCode: 'sauce',
        goal: SwapGoalV3.lessCalories,
      );

      expect(input, isNotNull);
      expect(input!.source.directSwapGroupCode, contains('cocktail_sauce'));
      final inputDirect = input.candidates
          .where((item) => item.lane == SwapLaneV3.direct)
          .toList();
      expect(inputDirect, isNotEmpty);
      expect(
        inputDirect.every((item) {
          final name = item.product.name.toLowerCase();
          return name.contains('cocktail') ||
              name.contains('whisky') ||
              name.contains('whiskey');
        }),
        isTrue,
      );
      final result = const SwapCalculatorV3().calculate(input);
      expect(result.error, isNull);
      expect(
        result.directSwaps.every((item) =>
            item.product.directSwapGroupCode ==
            input.source.directSwapGroupCode),
        isTrue,
      );
      expect(
        result.compatibleAlternatives.every((item) =>
            item.product.directSwapGroupCode !=
            input.source.directSwapGroupCode),
        isTrue,
      );
      expect(
        [
          ...result.directSwaps,
          ...result.compatibleAlternatives,
          ...result.smartAlternatives,
        ].any((item) => item.product.barcode == input.source.barcode),
        isFalse,
      );
    });
  });
}
