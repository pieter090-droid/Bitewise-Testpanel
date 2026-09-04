enum SwapGoalV3 {
  lessCalories('less_calories', NutrientMetricV3.energyKcal, DirectionV3.lower),
  lessSugar('less_sugar', NutrientMetricV3.sugars, DirectionV3.lower),
  lessSaturatedFat(
    'less_saturated_fat',
    NutrientMetricV3.saturatedFat,
    DirectionV3.lower,
  ),
  lessSalt('less_salt', NutrientMetricV3.salt, DirectionV3.lower),
  moreProtein('more_protein', NutrientMetricV3.protein, DirectionV3.higher),
  moreFiber('more_fiber', NutrientMetricV3.fiber, DirectionV3.higher),
  bestOverall('best_overall', null, null);

  const SwapGoalV3(this.code, this.metric, this.direction);
  final String code;
  final NutrientMetricV3? metric;
  final DirectionV3? direction;
}

enum NutrientMetricV3 {
  energyKcal('energy_kcal', 'calorieën', 'kcal'),
  protein('protein_g', 'eiwit', 'g'),
  carbohydrates('carbohydrates_g', 'koolhydraten', 'g'),
  sugars('sugars_g', 'suiker', 'g'),
  fat('fat_g', 'vet', 'g'),
  saturatedFat('saturated_fat_g', 'verzadigd vet', 'g'),
  fiber('fiber_g', 'vezels', 'g'),
  salt('salt_g', 'zout', 'g');

  const NutrientMetricV3(this.code, this.labelNl, this.unit);
  final String code;
  final String labelNl;
  final String unit;
}

enum DirectionV3 { lower, higher }

enum SwapLaneV3 { direct, compatibleAlternative, smartAlternative }

enum ComparisonBasisTypeV3 {
  comparablePortion,
  comparableUnit,
  per100g,
  per100ml,
  incomparable,
}

enum GroupComparisonPreferenceV3 { portion, unit, per100g, per100ml }

enum NutritionDimensionV3 { mass, volume, unknown }

enum PortionUnitV3 { grams, milliliters, piece }

enum ThresholdModeV3 {
  absoluteOnly,
  percentageOnly,
  absoluteOrPercentage,
  absoluteAndPercentage,
}

enum AttributeTypeV3 { productForm, preparationStatus }

class NutritionV3 {
  const NutritionV3({
    this.energyKcal,
    this.protein,
    this.carbohydrates,
    this.sugars,
    this.fat,
    this.saturatedFat,
    this.fiber,
    this.salt,
  });

  final double? energyKcal;
  final double? protein;
  final double? carbohydrates;
  final double? sugars;
  final double? fat;
  final double? saturatedFat;
  final double? fiber;
  final double? salt;

  double? value(NutrientMetricV3 metric) => switch (metric) {
        NutrientMetricV3.energyKcal => energyKcal,
        NutrientMetricV3.protein => protein,
        NutrientMetricV3.carbohydrates => carbohydrates,
        NutrientMetricV3.sugars => sugars,
        NutrientMetricV3.fat => fat,
        NutrientMetricV3.saturatedFat => saturatedFat,
        NutrientMetricV3.fiber => fiber,
        NutrientMetricV3.salt => salt,
      };
}

class PortionContextV3 {
  const PortionContextV3({
    this.value,
    this.unit,
    this.confidence = 0,
    this.pieceWeightGrams,
    this.isIndividual = false,
  });

  final double? value;
  final PortionUnitV3? unit;
  final double confidence;
  final double? pieceWeightGrams;
  final bool isIndividual;
}

class SwapProductV3 {
  const SwapProductV3({
    required this.barcode,
    required this.name,
    required this.directSwapGroupCode,
    required this.usageRoleCodes,
    required this.productFormCode,
    required this.preparationStatusCode,
    required this.classificationStatus,
    required this.classificationConfidence,
    required this.swapEligible,
    required this.nutrition,
    this.brand,
    this.primaryUsageRoleCode,
    this.portionContext,
    this.nutritionDimension = NutritionDimensionV3.mass,
    this.dataCompleteness = 0,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String? directSwapGroupCode;
  final Set<String> usageRoleCodes;
  final String? primaryUsageRoleCode;
  final String? productFormCode;
  final String? preparationStatusCode;
  final String classificationStatus;
  final double classificationConfidence;
  final bool swapEligible;
  final NutritionV3 nutrition;
  final PortionContextV3? portionContext;
  final NutritionDimensionV3 nutritionDimension;
  final double dataCompleteness;
}

class DirectSwapGroupPolicyV3 {
  const DirectSwapGroupPolicyV3({
    required this.groupCode,
    this.minimumProfileConfidence = 0.8,
    this.comparisonPreference = GroupComparisonPreferenceV3.portion,
    this.formPolicy = CompatibilityPolicyV3.exact,
    this.preparationPolicy = CompatibilityPolicyV3.exact,
    this.allowPer100Fallback = true,
  });

  final String groupCode;
  final double minimumProfileConfidence;
  final GroupComparisonPreferenceV3 comparisonPreference;
  final CompatibilityPolicyV3 formPolicy;
  final CompatibilityPolicyV3 preparationPolicy;
  final bool allowPer100Fallback;
}

enum CompatibilityPolicyV3 { exact, compatible, ignore }

class SwapGroupRelationV3 {
  const SwapGroupRelationV3({
    required this.sourceGroupCode,
    required this.targetGroupCode,
    required this.lane,
    required this.semanticFit,
    this.usageRoleCode,
    this.minimumGoalImprovementPercent,
    this.minimumCandidateScore,
    this.isActive = true,
  });

  final String sourceGroupCode;
  final String targetGroupCode;
  final SwapLaneV3 lane;
  final String? usageRoleCode;
  final double semanticFit;
  final double? minimumGoalImprovementPercent;
  final double? minimumCandidateScore;
  final bool isActive;
}

class AttributeCompatibilityRuleV3 {
  const AttributeCompatibilityRuleV3({
    required this.attributeType,
    required this.sourceCode,
    required this.targetCode,
    required this.lane,
    required this.compatibilityScore,
    this.usageRoleCode,
    this.isAllowed = true,
    this.isActive = true,
  });

  final AttributeTypeV3 attributeType;
  final String sourceCode;
  final String targetCode;
  final SwapLaneV3 lane;
  final String? usageRoleCode;
  final double compatibilityScore;
  final bool isAllowed;
  final bool isActive;
}

class GuardrailV3 {
  const GuardrailV3({
    required this.goal,
    required this.metric,
    required this.preferredDirection,
    this.groupCode,
    this.maximumRegressionAbsolute,
    this.maximumRegressionPercent,
    this.hardBlock = true,
    this.required = false,
    this.penaltyPoints = 0,
  });

  final String? groupCode;
  final SwapGoalV3 goal;
  final NutrientMetricV3 metric;
  final DirectionV3 preferredDirection;
  final double? maximumRegressionAbsolute;
  final double? maximumRegressionPercent;
  final bool hardBlock;
  final bool required;
  final double penaltyPoints;
}

class SwapScoreWeightsV3 {
  const SwapScoreWeightsV3({
    this.goal = 45,
    this.nutritionBalance = 20,
    this.practicalMatch = 15,
    this.comparisonQuality = 10,
    this.dataQuality = 10,
  });

  final double goal;
  final double nutritionBalance;
  final double practicalMatch;
  final double comparisonQuality;
  final double dataQuality;

  double get total =>
      goal +
      nutritionBalance +
      practicalMatch +
      comparisonQuality +
      dataQuality;
}

class PracticalWeightsV3 {
  const PracticalWeightsV3({
    this.semantic = 0.5,
    this.form = 0.3,
    this.preparation = 0.2,
  });

  final double semantic;
  final double form;
  final double preparation;
  double get total => semantic + form + preparation;
}

class SwapCalculationPolicyV3 {
  const SwapCalculationPolicyV3({
    required this.goal,
    this.engineVersion = 'swap_engine_v3',
    this.policyVersion = 'policy_v3_1',
    this.minimumClassificationConfidence = 0.8,
    this.minimumPortionConfidence = 0.7,
    this.minimumImprovementAbsolute,
    this.minimumImprovementPercent = 8,
    this.excellentImprovementPercent = 35,
    this.thresholdMode = ThresholdModeV3.percentageOnly,
    this.minimumKnownMetrics = 3,
    this.scoreWeights = const SwapScoreWeightsV3(),
    this.practicalWeights = const PracticalWeightsV3(),
    this.minimumDirectScore = 45,
    this.minimumAlternativeScore = 55,
    this.minimumSmartAlternativeScore = 65,
    this.maximumResultsPerLane = 8,
    this.bestOverallWeights = const {
      NutrientMetricV3.energyKcal: 0.30,
      NutrientMetricV3.sugars: 0.25,
      NutrientMetricV3.saturatedFat: 0.20,
      NutrientMetricV3.salt: 0.10,
      NutrientMetricV3.protein: 0.10,
      NutrientMetricV3.fiber: 0.05,
    },
    this.denominatorFloors = const {
      NutrientMetricV3.energyKcal: 50,
      NutrientMetricV3.sugars: 1,
      NutrientMetricV3.saturatedFat: 0.5,
      NutrientMetricV3.salt: 0.1,
      NutrientMetricV3.protein: 2,
      NutrientMetricV3.fiber: 1,
      NutrientMetricV3.carbohydrates: 5,
      NutrientMetricV3.fat: 3,
    },
  });

  final SwapGoalV3 goal;
  final String engineVersion;
  final String policyVersion;
  final double minimumClassificationConfidence;
  final double minimumPortionConfidence;
  final double? minimumImprovementAbsolute;
  final double minimumImprovementPercent;
  final double excellentImprovementPercent;
  final ThresholdModeV3 thresholdMode;
  final int minimumKnownMetrics;
  final SwapScoreWeightsV3 scoreWeights;
  final PracticalWeightsV3 practicalWeights;
  final double minimumDirectScore;
  final double minimumAlternativeScore;
  final double minimumSmartAlternativeScore;
  final int maximumResultsPerLane;
  final Map<NutrientMetricV3, double> bestOverallWeights;
  final Map<NutrientMetricV3, double> denominatorFloors;

  double floorFor(NutrientMetricV3 metric) => denominatorFloors[metric] ?? 1;

  double minimumScoreFor(SwapLaneV3 lane) => switch (lane) {
        SwapLaneV3.direct => minimumDirectScore,
        SwapLaneV3.compatibleAlternative => minimumAlternativeScore,
        SwapLaneV3.smartAlternative => minimumSmartAlternativeScore,
      };
}

class SwapCandidateV3 {
  const SwapCandidateV3(
      {required this.product, required this.lane, this.relation});
  final SwapProductV3 product;
  final SwapLaneV3 lane;
  final SwapGroupRelationV3? relation;
}

class SwapCalculatorInputV3 {
  const SwapCalculatorInputV3({
    required this.source,
    required this.usageRoleCode,
    required this.candidates,
    required this.policy,
    required this.groupPolicy,
    this.guardrails = const [],
    this.attributeRules = const [],
  });

  final SwapProductV3 source;
  final String usageRoleCode;
  final List<SwapCandidateV3> candidates;
  final SwapCalculationPolicyV3 policy;
  final DirectSwapGroupPolicyV3 groupPolicy;
  final List<GuardrailV3> guardrails;
  final List<AttributeCompatibilityRuleV3> attributeRules;
}

class ComparisonBasisV3 {
  const ComparisonBasisV3({
    required this.type,
    required this.sourceMultiplier,
    required this.candidateMultiplier,
    required this.qualityFactor,
  });

  const ComparisonBasisV3.incomparable()
      : type = ComparisonBasisTypeV3.incomparable,
        sourceMultiplier = 0,
        candidateMultiplier = 0,
        qualityFactor = 0;

  final ComparisonBasisTypeV3 type;
  final double sourceMultiplier;
  final double candidateMultiplier;
  final double qualityFactor;

  double? sourceValue(SwapProductV3 p, NutrientMetricV3 metric) {
    final value = p.nutrition.value(metric);
    return value == null ? null : value * sourceMultiplier;
  }

  double? candidateValue(SwapProductV3 p, NutrientMetricV3 metric) {
    final value = p.nutrition.value(metric);
    return value == null ? null : value * candidateMultiplier;
  }
}

class NutritionDeltaV3 {
  const NutritionDeltaV3({
    required this.metric,
    required this.sourceValue,
    required this.candidateValue,
    required this.absoluteImprovement,
    required this.percentageImprovement,
  });

  final NutrientMetricV3 metric;
  final double sourceValue;
  final double candidateValue;
  final double absoluteImprovement;
  final double percentageImprovement;
}

class GuardrailEvaluationV3 {
  const GuardrailEvaluationV3({
    this.hardBlockReason,
    this.penalty = 0,
    this.regressions = const [],
  });

  final String? hardBlockReason;
  final double penalty;
  final List<String> regressions;
  bool get isBlocked => hardBlockReason != null;
}

class SwapScoreBreakdownV3 {
  const SwapScoreBreakdownV3({
    required this.goalImprovement,
    required this.nutritionBalance,
    required this.practicalMatch,
    required this.comparisonQuality,
    required this.dataQuality,
    required this.guardrailPenalty,
    required this.finalScore,
  });

  final double goalImprovement;
  final double nutritionBalance;
  final double practicalMatch;
  final double comparisonQuality;
  final double dataQuality;
  final double guardrailPenalty;
  final double finalScore;
}

class SwapRecommendationV3 {
  const SwapRecommendationV3({
    required this.product,
    required this.lane,
    required this.score,
    required this.comparisonBasis,
    required this.explanation,
    this.goalDelta,
    this.regressions = const [],
  });

  final SwapProductV3 product;
  final SwapLaneV3 lane;
  final SwapScoreBreakdownV3 score;
  final ComparisonBasisTypeV3 comparisonBasis;
  final NutritionDeltaV3? goalDelta;
  final List<String> regressions;
  final List<String> explanation;
}

class RejectedCandidateV3 {
  const RejectedCandidateV3(
      {required this.barcode, required this.lane, required this.reason});
  final String barcode;
  final SwapLaneV3 lane;
  final String reason;
}

class SwapCalculationResultV3 {
  const SwapCalculationResultV3({
    required this.engineVersion,
    required this.policyVersion,
    required this.sourceBarcode,
    required this.goal,
    required this.usageRoleCode,
    this.directSwaps = const [],
    this.compatibleAlternatives = const [],
    this.smartAlternatives = const [],
    this.rejectedCandidates = const [],
    this.warnings = const [],
    this.error,
  });

  final String engineVersion;
  final String policyVersion;
  final String sourceBarcode;
  final SwapGoalV3 goal;
  final String usageRoleCode;
  final List<SwapRecommendationV3> directSwaps;
  final List<SwapRecommendationV3> compatibleAlternatives;
  final List<SwapRecommendationV3> smartAlternatives;
  final List<RejectedCandidateV3> rejectedCandidates;
  final List<String> warnings;
  final String? error;
}
