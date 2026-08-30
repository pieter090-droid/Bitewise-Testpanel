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
    }
    return terms.take(8).toList(growable: false);
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
      if (queryTokens.isNotEmpty &&
          queryTokens.every((token) => searchable.contains(token))) {
        score += 250;
      }
      score += aliases.where((alias) => searchable.contains(alias)).length * 90;
      score += words.intersection(aliasWords).length * 500;

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
}
