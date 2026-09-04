import 'dart:math' as math;

import 'package:bitewise/features/snackswap_v3/application/nutrition_delta_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapScoreComputationV3 {
  const SwapScoreComputationV3.accepted({
    required this.breakdown,
    required this.goalDelta,
  }) : rejectionReason = null;

  const SwapScoreComputationV3.rejected(this.rejectionReason)
      : breakdown = null,
        goalDelta = null;

  final String? rejectionReason;
  final SwapScoreBreakdownV3? breakdown;
  final NutritionDeltaV3? goalDelta;
  bool get isAccepted => rejectionReason == null;
}

class SwapScoreCalculatorV3 {
  const SwapScoreCalculatorV3({
    this.deltaCalculator = const NutritionDeltaCalculatorV3(),
  });

  final NutritionDeltaCalculatorV3 deltaCalculator;

  SwapScoreComputationV3 score({
    required SwapProductV3 source,
    required SwapCandidateV3 candidate,
    required ComparisonBasisV3 basis,
    required SwapCalculationPolicyV3 policy,
    required double formScore,
    required double preparationScore,
    required GuardrailEvaluationV3 guardrails,
  }) {
    NutritionDeltaV3? goalDelta;
    double goalScore;
    if (policy.goal == SwapGoalV3.bestOverall) {
      final utility = _bestOverallUtility(
        source: source,
        candidate: candidate.product,
        basis: basis,
        policy: policy,
      );
      if (utility.known < policy.minimumKnownMetrics || utility.value <= 0) {
        return const SwapScoreComputationV3.rejected(
          'insufficient_improvement',
        );
      }
      goalScore = (utility.value / 0.5 * 100).clamp(0, 100).toDouble();
    } else {
      final metric = policy.goal.metric!;
      goalDelta = deltaCalculator.calculate(
        source: source,
        candidate: candidate.product,
        basis: basis,
        metric: metric,
        direction: policy.goal.direction!,
        denominatorFloor: policy.floorFor(metric) * basis.sourceMultiplier,
      );
      if (goalDelta == null) {
        return const SwapScoreComputationV3.rejected(
          'missing_goal_nutrient',
        );
      }
      if (goalDelta.absoluteImprovement <= 0 ||
          !_passesThreshold(goalDelta, policy, candidate.relation)) {
        return const SwapScoreComputationV3.rejected(
          'insufficient_improvement',
        );
      }
      final minimumPercent = math.max(
        policy.minimumImprovementPercent,
        candidate.relation?.minimumGoalImprovementPercent ??
            policy.minimumImprovementPercent,
      );
      final span = policy.excellentImprovementPercent - minimumPercent;
      goalScore = span <= 0
          ? 100
          : ((goalDelta.percentageImprovement - minimumPercent) / span * 100)
              .clamp(0, 100)
              .toDouble();
    }

    final nutritionBalance = _nutritionBalance(
      source: source,
      candidate: candidate.product,
      basis: basis,
      policy: policy,
      primaryMetric: policy.goal.metric,
    );
    final semantic = candidate.lane == SwapLaneV3.direct
        ? 1.0
        : candidate.relation!.semanticFit.clamp(0, 1).toDouble();
    final practical = (semantic * policy.practicalWeights.semantic +
            formScore * policy.practicalWeights.form +
            preparationScore * policy.practicalWeights.preparation) *
        100;
    final comparisonQuality = basis.qualityFactor * 100;
    final dataQuality = (candidate.product.classificationConfidence * 50 +
            candidate.product.dataCompleteness.clamp(0, 1) * 30 +
            basis.qualityFactor * 20)
        .clamp(0, 100)
        .toDouble();
    final weights = policy.scoreWeights;
    final base = goalScore * weights.goal / 100 +
        nutritionBalance * weights.nutritionBalance / 100 +
        practical * weights.practicalMatch / 100 +
        comparisonQuality * weights.comparisonQuality / 100 +
        dataQuality * weights.dataQuality / 100;
    final finalScore = (base - guardrails.penalty).clamp(0, 100).toDouble();
    final requiredMinimum = math.max(
      policy.minimumScoreFor(candidate.lane),
      candidate.relation?.minimumCandidateScore ?? 0,
    );
    if (finalScore < requiredMinimum) {
      return const SwapScoreComputationV3.rejected(
        'below_min_lane_score',
      );
    }
    return SwapScoreComputationV3.accepted(
      goalDelta: goalDelta,
      breakdown: SwapScoreBreakdownV3(
        goalImprovement: goalScore,
        nutritionBalance: nutritionBalance,
        practicalMatch: practical,
        comparisonQuality: comparisonQuality,
        dataQuality: dataQuality,
        guardrailPenalty: guardrails.penalty,
        finalScore: finalScore,
      ),
    );
  }

  bool _passesThreshold(
    NutritionDeltaV3 delta,
    SwapCalculationPolicyV3 policy,
    SwapGroupRelationV3? relation,
  ) {
    final relationMinimum = relation?.minimumGoalImprovementPercent;
    if (relationMinimum != null &&
        delta.percentageImprovement < relationMinimum) {
      return false;
    }
    final minimumPercent = math.max(
      policy.minimumImprovementPercent,
      relation?.minimumGoalImprovementPercent ?? 0,
    );
    final percentageOk = delta.percentageImprovement >= minimumPercent;
    final absoluteOk = policy.minimumImprovementAbsolute != null &&
        delta.absoluteImprovement >= policy.minimumImprovementAbsolute!;
    return switch (policy.thresholdMode) {
      ThresholdModeV3.absoluteOnly => absoluteOk,
      ThresholdModeV3.percentageOnly => percentageOk,
      ThresholdModeV3.absoluteOrPercentage => absoluteOk || percentageOk,
      ThresholdModeV3.absoluteAndPercentage => absoluteOk && percentageOk,
    };
  }

  double _nutritionBalance({
    required SwapProductV3 source,
    required SwapProductV3 candidate,
    required ComparisonBasisV3 basis,
    required SwapCalculationPolicyV3 policy,
    required NutrientMetricV3? primaryMetric,
  }) {
    const directions = {
      NutrientMetricV3.energyKcal: DirectionV3.lower,
      NutrientMetricV3.sugars: DirectionV3.lower,
      NutrientMetricV3.saturatedFat: DirectionV3.lower,
      NutrientMetricV3.salt: DirectionV3.lower,
      NutrientMetricV3.protein: DirectionV3.higher,
      NutrientMetricV3.fiber: DirectionV3.higher,
    };
    var sum = 0.0;
    var known = 0;
    for (final entry in directions.entries) {
      if (entry.key == primaryMetric) continue;
      final delta = deltaCalculator.calculate(
        source: source,
        candidate: candidate,
        basis: basis,
        metric: entry.key,
        direction: entry.value,
        denominatorFloor: policy.floorFor(entry.key) * basis.sourceMultiplier,
      );
      if (delta == null) continue;
      sum += (delta.percentageImprovement / 100).clamp(-1, 1);
      known++;
    }
    final average = known == 0 ? 0 : sum / known;
    return (50 + 50 * average).clamp(0, 100).toDouble();
  }

  ({double value, int known}) _bestOverallUtility({
    required SwapProductV3 source,
    required SwapProductV3 candidate,
    required ComparisonBasisV3 basis,
    required SwapCalculationPolicyV3 policy,
  }) {
    var numerator = 0.0;
    var denominator = 0.0;
    var known = 0;
    for (final entry in policy.bestOverallWeights.entries) {
      final direction = switch (entry.key) {
        NutrientMetricV3.protein ||
        NutrientMetricV3.fiber =>
          DirectionV3.higher,
        _ => DirectionV3.lower,
      };
      final delta = deltaCalculator.calculate(
        source: source,
        candidate: candidate,
        basis: basis,
        metric: entry.key,
        direction: direction,
        denominatorFloor: policy.floorFor(entry.key) * basis.sourceMultiplier,
      );
      if (delta == null) continue;
      numerator +=
          (delta.percentageImprovement / 100).clamp(-1, 1) * entry.value;
      denominator += entry.value;
      known++;
    }
    return (
      value: denominator == 0 ? 0 : numerator / denominator,
      known: known
    );
  }
}
