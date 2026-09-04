abstract final class FeatureFlags {
  /// V3 blijft uit totdat de v3-tabellen/RPC zijn gevuld en de datasetreview
  /// expliciet is goedgekeurd. V2 en v3 mogen nooit in één resultaat mengen.
  static const swapEngineV3Enabled = bool.fromEnvironment(
    'SWAP_ENGINE_V3_ENABLED',
    defaultValue: false,
  );
}
