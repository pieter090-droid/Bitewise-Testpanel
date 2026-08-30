import 'package:bitewise/core/supabase/supabase_service.dart';
import 'package:bitewise/features/snackswap/data/snackswap_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('SUPABASE_URL');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY');
final _skipReason = _url.isEmpty || _key.isEmpty
    ? 'Alleen uitvoeren met de read-only Supabase dart-defines.'
    : false;

void main() {
  SnackSwapService liveService() => SnackSwapService(
        SupabaseService.forTesting(SupabaseClient(_url, _key)),
      );

  test('ei vindt een echt eierproduct voor ingrediëntmatches', () async {
    final results = await liveService().searchProducts('ei');

    expect(results, isNotEmpty);
    expect(
      results.take(5).any(
            (p) => RegExp(r'\b(ei|eieren)\b', caseSensitive: false)
                .hasMatch(p.name),
          ),
      isTrue,
    );
  }, skip: _skipReason);

  test('Kinder Bueno is rechtstreeks vindbaar', () async {
    final results = await liveService().searchProducts('kinder bueno');

    expect(results, isNotEmpty);
    expect(
      results.take(10).any((p) {
        final text = '${p.brand ?? ''} ${p.name}'.toLowerCase();
        return text.contains('kinder') && text.contains('bueno');
      }),
      isTrue,
    );
  }, skip: _skipReason);

  test('Solero-hoofdkandidaten blijven binnen de ijsfamilie', () async {
    final service = liveService();
    final source = await service.getCandidateByBarcode('8712100889288');

    expect(source, isNotNull);
    expect(source!.features.swapFamily, 'ice_cream_desserts');
    final candidates = await service.getCandidatesForCluster(
      excludeBarcode: source.barcode,
      swapFamily: source.features.swapFamily,
      snackType: source.features.snackType,
      categoryCluster: source.features.categoryCluster,
      fallbackCategory: source.category,
    );
    expect(candidates, isNotEmpty);
    expect(
      candidates.every(
        (candidate) => candidate.features.swapFamily == 'ice_cream_desserts',
      ),
      isTrue,
    );
  }, skip: _skipReason);
}
