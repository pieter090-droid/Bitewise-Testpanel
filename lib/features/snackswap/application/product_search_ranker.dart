import 'package:bitewise/features/snackswap/domain/snack_product.dart';

/// Rangschikt tekstresultaten op menselijke relevantie.
abstract final class ProductSearchRanker {
  static const _aliases = <String, List<String>>{
    'ei': ['eieren', 'scharrelei', 'scharreleieren', 'egg', 'eggs'],
    'eieren': ['ei', 'scharrelei', 'scharreleieren', 'egg', 'eggs'],
    'eiwitreep': ['proteine reep', 'protein bar'],
    'proteine': ['eiwit', 'protein'],
    'amandel': ['almond'],
    'almond': ['amandel'],
    'yoghurt': ['yogurt'],
    'yogurt': ['yoghurt'],
    'kwark': ['quark', 'fromage blanc'],
    'ijs': ['ice cream', 'glace'],
    'frisdrank': ['soft drink', 'soda'],
    'chips': ['crisps', 'aardappelchips'],
    'reep': ['bar'],
    'koek': ['cookie', 'cookies', 'biscuit', 'biscuits'],
    'kaas': ['cheese'],
    'kipfilet': ['chicken breast'],
    'pindakaas': ['peanut butter'],
    'chocopasta': ['hazelnootpasta', 'chocolate spread'],
    'appel': ['apple'],
    'brood': ['bread'],
  };

  static List<String> searchTerms(String query) {
    final normalized = normalize(query);
    if (normalized.length < 2) return const [];
    final terms = <String>{normalized};
    for (final token in normalized.split(' ')) {
      if (token.length >= 2) terms.add(token);
      terms.addAll(_aliases[token] ?? const []);
      // Een korte prefix maakt typefouten terugvindbaar in Supabase; de
      // lokale rangschikker beslist daarna met edit-distance of het echt past.
      if (token.length >= 5) {
        terms.add(token.substring(0, 4));
        terms.addAll(_adjacentTranspositions(token));
      }
    }
    return terms.take(12).toList(growable: false);
  }

  static List<SnackProduct> rank(
    String query,
    Iterable<SnackProduct> products, {
    int limit = 30,
  }) {
    final q = normalize(query);
    final queryTokens =
        q.split(' ').where((token) => token.isNotEmpty).toList();
    final unique = <String, SnackProduct>{};
    for (final product in products) {
      if (product.barcode.isNotEmpty) unique[product.barcode] = product;
    }

    final scored = <({SnackProduct product, int score})>[];
    for (final product in unique.values) {
      final name = normalize(product.name);
      final brand = normalize(product.brand ?? '');
      final category = normalize(product.categoriesTags ?? '');
      final combined = '$brand $name'.trim();
      final words =
          combined.split(' ').where((word) => word.isNotEmpty).toSet();
      final searchable = '$combined $category';
      final aliases = queryTokens.expand<String>(
        (token) => _aliases[token] ?? const <String>[],
      );
      final aliasWords = aliases
          .expand((alias) => normalize(alias).split(' '))
          .where((word) => word.isNotEmpty)
          .toSet();

      var score = 0;
      if (name == q) score += 1000;
      if (combined == q || '$name $brand'.trim() == q) score += 900;
      if (name.startsWith('$q ')) score += 650;
      if (brand == q) score += 600;
      if (combined.contains(q)) score += 450;

      final exactTokens = queryTokens.where(words.contains).length;
      score += exactTokens * 160;
      final fuzzyTokens = queryTokens
          .where((token) => !words.contains(token))
          .where((token) => words.any((word) => _isNearToken(token, word)))
          .length;
      score += fuzzyTokens * 240;
      if (queryTokens.isNotEmpty &&
          exactTokens + fuzzyTokens == queryTokens.length) {
        score += 220;
      }
      if (queryTokens.isNotEmpty &&
          queryTokens.every((token) => searchable.contains(token))) {
        score += 250;
      }
      score += aliases.where((alias) => searchable.contains(alias)).length * 90;
      // Een volledig synoniemwoord is sterk bewijs voor productintentie:
      // "scharreleieren" moet bij "ei" boven "ei-bieslooksalade" komen.
      score += words.intersection(aliasWords).length * 1100;

      // Bij korte zoektermen is een substring te ruisgevoelig: "ei" mag
      // bijvoorbeeld niet ieder product met "eiwit" naar boven halen.
      final hasShortWordMatch = words.contains(q) ||
          exactTokens > 0 ||
          words.intersection(aliasWords).isNotEmpty;
      if (q.length <= 3 && !hasShortWordMatch) continue;

      // Een gevonden product blijft vindbaar, maar producten waarvoor de
      // aanbevelingsengine klaar is krijgen binnen vergelijkbare tekstmatches
      // een lichte voorkeur.
      if (product.isSwapReady) score += 75;
      if (score > 0) scored.add((product: product, score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.product.name.compareTo(b.product.name);
    });
    return scored
        .take(limit)
        .map((item) => item.product)
        .toList(growable: false);
  }

  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâãå]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöôõ]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  static bool _isNearToken(String query, String candidate) {
    if (query.length < 4 || candidate.length < 4) return false;
    final maxDistance = query.length >= 8 ? 2 : 1;
    if ((query.length - candidate.length).abs() > maxDistance) return false;
    return _editDistance(query, candidate, maxDistance) <= maxDistance;
  }

  /// Levert een klein, begrensd aantal veelvoorkomende typefoutvarianten.
  /// Daardoor kan de server kandidaten teruggeven wanneer de fout al in de
  /// eerste letters zit; de fuzzy rangschikker controleert daarna de match.
  static Iterable<String> _adjacentTranspositions(String token) sync* {
    for (var index = 0; index < token.length - 1; index++) {
      if (token[index] == token[index + 1]) continue;
      yield '${token.substring(0, index)}'
          '${token[index + 1]}${token[index]}'
          '${token.substring(index + 2)}';
    }
  }

  /// Begrensde Damerau-Levenshtein: ondersteunt ook twee verwisselde letters
  /// (zoals `yohgurt`) zonder de hele catalogus fuzzy te maken.
  static int _editDistance(String left, String right, int cutoff) {
    final previousPrevious = List<int>.filled(right.length + 1, 0);
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0)..[0] = i;
      var rowMinimum = current[0];
      for (var j = 1; j <= right.length; j++) {
        final substitutionCost =
            left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1;
        var value = [
          current[j - 1] + 1,
          previous[j] + 1,
          previous[j - 1] + substitutionCost,
        ].reduce((a, b) => a < b ? a : b);
        if (i > 1 &&
            j > 1 &&
            left.codeUnitAt(i - 1) == right.codeUnitAt(j - 2) &&
            left.codeUnitAt(i - 2) == right.codeUnitAt(j - 1)) {
          final transposed = previousPrevious[j - 2] + 1;
          if (transposed < value) value = transposed;
        }
        current[j] = value;
        if (value < rowMinimum) rowMinimum = value;
      }
      if (rowMinimum > cutoff) return cutoff + 1;
      for (var j = 0; j <= right.length; j++) {
        previousPrevious[j] = previous[j];
      }
      previous = current;
    }
    return previous[right.length];
  }
}
