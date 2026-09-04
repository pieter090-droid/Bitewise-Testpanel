import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapInputValidatorV3 {
  const SwapInputValidatorV3();

  String? validate(SwapCalculatorInputV3 input) {
    if (input.source.barcode.isEmpty) return 'invalid_source';
    if (!input.source.swapEligible ||
        input.source.classificationStatus != 'classified') {
      return 'source_not_eligible';
    }
    final minimumConfidence = input.groupPolicy.minimumProfileConfidence >
            input.policy.minimumClassificationConfidence
        ? input.groupPolicy.minimumProfileConfidence
        : input.policy.minimumClassificationConfidence;
    if (input.source.classificationConfidence < minimumConfidence) {
      return 'source_confidence_too_low';
    }
    if (!input.source.usageRoleCodes.contains(input.usageRoleCode)) {
      return 'usage_role_mismatch';
    }
    if (input.source.directSwapGroupCode == null ||
        input.source.directSwapGroupCode != input.groupPolicy.groupCode) {
      return 'missing_policy';
    }
    if ((input.policy.scoreWeights.total - 100).abs() > 0.000001 ||
        (input.policy.practicalWeights.total - 1).abs() > 0.000001) {
      return 'invalid_policy_weights';
    }
    if (input.policy.maximumResultsPerLane < 1 ||
        input.policy.minimumKnownMetrics < 1 ||
        input.policy.excellentImprovementPercent <
            input.policy.minimumImprovementPercent) {
      return 'invalid_policy';
    }
    return null;
  }
}
