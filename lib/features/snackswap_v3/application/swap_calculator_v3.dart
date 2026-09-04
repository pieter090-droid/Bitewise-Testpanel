import 'package:bitewise/features/snackswap_v3/application/candidate_eligibility_policy_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/comparison_basis_resolver_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_explanation_builder_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_guardrail_evaluator_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_input_validator_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_result_ranker_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_score_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapCalculatorV3 {
  const SwapCalculatorV3({
    this.inputValidator = const SwapInputValidatorV3(),
    this.eligibilityPolicy = const CandidateEligibilityPolicyV3(),
    this.basisResolver = const ComparisonBasisResolverV3(),
    this.guardrailEvaluator = const SwapGuardrailEvaluatorV3(),
    this.scoreCalculator = const SwapScoreCalculatorV3(),
    this.explanationBuilder = const SwapExplanationBuilderV3(),
    this.ranker = const SwapResultRankerV3(),
  });

  final SwapInputValidatorV3 inputValidator;
  final CandidateEligibilityPolicyV3 eligibilityPolicy;
  final ComparisonBasisResolverV3 basisResolver;
  final SwapGuardrailEvaluatorV3 guardrailEvaluator;
  final SwapScoreCalculatorV3 scoreCalculator;
  final SwapExplanationBuilderV3 explanationBuilder;
  final SwapResultRankerV3 ranker;

  SwapCalculationResultV3 calculate(SwapCalculatorInputV3 input) {
    final validationError = inputValidator.validate(input);
    if (validationError != null) {
      return _result(input,
          error: validationError, warnings: [validationError]);
    }

    final accepted = <SwapLaneV3, List<SwapRecommendationV3>>{
      for (final lane in SwapLaneV3.values) lane: [],
    };
    final rejected = <RejectedCandidateV3>[];

    for (final candidate in input.candidates) {
      final eligibility = eligibilityPolicy.evaluate(
        source: input.source,
        candidate: candidate,
        usageRoleCode: input.usageRoleCode,
        policy: input.policy,
        groupPolicy: input.groupPolicy,
        attributeRules: input.attributeRules,
      );
      if (!eligibility.isAllowed) {
        rejected.add(
          RejectedCandidateV3(
            barcode: candidate.product.barcode,
            lane: candidate.lane,
            reason: eligibility.rejectionReason!,
          ),
        );
        continue;
      }

      final basis = basisResolver.resolve(
        source: input.source,
        candidate: candidate.product,
        policy: input.policy,
        groupPolicy: input.groupPolicy,
      );
      if (basis.type == ComparisonBasisTypeV3.incomparable) {
        rejected.add(
          RejectedCandidateV3(
            barcode: candidate.product.barcode,
            lane: candidate.lane,
            reason: 'incomparable_basis',
          ),
        );
        continue;
      }

      final guardrails = guardrailEvaluator.evaluate(
        source: input.source,
        candidate: candidate.product,
        basis: basis,
        policy: input.policy,
        groupCode: input.groupPolicy.groupCode,
        guardrails: input.guardrails,
      );
      if (guardrails.isBlocked) {
        rejected.add(
          RejectedCandidateV3(
            barcode: candidate.product.barcode,
            lane: candidate.lane,
            reason: guardrails.hardBlockReason!,
          ),
        );
        continue;
      }

      final score = scoreCalculator.score(
        source: input.source,
        candidate: candidate,
        basis: basis,
        policy: input.policy,
        formScore: eligibility.formScore,
        preparationScore: eligibility.preparationScore,
        guardrails: guardrails,
      );
      if (!score.isAccepted) {
        rejected.add(
          RejectedCandidateV3(
            barcode: candidate.product.barcode,
            lane: candidate.lane,
            reason: score.rejectionReason!,
          ),
        );
        continue;
      }
      final explanation = explanationBuilder.build(
        product: candidate.product,
        lane: candidate.lane,
        comparisonBasis: basis.type,
        goalDelta: score.goalDelta,
        usageRoleCode: input.usageRoleCode,
      );
      accepted[candidate.lane]!.add(
        SwapRecommendationV3(
          product: candidate.product,
          lane: candidate.lane,
          score: score.breakdown!,
          comparisonBasis: basis.type,
          goalDelta: score.goalDelta,
          regressions: guardrails.regressions,
          explanation: explanation,
        ),
      );
    }

    final direct = ranker.rank(
      accepted[SwapLaneV3.direct]!,
      input.policy.maximumResultsPerLane,
    );
    final alternatives = ranker.rank(
      accepted[SwapLaneV3.compatibleAlternative]!,
      input.policy.maximumResultsPerLane,
    );
    final smart = ranker.rank(
      accepted[SwapLaneV3.smartAlternative]!,
      input.policy.maximumResultsPerLane,
    );
    final warnings = <String>[];
    if (direct.isEmpty && alternatives.isEmpty && smart.isEmpty) {
      warnings.add('no_valid_candidates');
    }
    return _result(
      input,
      direct: direct,
      alternatives: alternatives,
      smart: smart,
      rejected: rejected,
      warnings: warnings,
    );
  }

  SwapCalculationResultV3 _result(
    SwapCalculatorInputV3 input, {
    List<SwapRecommendationV3> direct = const [],
    List<SwapRecommendationV3> alternatives = const [],
    List<SwapRecommendationV3> smart = const [],
    List<RejectedCandidateV3> rejected = const [],
    List<String> warnings = const [],
    String? error,
  }) =>
      SwapCalculationResultV3(
        engineVersion: input.policy.engineVersion,
        policyVersion: input.policy.policyVersion,
        sourceBarcode: input.source.barcode,
        goal: input.policy.goal,
        usageRoleCode: input.usageRoleCode,
        directSwaps: direct,
        compatibleAlternatives: alternatives,
        smartAlternatives: smart,
        rejectedCandidates: rejected,
        warnings: warnings,
        error: error,
      );
}
