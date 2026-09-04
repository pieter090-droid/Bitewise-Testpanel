import 'package:bitewise/features/snackswap_v3/application/comparison_basis_resolver_v3.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calculator = SwapCalculatorV3();

  SwapProductV3 product({
    required String barcode,
    String name = 'Product',
    String? group = 'whisky_sauce',
    Set<String> roles = const {'dip'},
    String? form = 'sauce',
    String? preparation = 'ready_to_eat',
    String status = 'classified',
    double confidence = 0.9,
    bool eligible = true,
    NutritionV3 nutrition = const NutritionV3(
      energyKcal: 200,
      protein: 5,
      sugars: 10,
      saturatedFat: 3,
      fiber: 2,
      salt: 1,
    ),
    PortionContextV3? portion,
    NutritionDimensionV3 dimension = NutritionDimensionV3.mass,
    double completeness = 1,
  }) =>
      SwapProductV3(
        barcode: barcode,
        name: name,
        directSwapGroupCode: group,
        usageRoleCodes: roles,
        productFormCode: form,
        preparationStatusCode: preparation,
        classificationStatus: status,
        classificationConfidence: confidence,
        swapEligible: eligible,
        nutrition: nutrition,
        portionContext: portion,
        nutritionDimension: dimension,
        dataCompleteness: completeness,
      );

  SwapCalculatorInputV3 input({
    required SwapProductV3 source,
    required List<SwapCandidateV3> candidates,
    SwapGoalV3 goal = SwapGoalV3.lessCalories,
    List<GuardrailV3> guardrails = const [],
    List<AttributeCompatibilityRuleV3> rules = const [],
    SwapCalculationPolicyV3? policy,
    DirectSwapGroupPolicyV3? groupPolicy,
  }) =>
      SwapCalculatorInputV3(
        source: source,
        usageRoleCode: 'dip',
        candidates: candidates,
        policy: policy ?? SwapCalculationPolicyV3(goal: goal),
        groupPolicy: groupPolicy ??
            DirectSwapGroupPolicyV3(groupCode: source.directSwapGroupCode!),
        guardrails: guardrails,
        attributeRules: rules,
      );

  SwapProductV3 lowerKcal(String barcode, {String? group = 'whisky_sauce'}) =>
      product(
        barcode: barcode,
        group: group,
        nutrition: const NutritionV3(
          energyKcal: 150,
          protein: 5,
          sugars: 8,
          saturatedFat: 2,
          fiber: 2,
          salt: 0.9,
        ),
      );

  test('200 naar 150 kcal is 25 procent verbetering', () {
    final source = product(barcode: '1');
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: lowerKcal('2'), lane: SwapLaneV3.direct),
        ],
      ),
    );
    expect(result.directSwaps, hasLength(1));
    expect(
      result.directSwaps.single.goalDelta!.percentageImprovement,
      closeTo(25, 0.000001),
    );
  });

  test('bronproduct kan zichzelf nooit aanbevolen krijgen', () {
    final source = product(barcode: '1');
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: source, lane: SwapLaneV3.direct),
        ],
      ),
    );
    expect(result.directSwaps, isEmpty);
    expect(result.rejectedCandidates.single.reason, 'same_product');
  });

  test('directe swap vereist exact dezelfde groep', () {
    final source = product(barcode: '1');
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: lowerKcal('2', group: 'mayonnaise'),
            lane: SwapLaneV3.direct,
          ),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'direct_group_mismatch');
  });

  test('alternatief vereist expliciete actieve en directionele relatie', () {
    final source = product(barcode: '1');
    final mayo = lowerKcal('2', group: 'mayonnaise');
    var result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: mayo,
            lane: SwapLaneV3.compatibleAlternative,
          ),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'missing_group_relation');

    const reversed = SwapGroupRelationV3(
      sourceGroupCode: 'mayonnaise',
      targetGroupCode: 'whisky_sauce',
      lane: SwapLaneV3.compatibleAlternative,
      semanticFit: 0.8,
    );
    result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: mayo,
            lane: SwapLaneV3.compatibleAlternative,
            relation: reversed,
          ),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'missing_group_relation');
  });

  test('whiskysaus toont mayo alleen via expliciete diprelatie', () {
    final source = product(barcode: '1', name: 'Whiskysaus');
    final mayo = lowerKcal('2', group: 'mayonnaise');
    const relation = SwapGroupRelationV3(
      sourceGroupCode: 'whisky_sauce',
      targetGroupCode: 'mayonnaise',
      lane: SwapLaneV3.compatibleAlternative,
      usageRoleCode: 'dip',
      semanticFit: 0.85,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: mayo,
            lane: SwapLaneV3.compatibleAlternative,
            relation: relation,
          ),
        ],
      ),
    );
    expect(result.directSwaps, isEmpty);
    expect(result.compatibleAlternatives, hasLength(1));
  });

  test('tamari zonder relatie wordt geen whiskysaus-alternatief', () {
    final source = product(barcode: '1', name: 'Whiskysaus');
    final tamari = lowerKcal('2', group: 'soy_sauce');
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: tamari,
            lane: SwapLaneV3.compatibleAlternative,
          ),
        ],
      ),
    );
    expect(result.compatibleAlternatives, isEmpty);
    expect(result.rejectedCandidates.single.reason, 'missing_group_relation');
  });

  test('Solero-achtig ijs krijgt nooit cottage cheese als directe swap', () {
    final source = product(
      barcode: '1',
      name: 'Solero',
      group: 'fruit_ice_cream_stick',
      roles: const {'dessert'},
      form: 'ice_cream_stick',
    );
    final cottage = product(
      barcode: '2',
      name: 'Cottage cheese',
      group: 'cottage_cheese',
      roles: const {'dessert'},
      form: 'scoopable',
      nutrition: const NutritionV3(energyKcal: 90),
    );
    final result = calculator.calculate(
      SwapCalculatorInputV3(
        source: source,
        usageRoleCode: 'dessert',
        candidates: [
          SwapCandidateV3(product: cottage, lane: SwapLaneV3.direct),
        ],
        policy: const SwapCalculationPolicyV3(
          goal: SwapGoalV3.lessCalories,
        ),
        groupPolicy: const DirectSwapGroupPolicyV3(
          groupCode: 'fruit_ice_cream_stick',
        ),
      ),
    );
    expect(result.directSwaps, isEmpty);
    expect(result.rejectedCandidates.single.reason, 'direct_group_mismatch');
  });

  test('review, conflict, unclassified en lage confidence worden geweigerd',
      () {
    final source = product(barcode: '1');
    final candidates = [
      product(barcode: '2', status: 'review_required'),
      product(barcode: '3', status: 'conflict'),
      product(barcode: '4', status: 'unclassified'),
      product(barcode: '5', confidence: 0.7),
    ].map(
      (p) => SwapCandidateV3(product: p, lane: SwapLaneV3.direct),
    );
    final result = calculator.calculate(
      input(source: source, candidates: candidates.toList()),
    );
    expect(result.directSwaps, isEmpty);
    expect(
      result.rejectedCandidates.map((r) => r.reason),
      containsAll(['classification_not_approved', 'confidence_too_low']),
    );
  });

  test('onbekende of afwijkende vorm faalt gesloten', () {
    final source = product(barcode: '1');
    final candidate = lowerKcal('2');
    final unknown = product(
      barcode: candidate.barcode,
      nutrition: candidate.nutrition,
      form: null,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: unknown, lane: SwapLaneV3.direct),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'form_incompatible');
  });

  test('expliciete compatibiliteitsregel kan vorm toestaan', () {
    final source = product(barcode: '1');
    final candidate = product(
      barcode: '2',
      form: 'spread',
      nutrition: lowerKcal('x').nutrition,
    );
    const rule = AttributeCompatibilityRuleV3(
      attributeType: AttributeTypeV3.productForm,
      sourceCode: 'sauce',
      targetCode: 'spread',
      lane: SwapLaneV3.direct,
      compatibilityScore: 0.7,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        ],
        rules: const [rule],
        groupPolicy: const DirectSwapGroupPolicyV3(
          groupCode: 'whisky_sauce',
          formPolicy: CompatibilityPolicyV3.compatible,
        ),
      ),
    );
    expect(result.directSwaps, hasLength(1));
  });

  test('gram en milliliter zijn zonder dichtheid onvergelijkbaar', () {
    final source = product(barcode: '1');
    final candidate = product(
      barcode: '2',
      dimension: NutritionDimensionV3.volume,
      nutrition: lowerKcal('x').nutrition,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'incomparable_basis');
  });

  test('stukvergelijking gebruikt stukgewicht en niet het aantal stuks', () {
    const resolver = ComparisonBasisResolverV3();
    final source = product(
      barcode: '1',
      portion: const PortionContextV3(
        value: 1,
        unit: PortionUnitV3.piece,
        confidence: 0.9,
        pieceWeightGrams: 50,
        isIndividual: true,
      ),
    );
    final candidate = product(
      barcode: '2',
      portion: const PortionContextV3(
        value: 1,
        unit: PortionUnitV3.piece,
        confidence: 0.9,
        pieceWeightGrams: 80,
        isIndividual: true,
      ),
    );
    final basis = resolver.resolve(
      source: source,
      candidate: candidate,
      policy: const SwapCalculationPolicyV3(
        goal: SwapGoalV3.lessCalories,
      ),
      groupPolicy: const DirectSwapGroupPolicyV3(
        groupCode: 'whisky_sauce',
      ),
    );
    expect(basis.type, ComparisonBasisTypeV3.comparableUnit);
    expect(basis.sourceMultiplier, 0.5);
    expect(basis.candidateMultiplier, 0.8);
  });

  test('ontbrekende primaire doelwaarde is nooit nul', () {
    final source = product(barcode: '1');
    final candidate = product(
      barcode: '2',
      nutrition: const NutritionV3(protein: 5),
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'missing_goal_nutrient');
  });

  test('harde guardrail kan doelverbetering blokkeren', () {
    final source = product(barcode: '1');
    final candidate = product(
      barcode: '2',
      nutrition: const NutritionV3(
        energyKcal: 150,
        sugars: 20,
        protein: 5,
        saturatedFat: 3,
        fiber: 2,
        salt: 1,
      ),
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        ],
        guardrails: const [
          GuardrailV3(
            goal: SwapGoalV3.lessCalories,
            metric: NutrientMetricV3.sugars,
            preferredDirection: DirectionV3.lower,
            maximumRegressionPercent: 25,
          ),
        ],
      ),
    );
    expect(
      result.rejectedCandidates.single.reason,
      'hard_guardrail_failed:sugars_g',
    );
  });

  test('required onbekende guardrailwaarde blokkeert', () {
    final source = product(
      barcode: '1',
      nutrition: const NutritionV3(energyKcal: 200),
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: lowerKcal('2'), lane: SwapLaneV3.direct),
        ],
        guardrails: const [
          GuardrailV3(
            goal: SwapGoalV3.lessCalories,
            metric: NutrientMetricV3.protein,
            preferredDirection: DirectionV3.higher,
            required: true,
          ),
        ],
      ),
    );
    expect(
      result.rejectedCandidates.single.reason,
      'required_guardrail_missing:protein_g',
    );
  });

  test('direct en alternatief blijven twee afzonderlijke lijsten', () {
    final source = product(barcode: '1');
    final direct = lowerKcal('2');
    final alternative = product(
      barcode: '3',
      group: 'mayonnaise',
      nutrition: const NutritionV3(
        energyKcal: 80,
        protein: 6,
        sugars: 2,
        saturatedFat: 1,
        fiber: 3,
        salt: 0.5,
      ),
    );
    const relation = SwapGroupRelationV3(
      sourceGroupCode: 'whisky_sauce',
      targetGroupCode: 'mayonnaise',
      lane: SwapLaneV3.compatibleAlternative,
      semanticFit: 1,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(product: direct, lane: SwapLaneV3.direct),
          SwapCandidateV3(
            product: alternative,
            lane: SwapLaneV3.compatibleAlternative,
            relation: relation,
          ),
        ],
      ),
    );
    expect(result.directSwaps.single.product.barcode, '2');
    expect(result.compatibleAlternatives.single.product.barcode, '3');
  });

  test('ongeldige gewichten stoppen fail-closed', () {
    final source = product(barcode: '1');
    final result = calculator.calculate(
      input(
        source: source,
        candidates: const [],
        policy: const SwapCalculationPolicyV3(
          goal: SwapGoalV3.lessCalories,
          scoreWeights: SwapScoreWeightsV3(goal: 40),
        ),
      ),
    );
    expect(result.error, 'invalid_policy_weights');
  });

  test('nul geldige kandidaten geeft gecontroleerde empty-state', () {
    final result = calculator.calculate(
      input(source: product(barcode: '1'), candidates: const []),
    );
    expect(result.error, isNull);
    expect(result.warnings, contains('no_valid_candidates'));
  });

  test('ranking is deterministisch en dedupliceert op barcode', () {
    final source = product(barcode: '1');
    final candidate = lowerKcal('2');
    final calculatorInput = input(
      source: source,
      candidates: [
        SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        SwapCandidateV3(product: candidate, lane: SwapLaneV3.direct),
        SwapCandidateV3(product: lowerKcal('3'), lane: SwapLaneV3.direct),
      ],
    );
    final first = calculator.calculate(calculatorInput);
    final second = calculator.calculate(calculatorInput);
    expect(first.directSwaps, hasLength(2));
    expect(
      first.directSwaps.map((r) => r.product.barcode),
      second.directSwaps.map((r) => r.product.barcode),
    );
  });

  test('bron moet zelf eligible en voldoende betrouwbaar zijn', () {
    final result = calculator.calculate(
      input(
        source: product(barcode: '1', eligible: false),
        candidates: const [],
      ),
    );
    expect(result.error, 'source_not_eligible');

    final lowConfidence = calculator.calculate(
      input(
        source: product(barcode: '1', confidence: 0.79),
        candidates: const [],
      ),
    );
    expect(lowConfidence.error, 'source_confidence_too_low');
  });

  test('product uit dezelfde groep kan niet als alternatief worden vermomd',
      () {
    final source = product(barcode: '1');
    const relation = SwapGroupRelationV3(
      sourceGroupCode: 'whisky_sauce',
      targetGroupCode: 'whisky_sauce',
      lane: SwapLaneV3.compatibleAlternative,
      semanticFit: 1,
    );
    final result = calculator.calculate(
      input(
        source: source,
        candidates: [
          SwapCandidateV3(
            product: lowerKcal('2'),
            lane: SwapLaneV3.compatibleAlternative,
            relation: relation,
          ),
        ],
      ),
    );
    expect(result.rejectedCandidates.single.reason, 'wrong_swap_lane');
  });

  test('expliciete per-100-basis is geen fallback en mag fallback uitzetten',
      () {
    const resolver = ComparisonBasisResolverV3();
    final basis = resolver.resolve(
      source: product(barcode: '1'),
      candidate: lowerKcal('2'),
      policy: const SwapCalculationPolicyV3(
        goal: SwapGoalV3.lessCalories,
      ),
      groupPolicy: const DirectSwapGroupPolicyV3(
        groupCode: 'whisky_sauce',
        comparisonPreference: GroupComparisonPreferenceV3.per100g,
        allowPer100Fallback: false,
      ),
    );
    expect(basis.type, ComparisonBasisTypeV3.per100g);
  });
}
