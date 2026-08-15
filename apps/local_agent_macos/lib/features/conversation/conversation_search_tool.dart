import 'package:agent_core/agent_core.dart';

import 'conversation_storage_service.dart';

/// Lets the agent look through the user's own conversation history.
///
/// The first tool this app ships, chosen because it is entirely local,
/// read-only, and reaches data the app already owns — a permission layer
/// over it would be a layer over nothing. What the model gets back is
/// titles and dates, not transcripts: enough to answer 「我們之前聊過什麼」
/// and to point at the conversation, small enough not to spend the turn's
/// token budget on history the user did not ask to reread.
final class ConversationSearchTool implements AgentTool {
  /// Creates the tool over whatever answers a search.
  ///
  /// A function rather than the storage service, so the tool depends on
  /// exactly the one capability it uses and a test needs nothing else.
  ConversationSearchTool({
    required Future<List<ConversationSummary>> Function(String query)
    searchConversations,
  }) : _search = searchConversations;

  final Future<List<ConversationSummary>> Function(String) _search;

  /// The most conversations one answer carries.
  ///
  /// The result lands inside the model's context window, where the whole
  /// point of summaries over transcripts is staying small.
  static const int maxMatches = 5;

  @override
  String get name => 'search_conversations';

  @override
  String get description =>
      'Searches the user\'s past conversations with you. Returns matching '
      'conversation titles and dates. Use when the user asks what you '
      'talked about before.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
    'query': <String, Object?>{
      'type': 'string',
      'description': 'Words to look for in past conversations.',
    },
  };

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    final Object? query = arguments['query'];
    if (query is! String || query.trim().isEmpty) {
      // The model wrote the arguments, and a model omits arguments the way
      // it invents clocks. An error it can read keeps the turn alive.
      return const <String, Object?>{
        'error': 'query is required: words to look for.',
      };
    }
    final List<ConversationSummary> all = await _search(query);
    return <String, Object?>{
      'matches': <Object?>[
        for (final ConversationSummary summary in all.take(maxMatches))
          <String, Object?>{
            'title': summary.title,
            'when': summary.updatedAt.toIso8601String().substring(0, 10),
          },
      ],
      'totalMatches': all.length,
    };
  }
}
