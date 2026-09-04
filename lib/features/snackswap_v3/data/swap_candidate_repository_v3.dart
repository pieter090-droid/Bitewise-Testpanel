import 'package:bitewise/features/snackswap_v3/domain/swap_models_v3.dart';

abstract interface class SwapCandidateRepositoryV3 {
  Future<String?> primaryUsageRoleFor(String sourceBarcode);

  Future<SwapCalculatorInputV3?> loadInput({
    required String sourceBarcode,
    required String usageRoleCode,
    required SwapGoalV3 goal,
  });
}
