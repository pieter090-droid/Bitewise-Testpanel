/// Uniform productmodel voor de offline v3-catalogus en `lookup_product`.
///
/// De voedingswaarden zijn platte velden per 100 g/ml (`*_100g`), precies zoals
/// de backend ze levert. `source` komt uit het antwoord-omhulsel
/// (`"supabase"` of `"open_food_facts_saved"`).
class SnackProduct {
  const SnackProduct({
    required this.barcode,
    required this.name,
    this.brand,
    this.imageUrl,
    this.source,
    this.kcal100,
    this.sugar100,
    this.protein100,
    this.fat100,
    this.carbs100,
    this.fiber100,
    this.salt100,
    this.saturatedFat100,
    this.categoriesTags,
    this.classificationStatus,
    this.isSwapRelevant = false,
    this.swapFamily,
  });

  final String barcode;
  final String name;
  final String? brand;
  final String? imageUrl;
  final String? source;

  final double? kcal100;
  final double? sugar100;
  final double? protein100;
  final double? fat100;
  final double? carbs100;
  final double? fiber100;
  final double? salt100;
  final double? saturatedFat100;
  final String? categoriesTags;
  final String? classificationStatus;
  final bool isSwapRelevant;
  final String? swapFamily;

  bool get isSwapReady =>
      classificationStatus == 'classified' &&
      isSwapRelevant &&
      swapFamily != null &&
      swapFamily!.isNotEmpty;

  int get knownNutritionCount => [
        kcal100,
        sugar100,
        protein100,
        fat100,
        carbs100,
        fiber100,
        salt100,
        saturatedFat100,
      ].where((value) => value != null).length;

  bool get hasNutrition => knownNutritionCount > 0;

  factory SnackProduct.fromJson(Map<String, dynamic> json, {String? source}) {
    double? d(Object? v) => v == null ? null : (v as num).toDouble();
    return SnackProduct(
      barcode: json['barcode']?.toString() ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Onbekend product',
      brand: json['brand'] as String?,
      imageUrl: json['image_url'] as String?,
      source: source ?? json['source'] as String?,
      kcal100: d(json['kcal_100g']),
      sugar100: d(json['sugar_100g']),
      protein100: d(json['protein_100g']),
      fat100: d(json['fat_100g']),
      carbs100: d(json['carbs_100g']),
      fiber100: d(json['fiber_100g']),
      salt100: d(json['salt_100g']),
      saturatedFat100: d(json['saturated_fat_100g']),
      categoriesTags: json['categories_tags']?.toString(),
      classificationStatus: json['classification_status'] as String?,
      isSwapRelevant: json['is_swap_relevant'] == true,
      swapFamily: json['swap_family'] as String?,
    );
  }
}
