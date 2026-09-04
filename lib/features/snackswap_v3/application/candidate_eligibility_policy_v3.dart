import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class CandidateEligibilityResultV3 {
  const CandidateEligibilityResultV3.allowed({
    required this.formScore,
    required this.preparationScore,
  }) : rejectionReason = null;

  const CandidateEligibilityResultV3.rejected(this.rejectionReason)
      : formScore = 0,
        preparationScore = 0;

  final String? rejectionReason;
  final double formScore;
  final double preparationScore;
  bool get isAllowed => rejectionReason == null;
}

class CandidateEligibilityPolicyV3 {
  const CandidateEligibilityPolicyV3();

  CandidateEligibilityResultV3 evaluate({
    required SwapProductV3 source,
    required SwapCandidateV3 candidate,
    required String usageRoleCode,
    required SwapCalculationPolicyV3 policy,
    required DirectSwapGroupPolicyV3 groupPolicy,
    required List<AttributeCompatibilityRuleV3> attributeRules,
  }) {
    final product = candidate.product;
    if (product.barcode == source.barcode) {
      return const CandidateEligibilityResultV3.rejected('same_product');
    }
    if (!product.swapEligible) {
      return const CandidateEligibilityResultV3.rejected(
        'candidate_not_eligible',
      );
    }
    if (product.classificationStatus != 'classified') {
      return const CandidateEligibilityResultV3.rejected(
        'classification_not_approved',
      );
    }
    final minimumConfidence = groupPolicy.minimumProfileConfidence >
            policy.minimumClassificationConfidence
        ? groupPolicy.minimumProfileConfidence
        : policy.minimumClassificationConfidence;
    if (product.classificationConfidence < minimumConfidence) {
      return const CandidateEligibilityResultV3.rejected('confidence_too_low');
    }
    if (!product.usageRoleCodes.contains(usageRoleCode)) {
      return const CandidateEligibilityResultV3.rejected(
        'usage_role_mismatch',
      );
    }

    if (candidate.lane == SwapLaneV3.direct) {
      if (product.directSwapGroupCode != source.directSwapGroupCode) {
        return const CandidateEligibilityResultV3.rejected(
          'direct_group_mismatch',
        );
      }
    } else {
      final relation = candidate.relation;
      if (product.directSwapGroupCode == source.directSwapGroupCode) {
        return const CandidateEligibilityResultV3.rejected('wrong_swap_lane');
      }
      if (relation == null ||
          !relation.isActive ||
          relation.lane != candidate.lane ||
          relation.sourceGroupCode != source.directSwapGroupCode ||
          relation.targetGroupCode != product.directSwapGroupCode) {
        return const CandidateEligibilityResultV3.rejected(
          'missing_group_relation',
        );
      }
      if (relation.usageRoleCode != null &&
          relation.usageRoleCode != usageRoleCode) {
        return const CandidateEligibilityResultV3.rejected(
          'usage_role_mismatch',
        );
      }
    }

    final form = _attributeScore(
      type: AttributeTypeV3.productForm,
      sourceCode: source.productFormCode,
      targetCode: product.productFormCode,
      lane: candidate.lane,
      usageRoleCode: usageRoleCode,
      groupPolicy: groupPolicy.formPolicy,
      rules: attributeRules,
    );
    if (form == null) {
      return const CandidateEligibilityResultV3.rejected(
        'form_incompatible',
      );
    }
    final preparation = _attributeScore(
      type: AttributeTypeV3.preparationStatus,
      sourceCode: source.preparationStatusCode,
      targetCode: product.preparationStatusCode,
      lane: candidate.lane,
      usageRoleCode: usageRoleCode,
      groupPolicy: groupPolicy.preparationPolicy,
      rules: attributeRules,
    );
    if (preparation == null) {
      return const CandidateEligibilityResultV3.rejected(
        'preparation_incompatible',
      );
    }
    return CandidateEligibilityResultV3.allowed(
      formScore: form,
      preparationScore: preparation,
    );
  }

  double? _attributeScore({
    required AttributeTypeV3 type,
    required String? sourceCode,
    required String? targetCode,
    required SwapLaneV3 lane,
    required String usageRoleCode,
    required CompatibilityPolicyV3 groupPolicy,
    required List<AttributeCompatibilityRuleV3> rules,
  }) {
    if (sourceCode == null || targetCode == null) return null;
    if (sourceCode == targetCode) return 1;
    if (lane == SwapLaneV3.direct) {
      if (groupPolicy == CompatibilityPolicyV3.ignore) return 1;
      if (groupPolicy == CompatibilityPolicyV3.exact) return null;
    }
    for (final rule in rules) {
      if (rule.attributeType == type &&
          rule.sourceCode == sourceCode &&
          rule.targetCode == targetCode &&
          rule.lane == lane &&
          rule.isActive &&
          rule.isAllowed &&
          (rule.usageRoleCode == null || rule.usageRoleCode == usageRoleCode)) {
        return rule.compatibilityScore.clamp(0, 1).toDouble();
      }
    }
    return null;
  }
}
