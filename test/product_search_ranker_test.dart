import 'package:flutter_test/flutter_test.dart';

import 'package:bitewise/features/snackswap/application/product_search_ranker.dart';
import 'package:bitewise/features/snackswap/domain/snack_product.dart';

SnackProduct item(String barcode, String name, {String? brand, String? tags}) =>
    SnackProduct(
      barcode: barcode,
      name: name,
      brand: brand,
      categoriesTags: tags,
    );

void main() {
  group('ProductSearchRanker', () {
    test('ei zet echte eieren boven producten met ei als ingrediënt', () {
      final result = ProductSearchRanker.rank('ei', [
        item('1', 'Mayonaise met ei'),
        item('2', 'Scharrel eieren 10 stuks'),
        item('3', 'Eiwitreep chocolade'),
      ]);
      expect(result.first.barcode, '2');
    });

    test('Kinder Bueno wordt via volledige naam en merk gevonden', () {
      final result = ProductSearchRanker.rank('kinder bueno', [
        item('1', 'Bueno White', brand: 'Kinder'),
        item('2', 'Kinder chocolade'),
        item('3', 'Bueno imitatie', brand: 'Ander merk'),
      ]);
      expect(result.first.barcode, '1');
    });

    test('accenten en leestekens veranderen de match niet', () {
      final result = ProductSearchRanker.rank(
        'proteïne-reep',
        [item('1', 'Proteine reep chocolade')],
      );
      expect(result.single.barcode, '1');
    });

    test('dubbele barcodes komen eenmaal terug', () {
      final product = item('1', 'Kinder Bueno', brand: 'Ferrero');
      expect(
        ProductSearchRanker.rank('kinder bueno', [product, product]),
        hasLength(1),
      );
    });
  });
}
