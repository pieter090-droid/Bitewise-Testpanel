import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapResultRankerV3 {
  const SwapResultRankerV3();

  List<SwapRecommendationV3> rank(
    Iterable<SwapRecommendationV3> recommendations,
    int maximumResults,
  ) {
    final bestByBarcode = <String, SwapRecommendationV3>{};
    for (final recommendation in recommendations) {
      final existing = bestByBarcode[recommendation.product.barcode];
      if (existing == null || _compare(recommendation, existing) < 0) {
        bestByBarcode[recommendation.product.barcode] = recommendation;
      }
    }
    final result = bestByBarcode.values.toList()..sort(_compare);
    return result.take(maximumResults).toList(growable: false);
  }

  int _compare(SwapRecommendationV3 a, SwapRecommendationV3 b) {
    var value = b.score.finalScore.compareTo(a.score.finalScore);
    if (value != 0) return value;
    value = b.score.goalImprovement.compareTo(a.score.goalImprovement);
    if (value != 0) return value;
    value = b.score.practicalMatch.compareTo(a.score.practicalMatch);
    if (value != 0) return value;
    value = b.score.dataQuality.compareTo(a.score.dataQuality);
    if (value != 0) return value;
    return a.product.barcode.compareTo(b.product.barcode);
  }
}
