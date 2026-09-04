import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bitewise/features/snackswap_v3/data/swap_candidate_repository_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

final offlineSwapCandidateRepositoryV3Provider =
    Provider<SwapCandidateRepositoryV3>(
  (_) => OfflineSwapCandidateRepositoryV3(),
);

/// Tijdelijke, read-only brug voor het testpanel. Alle data komt uit de
/// meegebouwde asset; deze repository leest of schrijft nooit naar Supabase.
class OfflineSwapCandidateRepositoryV3 implements SwapCandidateRepositoryV3 {
  OfflineSwapCandidateRepositoryV3({AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  static const _assetPath = 'assets/data/swap_dataset_v3_test.json';
  final AssetBundle _bundle;
  Future<_OfflineDatasetV3>? _datasetFuture;

  Future<_OfflineDatasetV3> _dataset() => _datasetFuture ??= _loadDataset();

  Future<_OfflineDatasetV3> _loadDataset() async {
    final json = jsonDecode(await _bundle.loadString(_assetPath))
        as Map<String, dynamic>;
    return _OfflineDatasetV3.fromJson(json);
  }

  @override
  Future<String?> primaryUsageRoleFor(String sourceBarcode) async =>
      (await _dataset()).byBarcode[sourceBarcode]?.primaryRole;

  @override
  Future<SwapCalculatorInputV3?> loadInput({
    required String sourceBarcode,
    required String usageRoleCode,
    required SwapGoalV3 goal,
  }) async {
    final dataset = await _dataset();
    final sourceRecord = dataset.byBarcode[sourceBarcode];
    if (sourceRecord == null || !sourceRecord.roles.contains(usageRoleCode)) {
      return null;
    }

    final source = sourceRecord.toProduct(usageRoleCode);
    final sourceGroup = source.directSwapGroupCode;
    if (sourceGroup == null) return null;

    final candidates = <SwapCandidateV3>[];
    final seen = <String>{sourceBarcode};
    for (final record
        in dataset.byRuntimeIdentity[sourceRecord.runtimeIdentity] ??
            const <_OfflineProductRecordV3>[]) {
      if (!record.roles.contains(usageRoleCode) || !seen.add(record.barcode)) {
        continue;
      }
      candidates.add(
        SwapCandidateV3(
          product: record.toProduct(usageRoleCode),
          lane: SwapLaneV3.direct,
        ),
      );
    }

    // Andere producttypen binnen dezelfde brede subcategorie zijn geen
    // directe swaps. Ze mogen wel als expliciet alternatief meedoen (bv.
    // cocktailsaus -> knoflooksaus), waarna alle voedingsregels nog gelden.
    for (final record in dataset.byBaseIdentity[sourceRecord.baseIdentity] ??
        const <_OfflineProductRecordV3>[]) {
      if (record.directType == sourceRecord.directType ||
          !record.roles.contains(usageRoleCode) ||
          !seen.add(record.barcode)) {
        continue;
      }
      final product = record.toProduct(usageRoleCode);
      candidates.add(
        SwapCandidateV3(
          product: product,
          lane: SwapLaneV3.compatibleAlternative,
          relation: SwapGroupRelationV3(
            sourceGroupCode: sourceGroup,
            targetGroupCode: product.directSwapGroupCode!,
            lane: SwapLaneV3.compatibleAlternative,
            usageRoleCode: usageRoleCode,
            semanticFit: 0.72,
            minimumGoalImprovementPercent: 12,
            minimumCandidateScore: 55,
          ),
        ),
      );
    }

    for (final relation
        in dataset.relationsBySourceFamily[sourceRecord.legacyFamily] ??
            const <_OfflineRelationV3>[]) {
      if (!relation.active ||
          (relation.role != null && relation.role != usageRoleCode)) {
        continue;
      }
      for (final record in dataset.byLegacyFamily[relation.targetFamily] ??
          const <_OfflineProductRecordV3>[]) {
        if (!record.roles.contains(usageRoleCode) ||
            !seen.add(record.barcode)) {
          continue;
        }
        final product = record.toProduct(usageRoleCode);
        candidates.add(
          SwapCandidateV3(
            product: product,
            lane: SwapLaneV3.compatibleAlternative,
            relation: SwapGroupRelationV3(
              sourceGroupCode: sourceGroup,
              targetGroupCode: product.directSwapGroupCode!,
              lane: SwapLaneV3.compatibleAlternative,
              usageRoleCode: usageRoleCode,
              semanticFit: relation.semanticFit,
              minimumGoalImprovementPercent: relation.minimumImprovement,
              minimumCandidateScore: relation.minimumScore,
            ),
          ),
        );
      }
    }

    return SwapCalculatorInputV3(
      source: source,
      usageRoleCode: usageRoleCode,
      candidates: candidates,
      policy: dataset.policyFor(goal),
      groupPolicy: DirectSwapGroupPolicyV3(groupCode: sourceGroup),
      guardrails: dataset.guardrails.where((g) => g.goal == goal).toList(),
      attributeRules: dataset.attributeRules,
    );
  }
}

class _OfflineDatasetV3 {
  const _OfflineDatasetV3({
    required this.byBarcode,
    required this.byRuntimeIdentity,
    required this.byBaseIdentity,
    required this.byLegacyFamily,
    required this.relationsBySourceFamily,
    required this.guardrails,
    required this.attributeRules,
    required this.defaultProfile,
    required this.policyVersion,
  });

  final Map<String, _OfflineProductRecordV3> byBarcode;
  final Map<String, List<_OfflineProductRecordV3>> byRuntimeIdentity;
  final Map<String, List<_OfflineProductRecordV3>> byBaseIdentity;
  final Map<String, List<_OfflineProductRecordV3>> byLegacyFamily;
  final Map<String, List<_OfflineRelationV3>> relationsBySourceFamily;
  final List<GuardrailV3> guardrails;
  final List<AttributeCompatibilityRuleV3> attributeRules;
  final Map<String, dynamic> defaultProfile;
  final String policyVersion;

  factory _OfflineDatasetV3.fromJson(Map<String, dynamic> json) {
    final products = (json['products'] as List)
        .map((item) => _OfflineProductRecordV3.fromJson(
              (item as Map).cast<String, dynamic>(),
            ))
        .toList(growable: false);
    final byBarcode = <String, _OfflineProductRecordV3>{};
    final byIdentity = <String, List<_OfflineProductRecordV3>>{};
    final byBaseIdentity = <String, List<_OfflineProductRecordV3>>{};
    final byFamily = <String, List<_OfflineProductRecordV3>>{};
    for (final product in products) {
      byBarcode[product.barcode] = product;
      (byIdentity[product.runtimeIdentity] ??= []).add(product);
      (byBaseIdentity[product.baseIdentity] ??= []).add(product);
      (byFamily[product.legacyFamily] ??= []).add(product);
    }

    final relations = (json['relations'] as List)
        .map((item) => _OfflineRelationV3.fromJson(
              (item as Map).cast<String, dynamic>(),
            ))
        .toList(growable: false);
    final relationsByFamily = <String, List<_OfflineRelationV3>>{};
    for (final relation in relations) {
      (relationsByFamily[relation.sourceFamily] ??= []).add(relation);
    }

    return _OfflineDatasetV3(
      byBarcode: byBarcode,
      byRuntimeIdentity: byIdentity,
      byBaseIdentity: byBaseIdentity,
      byLegacyFamily: byFamily,
      relationsBySourceFamily: relationsByFamily,
      guardrails: _parseGuardrails(json['guardrails'] as List),
      attributeRules:
          _parseAttributeRules(json['attributeCompatibility'] as List),
      defaultProfile: (json['defaultProfile'] as Map).cast<String, dynamic>(),
      policyVersion: json['policyVersion']?.toString() ?? 'policy_v3_test',
    );
  }

  SwapCalculationPolicyV3 policyFor(SwapGoalV3 goal) => SwapCalculationPolicyV3(
        goal: goal,
        policyVersion: policyVersion,
        minimumImprovementAbsolute:
            _number(defaultProfile['minimumImprovementAbsolute']),
        minimumImprovementPercent:
            _number(defaultProfile['minimumImprovementPercent']) ?? 8,
        excellentImprovementPercent:
            _number(defaultProfile['excellentImprovementPercent']) ?? 35,
        thresholdMode: _thresholdMode(
          defaultProfile['improvementThresholdMode']?.toString(),
        ),
        minimumKnownMetrics:
            (defaultProfile['minimumKnownMetrics'] as num?)?.toInt() ?? 3,
        scoreWeights: SwapScoreWeightsV3(
          goal: _number(defaultProfile['goalWeight']) ?? 45,
          nutritionBalance:
              _number(defaultProfile['nutritionBalanceWeight']) ?? 20,
          practicalMatch: _number(defaultProfile['practicalMatchWeight']) ?? 15,
          comparisonQuality:
              _number(defaultProfile['portionQualityWeight']) ?? 10,
          dataQuality: _number(defaultProfile['dataQualityWeight']) ?? 10,
        ),
        minimumDirectScore: _number(defaultProfile['minimumDirectScore']) ?? 45,
        minimumAlternativeScore:
            _number(defaultProfile['minimumAlternativeScore']) ?? 55,
        minimumSmartAlternativeScore:
            _number(defaultProfile['minimumSmartAlternativeScore']) ?? 65,
        maximumResultsPerLane:
            (defaultProfile['maximumResultsPerLane'] as num?)?.toInt() ?? 8,
      );
}

class _OfflineProductRecordV3 {
  const _OfflineProductRecordV3({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.mainCategory,
    required this.productCategory,
    required this.subcategory,
    required this.legacyFamily,
    required this.form,
    required this.preparation,
    required this.directType,
    required this.primaryRole,
    required this.roles,
    required this.confidence,
    required this.completeness,
    required this.nutrition,
    required this.portion,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String mainCategory;
  final String productCategory;
  final String subcategory;
  final String legacyFamily;
  final String form;
  final String preparation;
  final String directType;
  final String primaryRole;
  final Set<String> roles;
  final double confidence;
  final double completeness;
  final NutritionV3 nutrition;
  final PortionContextV3? portion;

  String get baseIdentity =>
      '$mainCategory::$productCategory::$subcategory::$form::$preparation';
  String get runtimeIdentity => '$baseIdentity::$directType';
  String runtimeGroup(String role) => '$runtimeIdentity::$role';

  factory _OfflineProductRecordV3.fromJson(Map<String, dynamic> json) {
    final nutrition = json['nutrition'] as List;
    final portion = json['portion'] as List?;
    return _OfflineProductRecordV3(
      barcode: json['b'].toString(),
      name: json['n']?.toString() ?? 'Onbekend product',
      brand: json['brand']?.toString(),
      mainCategory: json['main'].toString(),
      productCategory: json['cat'].toString(),
      subcategory: json['sub'].toString(),
      legacyFamily: json['family'].toString(),
      form: json['form'].toString(),
      preparation: json['prep'].toString(),
      directType: json['type']?.toString() ?? 'standard',
      primaryRole: json['primaryRole'].toString(),
      roles: (json['roles'] as List).map((v) => v.toString()).toSet(),
      confidence: _number(json['confidence']) ?? 0,
      completeness: _number(json['completeness']) ?? 0,
      nutrition: NutritionV3(
        energyKcal: _number(nutrition[0]),
        protein: _number(nutrition[1]),
        carbohydrates: _number(nutrition[2]),
        sugars: _number(nutrition[3]),
        fat: _number(nutrition[4]),
        saturatedFat: _number(nutrition[5]),
        fiber: _number(nutrition[6]),
        salt: _number(nutrition[7]),
      ),
      portion: portion == null
          ? null
          : PortionContextV3(
              value: _number(portion[0]),
              unit: _portionUnit(portion[1]?.toString()),
              confidence: _number(portion[2]) ?? 0,
              pieceWeightGrams: _number(portion[3]),
              isIndividual: portion[4] == 'individual',
            ),
    );
  }

  SwapProductV3 toProduct(String activeRole) => SwapProductV3(
        barcode: barcode,
        name: name,
        brand: brand,
        directSwapGroupCode: runtimeGroup(activeRole),
        usageRoleCodes: roles,
        primaryUsageRoleCode: primaryRole,
        productFormCode: form,
        preparationStatusCode: preparation,
        classificationStatus: 'classified',
        classificationConfidence: confidence,
        swapEligible: true,
        nutrition: nutrition,
        portionContext: portion,
        nutritionDimension: _nutritionDimension(mainCategory, form, roles),
        dataCompleteness: completeness,
      );
}

class _OfflineRelationV3 {
  const _OfflineRelationV3({
    required this.sourceFamily,
    required this.targetFamily,
    required this.role,
    required this.semanticFit,
    required this.minimumImprovement,
    required this.minimumScore,
    required this.active,
  });

  final String sourceFamily;
  final String targetFamily;
  final String? role;
  final double semanticFit;
  final double? minimumImprovement;
  final double? minimumScore;
  final bool active;

  factory _OfflineRelationV3.fromJson(Map<String, dynamic> json) =>
      _OfflineRelationV3(
        sourceFamily: json['sourceFamily'].toString(),
        targetFamily: json['targetFamily'].toString(),
        role: json['role']?.toString(),
        semanticFit: _number(json['semanticFit']) ?? 0,
        minimumImprovement: _number(json['minimumImprovement']),
        minimumScore: _number(json['minimumScore']),
        active: json['active'] == true,
      );
}

List<GuardrailV3> _parseGuardrails(List<dynamic> values) {
  final result = <GuardrailV3>[];
  for (final value in values) {
    final json = (value as Map).cast<String, dynamic>();
    final goal = _goal(json['goalCode']?.toString());
    final metric = _metric(json['nutrientCode']?.toString());
    final direction = _direction(json['preferredDirection']?.toString());
    if (goal == null || metric == null || direction == null) continue;
    result.add(GuardrailV3(
      goal: goal,
      metric: metric,
      preferredDirection: direction,
      groupCode: json['groupCode']?.toString(),
      maximumRegressionAbsolute: _number(json['maximumRegressionAbsolute']),
      maximumRegressionPercent: _number(json['maximumRegressionPct']),
      hardBlock: json['hardBlock'] != false,
      required: json['required'] == true,
      penaltyPoints: _number(json['penaltyWeight']) ?? 0,
    ));
  }
  return result;
}

List<AttributeCompatibilityRuleV3> _parseAttributeRules(List<dynamic> values) {
  final result = <AttributeCompatibilityRuleV3>[];
  for (final value in values) {
    final json = (value as Map).cast<String, dynamic>();
    if (json['sourceCode'] == '*' || json['targetCode'] == '*') continue;
    final type = switch (json['attributeType']) {
      'product_form' => AttributeTypeV3.productForm,
      'preparation_status' => AttributeTypeV3.preparationStatus,
      _ => null,
    };
    final lane = switch (json['swapLane']) {
      'compatible' => SwapLaneV3.compatibleAlternative,
      'smart' => SwapLaneV3.smartAlternative,
      'direct' => SwapLaneV3.direct,
      _ => null,
    };
    if (type == null || lane == null) continue;
    result.add(AttributeCompatibilityRuleV3(
      attributeType: type,
      sourceCode: json['sourceCode'].toString(),
      targetCode: json['targetCode'].toString(),
      lane: lane,
      usageRoleCode: json['usageRoleCode']?.toString(),
      compatibilityScore: _number(json['compatibilityScore']) ?? 0,
      isAllowed: json['isAllowed'] != false,
    ));
  }
  return result;
}

double? _number(Object? value) => value is num ? value.toDouble() : null;

PortionUnitV3? _portionUnit(String? value) => switch (value) {
      'g' => PortionUnitV3.grams,
      'ml' => PortionUnitV3.milliliters,
      'piece' => PortionUnitV3.piece,
      _ => null,
    };

NutritionDimensionV3 _nutritionDimension(
  String mainCategory,
  String form,
  Set<String> roles,
) {
  if (mainCategory == 'beverages' ||
      (form == 'liquid' &&
          (roles.contains('drink') || roles.contains('hydration')))) {
    return NutritionDimensionV3.volume;
  }
  return NutritionDimensionV3.mass;
}

ThresholdModeV3 _thresholdMode(String? value) => switch (value) {
      'absolute_only' => ThresholdModeV3.absoluteOnly,
      'percentage_only' => ThresholdModeV3.percentageOnly,
      'absolute_and_percentage' => ThresholdModeV3.absoluteAndPercentage,
      _ => ThresholdModeV3.absoluteOrPercentage,
    };

SwapGoalV3? _goal(String? value) {
  for (final goal in SwapGoalV3.values) {
    if (goal.code == value) return goal;
  }
  return null;
}

DirectionV3? _direction(String? value) => switch (value) {
      'lower' => DirectionV3.lower,
      'higher' => DirectionV3.higher,
      _ => null,
    };

NutrientMetricV3? _metric(String? value) => switch (value) {
      'energyKcalPer100' => NutrientMetricV3.energyKcal,
      'proteinGPer100' => NutrientMetricV3.protein,
      'carbohydratesGPer100' => NutrientMetricV3.carbohydrates,
      'sugarsGPer100' => NutrientMetricV3.sugars,
      'fatGPer100' => NutrientMetricV3.fat,
      'saturatedFatGPer100' => NutrientMetricV3.saturatedFat,
      'fiberGPer100' => NutrientMetricV3.fiber,
      'saltGPer100' => NutrientMetricV3.salt,
      _ => null,
    };
