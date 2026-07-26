/// Immutable configuration selected before the application composition is built.
final class BootstrapConfig {
  /// Creates bootstrap configuration for the local macOS application.
  const BootstrapConfig({
    required this.localOnly,
    required this.targetFrameRate,
  });

  /// Whether the application communicates only with local services.
  final bool localOnly;

  /// The intended animation refresh-rate budget.
  final int targetFrameRate;
}

/// Creates the fixed bootstrap configuration for the local-first application.
BootstrapConfig createBootstrapConfig() {
  return const BootstrapConfig(localOnly: true, targetFrameRate: 120);
}
