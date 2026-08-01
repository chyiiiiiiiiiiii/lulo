import 'package:agent_core/agent_core.dart';

/// Supplies one immutable context snapshot immediately before generation.
abstract interface class AgentContextProvider {
  /// Composes stable behavior and relevant memories for [prompt].
  AgentPromptContext compose(String prompt);
}

/// Composes context from the latest profile returned by [profileOf].
final class ProfileAgentContextProvider implements AgentContextProvider {
  /// Creates a provider over an explicitly owned profile source.
  const ProfileAgentContextProvider(this.profileOf);

  /// Returns the latest valid profile for a new turn.
  final AgentProfile Function() profileOf;

  @override
  AgentPromptContext compose(String prompt) =>
      composeAgentPrompt(profile: profileOf(), prompt: prompt);
}
