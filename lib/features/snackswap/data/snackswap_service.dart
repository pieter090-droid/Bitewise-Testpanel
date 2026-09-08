import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bitewise/core/constants/app_constants.dart';
import 'package:bitewise/core/supabase/supabase_service.dart';
import 'package:bitewise/features/snackswap/application/product_search_ranker.dart';
import 'package:bitewise/features/snackswap/domain/product_features.dart';
import 'package:bitewise/features/snackswap/domain/snack_product.dart';
import 'package:bitewise/features/snackswap/domain/swap_score_result.dart';
import 'package:bitewise/features/snackswap_v3/data/offline_swap_candidate_repository_v3.dart';

// --- Resultaattypes met duidelijke, aparte statussen ---

sealed class LookupOutcome {
  const LookupOutcome();
}

/// Product gevonden.
class LookupFound extends LookupOutcome {
  const LookupFound(this.product);
  final SnackProduct product;
}

/// Backend antwoordde netjes met `found: false`.
class LookupNotFound extends LookupOutcome {
  const LookupNotFound();
}

/// Netwerk-, config- of onverwachte fout (met leesbare melding).
class LookupError extends LookupOutcome {
  const LookupError(this.message);
  final String message;
}

/// Leest bekende v3-producten eerst uit de meegebouwde offline catalogus.
///
/// - Onbekende barcodes vallen terug op de Supabase Edge Function.
/// - Roept nooit Open Food Facts direct aan (dat doet de Edge Function).
/// - Gebruikt alleen de publishable (anon) key; nooit een service_role key.
class SnackSwapService {
  SnackSwapService(
    this._supabase, {
    OfflineSwapCandidateRepositoryV3? offlineCatalog,
  }) : _offlineCatalog = offlineCatalog;

  final SupabaseService _supabase;
  final OfflineSwapCandidateRepositoryV3? _offlineCatalog;
  static const _resolvedProductView = 'product_features_resolved';
  static const _resolvedProductColumns = '''
barcode,name,brand,image_url,category,
kcal_100g,sugar_100g,protein_100g,fat_100g,carbs_100g,fiber_100g,salt_100g,saturated_fat_100g,
nova_group,nutriscore_grade,nutriscore_score,additives_n,
completeness,states_tags,serving_quantity,serving_size,kcal_serving,proteins_serving,sugars_serving,
fiber_serving,salt_serving,saturated_fat_serving,allergens,
swap_family,classification_status,is_swap_relevant,category_cluster,snack_type,product_form,consumption_mode,
secondary_consumption_modes,usage_context,taste_profile,texture_profile,use_moment,swap_tags,recommended_swap_directions,
processing_quality_score,data_quality_score,ai_confidence,is_sweet,is_salty,is_drink,is_dairy,is_chocolate,is_crunchy,
is_less_processed,has_sweeteners,has_palm_oil,ingredient_count
''';

  /// Basale barcode-validatie (EAN/UPC): alleen cijfers, 8–14 tekens.
  static bool isValidBarcode(String input) {
    final trimmed = input.trim();
    return RegExp(r'^\d{8,14}$').hasMatch(trimmed);
  }

  Future<LookupOutcome> lookupProduct(String barcode) async {
    final trimmed = barcode.replaceAll(RegExp(r'\D'), '');

    // De meegebouwde v3-set is de primaire bron voor de pitch-bèta. Dit is
    // dezelfde data die de swapengine gebruikt, dus productdetail en swap
    // kunnen niet meer door twee verschillende lookups uit elkaar lopen.
    try {
      final offline = await _offlineCatalog?.lookupProduct(trimmed);
      if (offline != null) return LookupFound(offline);
    } catch (_) {
      // Een beschadigde lokale asset mag de bestaande online fallback niet
      // blokkeren. De v3-swaproute rapporteert zo'n assetfout afzonderlijk.
    }

    if (!_supabase.isAvailable) {
      return const LookupError(
        'Geen backend geconfigureerd. Vul je Supabase-key in assets/env/env.json.',
      );
    }

    try {
      final response = await _supabase.client.functions.invoke(
        AppConstants.fnLookupProduct,
        body: {'barcode': trimmed},
      );

      final data = response.data;
      if (data is! Map) {
        return const LookupError('Onverwacht antwoord van de server.');
      }
      final map = data.cast<String, dynamic>();

      final found = map['found'] == true;
      final product = map['product'];
      if (!found || product == null) {
        return const LookupNotFound();
      }

      return LookupFound(
        SnackProduct.fromJson(
          (product as Map).cast<String, dynamic>(),
          source: map['source'] as String?,
        ),
      );
    } catch (e) {
      return LookupError(_friendly(e));
    }
  }

  /// Zoekt read-only op naam, merk en categorie en rangschikt lokaal op
  /// relevantie. De database wordt hierbij niet gewijzigd.
  Future<List<SnackProduct>> searchProducts(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];

    // Bekende pitchproducten blijven ook bij een trage of ontbrekende
    // internetverbinding direct vindbaar. De ranker zet exacte productnamen
    // en producttypes boven toevallige deelmatches.
    try {
      final offline = await _offlineCatalog?.searchProducts(q) ?? const [];
      if (offline.isNotEmpty) return ProductSearchRanker.rank(q, offline);
    } catch (_) {
      // Vang terug op de bestaande online zoeklaag.
    }

    if (!_supabase.isAvailable) return const [];
    try {
      const columns = 'barcode,name,brand,image_url,categories_tags,'
          'kcal_100g,sugar_100g,protein_100g,fat_100g,carbs_100g,'
          'classification_status,is_swap_relevant,swap_family';
      final terms = ProductSearchRanker.searchTerms(q);
      final normalized = ProductSearchRanker.normalize(q);

      Future<List<dynamic>> safeQuery(String filter, int limit) async {
        try {
          final rows = await _supabase.client
              .from(_resolvedProductView)
              .select(columns)
              .or(filter)
              .limit(limit);
          return rows as List;
        } catch (_) {
          return const [];
        }
      }

      // Eerst expliciete naam/merk-matches ophalen. De brede zoeklaag erna
      // zorgt voor categorieën en synoniemen, zonder dat een willekeurige
      // databasevolgorde de beste matches buiten de eerste 60 duwt.
      final requests = <Future<List<dynamic>>>[
        safeQuery(
          'name.ilike.$normalized,brand.ilike.$normalized',
          20,
        ),
        safeQuery(
          'name.ilike.$normalized%,brand.ilike.$normalized%',
          80,
        ),
        ...terms.map(
          (term) => safeQuery(
            'name.ilike.%$term%,brand.ilike.%$term%,'
            'categories_tags.ilike.%$term%',
            term == normalized ? 120 : 50,
          ),
        ),
      ];
      final responses = await Future.wait(requests);
      final products = responses.expand((rows) => rows.map(
            (row) => SnackProduct.fromJson(
              (row as Map).cast<String, dynamic>(),
            ),
          ));
      return ProductSearchRanker.rank(q, products);
    } catch (_) {
      return const [];
    }
  }

  // --- Rule-based SwapScore-engine ---
  //
  // Puur lezen; geen AI-aanroep. Zie SwapScoreCalculator voor de berekening
  // en product_features_resolved voor de schone Supabase-inputlaag.

  /// Bron- of kandidaatproduct incl. afgeleide features, in één query.
  Future<SwapCandidate?> getCandidateByBarcode(String barcode) async {
    if (!_supabase.isAvailable) return null;
    try {
      final rows = await _supabase.client
          .from(_resolvedProductView)
          .select(_resolvedProductColumns)
          .eq('barcode', barcode.trim())
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return null;
      return SwapCandidate.fromJoinedJson(
        (list.first as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Kandidaten van hetzelfde product-type, gesorteerd op datakwaliteit.
  ///
  /// Volgorde (fijn -> grof, stopt zodra er genoeg kandidaten zijn):
  ///  1. `swap_family` (bv. "chocolate_spreads" vs. "chocolate_confectionery"
  ///     -- onderscheidt vorm/gebruik, niet alleen smaak; regelgebaseerd
  ///     gevuld, ~34% dekking, dus vaak nog leeg).
  ///  2. `snack_type` (bv. "snoep", "chocolade", "zuivel_toetje" -- ~22
  ///     waarden, de daadwerkelijke productsoort).
  ///  3. `category_cluster` (slechts 7 brede emmers zoals "zoet"/"drank";
  ///     alleen als vangnet, want "zoet" alleen mengt snoep met yoghurt).
  ///  4. [fallbackCategory] (kale OFF-categorie) wanneer het bronproduct nog
  ///     niet AI-verrijkt is.
  static (String column, bool lowerIsBetter)? _goalAxis(SwapGoal? goal) =>
      switch (goal) {
        SwapGoal.minderKcal => ('kcal_100g', true),
        SwapGoal.minderSuiker => ('sugar_100g', true),
        SwapGoal.meerEiwit => ('protein_100g', false),
        SwapGoal.besteOverall || null => null,
      };

  /// Haalt ook de sterkste kandidaten op de gekozen doelas op. Daardoor
  /// verdwijnt een goede swap niet omdat hij buiten de kwaliteitstop valt.
  Future<List<SwapCandidate>> _goalDirectedCandidates({
    required String excludeBarcode,
    required String swapFamily,
    required SwapGoal goal,
    required double sourceValue,
    int limit = 20,
  }) async {
    final axis = _goalAxis(goal);
    if (axis == null) return const [];
    final (column, lowerIsBetter) = axis;
    var query = _supabase.client
        .from(_resolvedProductView)
        .select(_resolvedProductColumns)
        .eq('swap_family', swapFamily)
        .eq('classification_status', 'classified')
        .eq('is_swap_relevant', true)
        .neq('barcode', excludeBarcode);
    query = lowerIsBetter
        ? query.lt(column, sourceValue)
        : query.gt(column, sourceValue);
    final rows = await query
        .order(column, ascending: lowerIsBetter)
        .order('barcode')
        .limit(limit);
    return (rows as List)
        .map((row) => SwapCandidate.fromJoinedJson(
              (row as Map).cast<String, dynamic>(),
            ))
        .where(_isEligibleCandidate)
        .toList();
  }

  Future<List<SwapCandidate>> getCandidatesForCluster({
    required String excludeBarcode,
    String? swapFamily,
    String? snackType,
    String? categoryCluster,
    String? fallbackCategory,
    SwapGoal? goal,
    double? goalSourceValue,
    int limit = 120,
  }) async {
    if (!_supabase.isAvailable) return const [];
    try {
      if (swapFamily != null && swapFamily.isNotEmpty) {
        final rows = await _supabase.client
            .from(_resolvedProductView)
            .select(_resolvedProductColumns)
            .eq('swap_family', swapFamily)
            .eq('classification_status', 'classified')
            .eq('is_swap_relevant', true)
            .neq('barcode', excludeBarcode)
            .order('data_quality_score', ascending: false)
            .order('barcode')
            .limit(limit);
        final candidates = (rows as List)
            .map((r) => SwapCandidate.fromJoinedJson(
                (r as Map).cast<String, dynamic>()))
            .where(_isEligibleCandidate)
            .toList();
        if (goal != null && goalSourceValue != null) {
          final directed = await _goalDirectedCandidates(
            excludeBarcode: excludeBarcode,
            swapFamily: swapFamily,
            goal: goal,
            sourceValue: goalSourceValue,
          );
          final seen = candidates.map((candidate) => candidate.barcode).toSet();
          for (final candidate in directed) {
            if (seen.add(candidate.barcode)) candidates.add(candidate);
          }
        }
        // Een bekende familie is de hardste semantische grens. Ook bij maar
        // één goede kandidaat nooit verbreden naar een algemene categorie.
        return candidates;
      }
      if (snackType != null && snackType.isNotEmpty) {
        final rows = await _supabase.client
            .from(_resolvedProductView)
            .select(_resolvedProductColumns)
            .eq('snack_type', snackType)
            .eq('classification_status', 'classified')
            .eq('is_swap_relevant', true)
            .neq('barcode', excludeBarcode)
            .order('data_quality_score', ascending: false)
            .order('barcode')
            .limit(limit);
        final candidates = (rows as List)
            .map((r) => SwapCandidate.fromJoinedJson(
                (r as Map).cast<String, dynamic>()))
            .where(_isEligibleCandidate)
            .toList();
        return candidates;
      }
      if (categoryCluster != null && categoryCluster.isNotEmpty) {
        final rows = await _supabase.client
            .from(_resolvedProductView)
            .select(_resolvedProductColumns)
            .eq('category_cluster', categoryCluster)
            .eq('classification_status', 'classified')
            .eq('is_swap_relevant', true)
            .neq('barcode', excludeBarcode)
            .order('data_quality_score', ascending: false)
            .order('barcode')
            .limit(limit);
        final candidates = (rows as List)
            .map((r) => SwapCandidate.fromJoinedJson(
                (r as Map).cast<String, dynamic>()))
            .where(_isEligibleCandidate)
            .toList();
        if (candidates.isNotEmpty) return candidates;
      }
      if (fallbackCategory != null && fallbackCategory.isNotEmpty) {
        final rows = await _supabase.client
            .from(_resolvedProductView)
            .select(_resolvedProductColumns)
            .eq('classification_status', 'classified')
            .eq('is_swap_relevant', true)
            .neq('barcode', excludeBarcode)
            .ilike('category', '%$fallbackCategory%')
            .order('data_quality_score', ascending: false)
            .order('barcode')
            .limit(limit);
        return (rows as List)
            .map((r) => SwapCandidate.fromJoinedJson(
                (r as Map).cast<String, dynamic>()))
            .where(_isEligibleCandidate)
            .toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// Haalt de expliciete `related_families` op voor een `swap_family` uit
  /// `swap_family_mapping` -- de bron van waarheid voor "Andere opties"
  /// (bv. chocolate_spreads -> [nut_butters, jams_fruit_spreads, ...]).
  Future<List<String>> getRelatedFamilies(String swapFamily) async {
    if (!_supabase.isAvailable || swapFamily.isEmpty) return const [];
    try {
      final rows = await _supabase.client
          .from('swap_family_mapping')
          .select('related_families')
          .eq('swap_family', swapFamily)
          .limit(1);
      final list = rows as List;
      if (list.isEmpty) return const [];
      final related = (list.first as Map)['related_families'] as List?;
      return related?.map((e) => e.toString()).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Kandidaten voor "Andere opties": primair via de expliciete
  /// `related_families`-lijst (bv. chocolate_spreads -> nut_butters); als die
  /// leeg is, worden bewust geen cross-familie-opties verzonnen.
  Future<List<SwapCandidate>> getCandidatesForOtherForm({
    required String excludeBarcode,
    required String productForm,
    List<String> relatedFamilies = const [],
    String? excludeSwapFamily,
    int limit = 80,
  }) async {
    if (!_supabase.isAvailable) return const [];
    try {
      if (relatedFamilies.isNotEmpty) {
        final rows = await _supabase.client
            .from(_resolvedProductView)
            .select(_resolvedProductColumns)
            .inFilter('swap_family', relatedFamilies)
            .eq('classification_status', 'classified')
            .eq('is_swap_relevant', true)
            .neq('barcode', excludeBarcode)
            .order('data_quality_score', ascending: false)
            .limit(limit);
        final candidates = (rows as List)
            .map((r) => SwapCandidate.fromJoinedJson(
                (r as Map).cast<String, dynamic>()))
            .where(_isEligibleCandidate)
            .toList();
        if (candidates.isNotEmpty) return candidates;
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('network') ||
        s.contains('failed host') ||
        s.contains('connection')) {
      return 'Geen internetverbinding. Controleer je netwerk en probeer opnieuw.';
    }
    return 'Er ging iets mis bij de server. Probeer het later opnieuw.';
  }

  static bool _isEligibleCandidate(SwapCandidate candidate) =>
      candidate.features.classificationStatus == 'classified' &&
      candidate.features.isSwapRelevant &&
      candidate.features.swapFamily != null &&
      candidate.features.swapFamily!.isNotEmpty;
}

final snackSwapServiceProvider = Provider<SnackSwapService>(
  (ref) => SnackSwapService(
    ref.watch(supabaseServiceProvider),
    offlineCatalog: ref.watch(offlineSwapCandidateRepositoryV3Provider),
  ),
);
