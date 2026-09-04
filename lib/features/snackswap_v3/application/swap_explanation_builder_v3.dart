import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapExplanationBuilderV3 {
  const SwapExplanationBuilderV3();

  List<String> build({
    required SwapProductV3 product,
    required SwapLaneV3 lane,
    required ComparisonBasisTypeV3 comparisonBasis,
    required NutritionDeltaV3? goalDelta,
    required String usageRoleCode,
  }) {
    final result = <String>[];
    final delta = goalDelta;
    if (delta != null) {
      final direction = delta.absoluteImprovement >= 0 ? _direction(delta) : '';
      final basis = switch (comparisonBasis) {
        ComparisonBasisTypeV3.comparablePortion => 'per portie',
        ComparisonBasisTypeV3.comparableUnit => 'per stuk',
        ComparisonBasisTypeV3.per100g => 'per 100 gram',
        ComparisonBasisTypeV3.per100ml => 'per 100 milliliter',
        ComparisonBasisTypeV3.incomparable => '',
      };
      result.add(
        'Bevat ${delta.percentageImprovement.abs().toStringAsFixed(0)}% '
        '$direction ${delta.metric.labelNl} $basis.',
      );
    }
    result.add(switch (lane) {
      SwapLaneV3.direct =>
        'Dit is een directe vervanger binnen dezelfde productgroep.',
      SwapLaneV3.compatibleAlternative =>
        'Dit is een passend alternatief voor gebruik als $usageRoleCode.',
      SwapLaneV3.smartAlternative =>
        'Dit is een slim alternatief van een ander producttype.',
    });
    if (comparisonBasis == ComparisonBasisTypeV3.per100g ||
        comparisonBasis == ComparisonBasisTypeV3.per100ml) {
      result.add(
        'De vergelijking is per 100 gebaseerd omdat betrouwbare, '
        'vergelijkbare porties ontbreken.',
      );
    }
    if (product.dataCompleteness < 1) {
      result.add(
        'Deze vergelijking is beperkt omdat niet alle voedingswaarden '
        'beschikbaar zijn.',
      );
    }
    return result;
  }

  String _direction(NutritionDeltaV3 delta) => switch (delta.metric) {
        NutrientMetricV3.protein || NutrientMetricV3.fiber => 'meer',
        _ => 'minder',
      };
}
