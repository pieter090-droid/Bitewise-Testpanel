import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bitewise/core/config/feature_flags.dart';
import 'package:bitewise/features/snackswap/application/swap_score_calculator.dart';
import 'package:bitewise/features/snackswap/data/snackswap_service.dart';
import 'package:bitewise/features/snackswap/domain/product_features.dart';
import 'package:bitewise/features/snackswap/domain/swap_score_result.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/data/offline_swap_candidate_repository_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';
import 'package:bitewise/features/tracker/application/tracker_providers.dart';
import 'package:bitewise/features/tracker/domain/day_log.dart';

/// Rule-based aanbevelingsengine op basis van `product_features_resolved`.
/// Draait volledig lokaal
/// (geen AI-aanroep).
sealed class RuleBasedSwapOutcome {
  const RuleBasedSwapOutcome();
}

/// Het bronproduct is nog niet als swap-relevant/AI-verrijkt gemarkeerd, of
/// er zijn geen kandidaten binnen hetzelfde cluster/categorie gevonden.
class RuleBasedSwapNotFound extends RuleBasedSwapOutcome {
  const RuleBasedSwapNotFound();
}

class RuleBasedSwapError extends RuleBasedSwapOutcome {
  const RuleBasedSwapError(this.message);
  final String message;
}

class RuleBasedSwapFound extends RuleBasedSwapOutcome {
  const RuleBasedSwapFound(
      this.groups, this.allRanked, this.source, this.configs);
  final List<SwapRecommendationGroup> groups;

  /// Volledige, ongecapte, op score gesorteerde kandidatenlijst (incl. de
  /// cross-familie "Andere opties"-kandidaten) -- gebruikt door het
  /// categoriefilter op het scherm om [buildRecommendationGroups] opnieuw
  /// aan te roepen, geschaald naar één `snack_type`, los van de vaste
  /// 5-per-groep-limiet van [groups].
  final List<SwapScoreResult> allRanked;
  final SwapCandidate source;
  final List<Map<String, dynamic>> configs;
}

class SwapRecommendationGroup {
  const SwapRecommendationGroup({
    required this.slug,
    required this.label,
    required this.results,
  });
  final String slug;
  final String label;
  final List<SwapScoreResult> results;
}

/// Vertaalt het onboarding-doel naar het SwapGoal dat de calculator kent.
/// Leest een boolean-feature op naam voor lokale UI-groepering.
/// Onbekende kolomnaam -> null.
bool? _boolForColumn(ProductFeatures f, String? column) => switch (column) {
      'is_low_sugar' => f.isLowSugar,
      'is_high_protein' => f.isHighProtein,
      'is_low_kcal' => f.isLowKcal,
      'is_high_fiber' => f.isHighFiber,
      'is_less_processed' => f.isLessProcessed,
      _ => null,
    };

/// Bevestigt dat de kandidaat ook daadwerkelijk BETER is dan het bronproduct
/// op dit specifieke punt -- niet alleen absoluut "laag"/"hoog" op zichzelf.
///
/// Bug gevonden: "Minder kcal" toonde eerder kandidaten die zelf onder de
/// vaste drempel (bv. 150 kcal/100g) zaten, ook als het bronproduct fors
/// minder kcal had (bv. 80). De groepsnaam belooft een vergelijking t.o.v.
/// het bronproduct -- die vergelijking ontbrak volledig. Onbekend (een van
/// beide null) = kan niet bevestigen = hoort niet in deze groep, ook al is
/// de absolute vlag toevallig waar.
bool _relativeImprovement(
    String? column, SwapCandidate source, SwapCandidate candidate) {
  switch (column) {
    case 'is_low_sugar':
      final s = source.sugar100, c = candidate.sugar100;
      return s != null && c != null && c < s;
    case 'is_high_protein':
      final s = source.protein100, c = candidate.protein100;
      return s != null && c != null && c > s;
    case 'is_low_kcal':
      final s = source.kcal100, c = candidate.kcal100;
      return s != null && c != null && c < s;
    case 'is_less_processed':
      final s = source.features.processingQualityScore,
          c = candidate.features.processingQualityScore;
      return s != null && c != null && c > s;
    default:
      return true;
  }
}

/// Groepeert een (eventueel al op categorie gefilterde) kandidatenlijst
/// volgens een lokale UI-config -- Minder kcal/Meer eiwit/Minder suiker/
/// Overall, elk relatief t.o.v. [source] (zie
/// [_relativeImprovement]). Herbruikbaar: de hoofdweergave gebruikt dit met
/// de volledige kandidatenpool en limiet 5; het categoriefilter op het
/// scherm roept dit opnieuw aan met alleen kandidaten van één `snack_type`
/// en een ruimere limiet (bv. 10), zodat "Minder kcal binnen Zuivel" enz.
/// niet beperkt blijft tot wat toevallig in de top-5-overall zat.
List<SwapRecommendationGroup> buildRecommendationGroups({
  required List<Map<String, dynamic>> configs,
  required SwapCandidate source,
  required List<SwapScoreResult> ranked,
  int perGroupLimit = 5,
}) {
  final groups = <SwapRecommendationGroup>[];
  for (final config in configs) {
    final column = config['rule_column'] as String?;
    final tag = config['rule_swap_tag'] as String?;
    final direction = config['rule_direction'] as String?;

    List<SwapScoreResult> matches;
    if (column == null && tag == null && direction == null) {
      matches = ranked; // "Overall betere suggestie" = de algehele ranking.
    } else {
      matches = ranked.where((r) {
        if (column != null &&
            _boolForColumn(r.candidate.features, column) == true &&
            _relativeImprovement(column, source, r.candidate)) {
          return true;
        }
        if (tag != null && r.candidate.features.swapTags.contains(tag)) {
          return true;
        }
        if (direction != null &&
            r.candidate.features.recommendedSwapDirections
                .contains(direction)) {
          return true;
        }
        return false;
      }).toList();
    }
    if (matches.isEmpty) continue;
    groups.add(SwapRecommendationGroup(
      slug: config['slug'] as String,
      label: config['label'] as String,
      results: matches.take(perGroupLimit).toList(),
    ));
  }
  return groups;
}

const List<Map<String, dynamic>> fallbackGroupConfigs = [
  {'slug': 'minder_kcal', 'label': 'Minder kcal', 'rule_column': 'is_low_kcal'},
  {
    'slug': 'meer_eiwit',
    'label': 'Meer eiwit',
    'rule_column': 'is_high_protein'
  },
  {
    'slug': 'minder_suiker',
    'label': 'Minder suiker',
    'rule_column': 'is_low_sugar'
  },
  {'slug': 'beste_keuze_vandaag', 'label': 'Overall betere suggestie'},
];

SwapDayContext swapDayContextFromSummary(DailySummary summary) =>
    SwapDayContext(
      dailyKcalUsed: summary.kcal,
      dailyKcalGoal: summary.calorieTarget.toDouble(),
      dailySugarUsed: summary.sugar,
      dailySugarGoal: summary.sugarLimit.toDouble(),
      dailyProteinUsed: summary.protein,
      dailyProteinGoal: summary.proteinTarget.toDouble(),
      // De huidige tracker logt nog geen vezels. Bewust null laten: de
      // calculator behandelt dit onderdeel neutraal en verzint geen data.
      dailyFiberUsed: null,
      dailyFiberGoal: null,
    );

/// Berekent en groepeert swap-aanbevelingen voor een gescand product.
final ruleBasedSwapProvider = FutureProvider.family<
    RuleBasedSwapOutcome,
    ({
      String barcode,
      SwapGoal goal,
      bool useDayContext
    })>((ref, request) async {
  if (FeatureFlags.swapEngineV3Enabled) {
    return _loadOfflineV3Outcome(ref, request);
  }

  final service = ref.watch(snackSwapServiceProvider);
  final barcode = request.barcode;

  final source = await service.getCandidateByBarcode(barcode);
  if (source == null || !source.features.isSwapRelevant) {
    return const RuleBasedSwapNotFound();
  }

  final candidates = await service.getCandidatesForCluster(
    excludeBarcode: source.barcode,
    swapFamily: source.features.swapFamily,
    snackType: source.features.snackType,
    categoryCluster: source.features.categoryCluster,
    fallbackCategory: source.category,
    goal: request.goal,
    goalSourceValue: switch (request.goal) {
      SwapGoal.minderKcal => source.kcal100,
      SwapGoal.minderSuiker => source.sugar100,
      SwapGoal.meerEiwit => source.protein100,
      SwapGoal.besteOverall => null,
    },
  );
  if (candidates.isEmpty) return const RuleBasedSwapNotFound();

  final goal = request.goal;
  final dayContext = request.useDayContext
      ? swapDayContextFromSummary(ref.watch(dailySummaryProvider))
      : const SwapDayContext();

  final calculator = SwapScoreCalculator();
  final ranked = calculator.rankCandidates(
    source: source,
    candidates: candidates,
    goal: goal,
    dayContext: dayContext,
  );
  if (ranked.isEmpty) return const RuleBasedSwapNotFound();

  final configs = [
    {'slug': goal.value, 'label': goal.label},
  ];
  final groups = <SwapRecommendationGroup>[
    SwapRecommendationGroup(
      slug: 'directe_swaps',
      label: 'Directe swaps',
      results: ranked.take(5).toList(),
    ),
  ];

  // "Andere opties": bewust cross-familie (bv. chocopasta -> smeerkaas of
  // pindakaas), primair via de expliciete `related_families`-lijst uit
  // swap_family_mapping (bron van waarheid). Zonder expliciete relatie wordt
  // geen los product-form-vangnet meer gebruikt.
  var otherOptions = <SwapScoreResult>[];
  final sourceForm = source.features.productForm;
  final sourceFamily = source.features.swapFamily;
  if (sourceForm != null && sourceForm.isNotEmpty) {
    final relatedFamilies = sourceFamily != null && sourceFamily.isNotEmpty
        ? await service.getRelatedFamilies(sourceFamily)
        : const <String>[];
    final otherFormCandidates = await service.getCandidatesForOtherForm(
      excludeBarcode: source.barcode,
      productForm: sourceForm,
      relatedFamilies: relatedFamilies,
      excludeSwapFamily: sourceFamily,
    );
    otherOptions = otherFormCandidates
        .map((c) => calculator.scoreCrossForm(
            source: source, candidate: c, goal: goal, dayContext: dayContext))
        .where((r) => !r.isExcluded)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    if (otherOptions.isNotEmpty) {
      groups.add(SwapRecommendationGroup(
        slug: 'andere_opties',
        label: 'Andere opties',
        results: otherOptions.take(3).toList(),
      ));
    }
  }

  if (groups.isEmpty) return const RuleBasedSwapNotFound();

  // Volledige lijst voor het categoriefilter: hoofdranking + cross-familie
  // opties, gededupliceerd op barcode, opnieuw op score gesorteerd.
  final seen = <String>{};
  final allRanked = [...ranked, ...otherOptions]
      .where((r) => seen.add(r.candidate.barcode))
      .toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  return RuleBasedSwapFound(groups, allRanked, source, configs);
});

Future<RuleBasedSwapOutcome> _loadOfflineV3Outcome(
  Ref ref,
  ({String barcode, SwapGoal goal, bool useDayContext}) request,
) async {
  try {
    final repository = ref.read(offlineSwapCandidateRepositoryV3Provider);
    final role = await repository.primaryUsageRoleFor(request.barcode);
    if (role == null) return const RuleBasedSwapNotFound();

    final goal = _goalV3(request.goal);
    final input = await repository.loadInput(
      sourceBarcode: request.barcode,
      usageRoleCode: role,
      goal: goal,
    );
    if (input == null) return const RuleBasedSwapNotFound();

    final result = const SwapCalculatorV3().calculate(input);
    if (result.error != null) return RuleBasedSwapError(result.error!);

    List<SwapScoreResult> convert(List<SwapRecommendationV3> values) =>
        values.map(_legacyResultFromV3).toList(growable: false);

    final direct = convert(result.directSwaps);
    final compatible = convert(result.compatibleAlternatives);
    final smart = convert(result.smartAlternatives);
    if (direct.isEmpty && compatible.isEmpty && smart.isEmpty) {
      return const RuleBasedSwapNotFound();
    }

    final groups = <SwapRecommendationGroup>[
      if (direct.isNotEmpty)
        SwapRecommendationGroup(
          slug: 'directe_swaps_v3',
          label: 'Directe swaps',
          results: direct,
        ),
      if (compatible.isNotEmpty)
        SwapRecommendationGroup(
          slug: 'alternatieven_v3',
          label: 'Passende alternatieven',
          results: compatible,
        ),
      if (smart.isNotEmpty)
        SwapRecommendationGroup(
          slug: 'slimme_alternatieven_v3',
          label: 'Slimme alternatieven',
          results: smart,
        ),
    ];
    final seen = <String>{};
    final allRanked = [...direct, ...compatible, ...smart]
        .where((item) => seen.add(item.candidate.barcode))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    final configs = [
      {'slug': request.goal.value, 'label': request.goal.label},
    ];
    return RuleBasedSwapFound(
      groups,
      allRanked,
      _legacyProductFromV3(input.source),
      configs,
    );
  } catch (error) {
    return RuleBasedSwapError('v3_test_data_error:$error');
  }
}

SwapGoalV3 _goalV3(SwapGoal goal) => switch (goal) {
      SwapGoal.meerEiwit => SwapGoalV3.moreProtein,
      SwapGoal.minderKcal => SwapGoalV3.lessCalories,
      SwapGoal.minderSuiker => SwapGoalV3.lessSugar,
      SwapGoal.besteOverall => SwapGoalV3.bestOverall,
    };

SwapScoreResult _legacyResultFromV3(SwapRecommendationV3 result) =>
    SwapScoreResult(
      candidate: _legacyProductFromV3(result.product),
      score: result.score.finalScore,
      goalMatch: result.score.goalImprovement,
      nutritionImprovement: result.score.nutritionBalance,
      dayContext: 0,
      similarity: result.score.practicalMatch,
      processingQuality: result.score.comparisonQuality,
      dataQuality: result.score.dataQuality,
      reasons: result.explanation,
      reasonCodes: [
        switch (result.comparisonBasis) {
          ComparisonBasisTypeV3.comparablePortion => 'per portie',
          ComparisonBasisTypeV3.comparableUnit => 'per stuk',
          ComparisonBasisTypeV3.per100g => 'per 100 g',
          ComparisonBasisTypeV3.per100ml => 'per 100 ml',
          ComparisonBasisTypeV3.incomparable => 'niet vergelijkbaar',
        },
      ],
    );

SwapCandidate _legacyProductFromV3(SwapProductV3 product) => SwapCandidate(
      barcode: product.barcode,
      name: product.name,
      brand: product.brand,
      kcal100: product.nutrition.energyKcal,
      sugar100: product.nutrition.sugars,
      protein100: product.nutrition.protein,
      fat100: product.nutrition.fat,
      carbs100: product.nutrition.carbohydrates,
      fiber100: product.nutrition.fiber,
      salt100: product.nutrition.salt,
      saturatedFat100: product.nutrition.saturatedFat,
      completeness: product.dataCompleteness,
      features: ProductFeatures(
        barcode: product.barcode,
        classificationStatus: product.classificationStatus,
        categoryCluster: _runtimeGroupPart(product.directSwapGroupCode, 0),
        snackType: _runtimeGroupPart(product.directSwapGroupCode, 2),
        swapFamily: product.directSwapGroupCode,
        productForm: product.productFormCode,
        consumptionMode: product.preparationStatusCode,
        usageContext: product.usageRoleCodes.toList(growable: false),
        isDrink: product.nutritionDimension == NutritionDimensionV3.volume,
        dataQualityScore: product.dataCompleteness * 100,
        aiConfidence: product.classificationConfidence,
        isSwapRelevant: product.swapEligible,
      ),
    );

String? _runtimeGroupPart(String? group, int index) {
  final parts = group?.split('::');
  return parts != null && parts.length > index ? parts[index] : null;
}
