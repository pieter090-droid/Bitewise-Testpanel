import 'dart:math' as math;

import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class NutritionDeltaCalculatorV3 {
  const NutritionDeltaCalculatorV3();

  NutritionDeltaV3? calculate({
    required SwapProductV3 source,
    required SwapProductV3 candidate,
    required ComparisonBasisV3 basis,
    required NutrientMetricV3 metric,
    required DirectionV3 direction,
    required double denominatorFloor,
  }) {
    final sourceValue = basis.sourceValue(source, metric);
    final candidateValue = basis.candidateValue(candidate, metric);
    if (sourceValue == null || candidateValue == null) return null;
    final absolute = direction == DirectionV3.lower
        ? sourceValue - candidateValue
        : candidateValue - sourceValue;
    final denominator = math.max(sourceValue.abs(), denominatorFloor);
    return NutritionDeltaV3(
      metric: metric,
      sourceValue: sourceValue,
      candidateValue: candidateValue,
      absoluteImprovement: absolute,
      percentageImprovement: absolute / denominator * 100,
    );
  }
}
