import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class ComparisonBasisResolverV3 {
  const ComparisonBasisResolverV3();

  ComparisonBasisV3 resolve({
    required SwapProductV3 source,
    required SwapProductV3 candidate,
    required SwapCalculationPolicyV3 policy,
    required DirectSwapGroupPolicyV3 groupPolicy,
  }) {
    final sourcePortion = source.portionContext;
    final candidatePortion = candidate.portionContext;

    if (groupPolicy.comparisonPreference ==
            GroupComparisonPreferenceV3.portion &&
        _reliable(sourcePortion, policy) &&
        _reliable(candidatePortion, policy) &&
        sourcePortion!.unit == candidatePortion!.unit &&
        sourcePortion.unit != PortionUnitV3.piece &&
        _unitMatchesDimension(sourcePortion.unit!, source.nutritionDimension) &&
        _unitMatchesDimension(
          candidatePortion.unit!,
          candidate.nutritionDimension,
        )) {
      return ComparisonBasisV3(
        type: ComparisonBasisTypeV3.comparablePortion,
        sourceMultiplier: sourcePortion.value! / 100,
        candidateMultiplier: candidatePortion.value! / 100,
        qualityFactor: 1,
      );
    }

    final sourcePiece = sourcePortion?.pieceWeightGrams;
    final candidatePiece = candidatePortion?.pieceWeightGrams;
    if ((groupPolicy.comparisonPreference ==
                GroupComparisonPreferenceV3.portion ||
            groupPolicy.comparisonPreference ==
                GroupComparisonPreferenceV3.unit) &&
        sourcePiece != null &&
        candidatePiece != null &&
        sourcePiece > 0 &&
        candidatePiece > 0 &&
        sourcePortion!.confidence >= policy.minimumPortionConfidence &&
        candidatePortion!.confidence >= policy.minimumPortionConfidence &&
        sourcePortion.isIndividual &&
        candidatePortion.isIndividual &&
        source.nutritionDimension == NutritionDimensionV3.mass &&
        candidate.nutritionDimension == NutritionDimensionV3.mass) {
      return ComparisonBasisV3(
        type: ComparisonBasisTypeV3.comparableUnit,
        sourceMultiplier: sourcePiece / 100,
        candidateMultiplier: candidatePiece / 100,
        qualityFactor: 0.9,
      );
    }

    final explicitlyPer100 = groupPolicy.comparisonPreference ==
            GroupComparisonPreferenceV3.per100g ||
        groupPolicy.comparisonPreference ==
            GroupComparisonPreferenceV3.per100ml;
    if ((!explicitlyPer100 && !groupPolicy.allowPer100Fallback) ||
        source.nutritionDimension != candidate.nutritionDimension) {
      return const ComparisonBasisV3.incomparable();
    }
    final requiredDimension = switch (groupPolicy.comparisonPreference) {
      GroupComparisonPreferenceV3.per100g => NutritionDimensionV3.mass,
      GroupComparisonPreferenceV3.per100ml => NutritionDimensionV3.volume,
      _ => source.nutritionDimension,
    };
    if (source.nutritionDimension != requiredDimension) {
      return const ComparisonBasisV3.incomparable();
    }
    return switch (requiredDimension) {
      NutritionDimensionV3.mass => const ComparisonBasisV3(
          type: ComparisonBasisTypeV3.per100g,
          sourceMultiplier: 1,
          candidateMultiplier: 1,
          qualityFactor: 0.75,
        ),
      NutritionDimensionV3.volume => const ComparisonBasisV3(
          type: ComparisonBasisTypeV3.per100ml,
          sourceMultiplier: 1,
          candidateMultiplier: 1,
          qualityFactor: 0.75,
        ),
      NutritionDimensionV3.unknown => const ComparisonBasisV3.incomparable(),
    };
  }

  bool _reliable(
    PortionContextV3? portion,
    SwapCalculationPolicyV3 policy,
  ) =>
      portion?.value != null &&
      portion!.value! > 0 &&
      portion.unit != null &&
      portion.confidence >= policy.minimumPortionConfidence;

  bool _unitMatchesDimension(
    PortionUnitV3 unit,
    NutritionDimensionV3 dimension,
  ) =>
      (unit == PortionUnitV3.grams && dimension == NutritionDimensionV3.mass) ||
      (unit == PortionUnitV3.milliliters &&
          dimension == NutritionDimensionV3.volume);
}
