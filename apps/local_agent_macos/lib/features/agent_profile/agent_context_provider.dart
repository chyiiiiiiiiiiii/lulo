import 'package:agent_core/agent_core.dart';

/// Supplies one immutable context snapshot immediately before generation.
abstract interface class AgentContextProvider {
  /// Composes stable behavior and relevant memories for [prompt].
  AgentPromptContext compose(String prompt);
}

/// Composes context from the latest profile returned by [profileOf].
final class ProfileAgentContextProvider implements AgentContextProvider {
  /// Creates a provider over an explicitly owned profile source.
  const ProfileAgentContextProvider(
    this.profileOf, {
    this.clock = DateTime.now,
  });

  /// Returns the latest valid profile for a new turn.
  final AgentProfile Function() profileOf;

  /// What time it is as this turn is composed.
  ///
  /// Read once per turn rather than once per provider, so an app left open
  /// overnight does not spend the next day insisting it is still yesterday.
  /// Injected so a test can state a time instead of racing the machine's.
  final DateTime Function() clock;

  @override
  AgentPromptContext compose(String prompt) =>
      composeAgentPrompt(profile: profileOf(), prompt: prompt, now: clock());
}
