import 'package:bitewise/core/config/feature_flags.dart';
import 'package:bitewise/features/snackswap_v3/application/swap_calculator_v3.dart';
import 'package:bitewise/features/snackswap_v3/data/swap_candidate_repository_v3.dart';
import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

class SwapEngineV3Service {
  const SwapEngineV3Service({
    required this.repository,
    this.calculator = const SwapCalculatorV3(),
    this.enabled = FeatureFlags.swapEngineV3Enabled,
  });

  final SwapCandidateRepositoryV3 repository;
  final SwapCalculatorV3 calculator;
  final bool enabled;

  /// Geeft `null` terug wanneer v3 uitstaat of nog geen complete v3-input
  /// beschikbaar is. De aanroeper mag dan v2 gebruiken, maar mag resultaten
  /// van beide engines nooit samenvoegen.
  Future<SwapCalculationResultV3?> calculate({
    required String sourceBarcode,
    required String usageRoleCode,
    required SwapGoalV3 goal,
  }) async {
    if (!enabled) return null;
    final input = await repository.loadInput(
      sourceBarcode: sourceBarcode,
      usageRoleCode: usageRoleCode,
      goal: goal,
    );
    return input == null ? null : calculator.calculate(input);
  }
}
