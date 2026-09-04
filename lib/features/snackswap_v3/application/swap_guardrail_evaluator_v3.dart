import 'dart:math' as math;

import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapGuardrailEvaluatorV3 {
  const SwapGuardrailEvaluatorV3();

  GuardrailEvaluationV3 evaluate({
    required SwapProductV3 source,
    required SwapProductV3 candidate,
    required ComparisonBasisV3 basis,
    required SwapCalculationPolicyV3 policy,
    required String groupCode,
    required List<GuardrailV3> guardrails,
  }) {
    var penalty = 0.0;
    final regressions = <String>[];
    for (final guardrail in guardrails) {
      if (guardrail.goal != policy.goal ||
          (guardrail.groupCode != null && guardrail.groupCode != groupCode)) {
        continue;
      }
      final sourceValue = basis.sourceValue(source, guardrail.metric);
      final candidateValue = basis.candidateValue(candidate, guardrail.metric);
      if (sourceValue == null || candidateValue == null) {
        if (guardrail.required) {
          return GuardrailEvaluationV3(
            hardBlockReason:
                'required_guardrail_missing:${guardrail.metric.code}',
          );
        }
        continue;
      }
      final regression = guardrail.preferredDirection == DirectionV3.lower
          ? candidateValue - sourceValue
          : sourceValue - candidateValue;
      if (regression <= 0) continue;
      final percentage = regression /
          math.max(
            sourceValue.abs(),
            policy.floorFor(guardrail.metric) * basis.sourceMultiplier,
          ) *
          100;
      final exceedsAbsolute = guardrail.maximumRegressionAbsolute != null &&
          regression > guardrail.maximumRegressionAbsolute!;
      final exceedsPercentage = guardrail.maximumRegressionPercent != null &&
          percentage > guardrail.maximumRegressionPercent!;
      if (!exceedsAbsolute && !exceedsPercentage) continue;
      regressions.add(
        '${guardrail.metric.code}:${percentage.toStringAsFixed(1)}%',
      );
      if (guardrail.hardBlock) {
        return GuardrailEvaluationV3(
          hardBlockReason: 'hard_guardrail_failed:${guardrail.metric.code}',
          regressions: regressions,
        );
      }
      penalty += guardrail.penaltyPoints;
    }
    return GuardrailEvaluationV3(
      penalty: penalty,
      regressions: regressions,
    );
  }
}
