import 'package:agent_core/agent_core.dart';

/// Supplies one immutable context snapshot immediately before generation.
abstract interface class AgentContextProvider {
  /// Composes stable behavior and relevant memories for [prompt], shaped
  /// for the [channel] the question came in on.
  AgentPromptContext compose(
    String prompt, {
    AnswerChannel channel = AnswerChannel.spoken,
  });
}

/// Composes context from the latest profile returned by [profileOf].
final class ProfileAgentContextProvider implements AgentContextProvider {
  /// Creates a provider over an explicitly owned profile source.
  const ProfileAgentContextProvider(
    this.profileOf, {
    this.clock = DateTime.now,
    this.documentOf = _noDocument,
    this.frontmostAppOf = _noFrontmostApp,
  });

  /// Returns the latest valid profile for a new turn.
  final AgentProfile Function() profileOf;

  /// What time it is as this turn is composed.
  ///
  /// Read once per turn rather than once per provider, so an app left open
  /// overnight does not spend the next day insisting it is still yesterday.
  /// Injected so a test can state a time instead of racing the machine's.
  final DateTime Function() clock;

  /// The document the user is asking about, or empty when there is none.
  ///
  /// Read at the moment a question is composed rather than captured, the
  /// same way the profile is: what is open now is what the question is
  /// about. Only the passages this question turns out to be about are sent,
  /// so an open document a question has nothing to do with costs nothing.
  final String Function() documentOf;

  /// The app the user is in as this turn is composed, or empty to say
  /// nothing about the desktop.
  ///
  /// Read at compose time like the clock and the document, and gated by
  /// the caller: whether the desktop is shared at all is a setting, and
  /// the setting's owner decides by returning empty.
  final String Function() frontmostAppOf;

  @override
  AgentPromptContext compose(
    String prompt, {
    AnswerChannel channel = AnswerChannel.spoken,
  }) {
    final String document = documentOf();
    final String frontmostApp = frontmostAppOf();
    return composeAgentPrompt(
      profile: profileOf(),
      prompt: prompt,
      now: clock(),
      document: document.isEmpty ? null : document,
      frontmostApp: frontmostApp.isEmpty ? null : frontmostApp,
      channel: channel,
    );
  }
}

String _noDocument() => '';

String _noFrontmostApp() => '';
