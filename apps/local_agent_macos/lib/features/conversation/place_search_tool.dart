import 'package:agent_core/agent_core.dart';

/// One place Apple Maps returned: a real name at a real address.
final class PlaceHit {
  /// Creates a hit.
  const PlaceHit({required this.name, required this.address});

  /// What the place calls itself.
  final String name;

  /// Where it is, as Apple formats it.
  final String address;
}

/// Lets the agent look up real places through Apple Maps.
///
/// Exists because its absence was watched failing: asked for quiet cafés,
/// the model invented three shops and promised to search Google Maps. The
/// prompt now bans the fabrication; this is the capability that replaces
/// it. Apple's local search rather than a third-party API on purpose — a
/// system framework the OS already trusts, no key to manage, and the query
/// goes to the same place the user's own Maps searches go.
///
/// The search runs without the user's location: the model is told to put
/// the city or district in the query instead, which the conversation
/// almost always already contains. Asking for location permission would
/// buy distance sorting at the price of a system dialog this tool works
/// fine without.
final class PlaceSearchTool implements AgentTool {
  /// Creates the tool over whatever answers a place search.
  PlaceSearchTool({
    required Future<List<PlaceHit>> Function(String query) searchPlaces,
  }) : _search = searchPlaces;

  final Future<List<PlaceHit>> Function(String) _search;

  /// The most places one answer carries: the result lands in the model's
  /// context, and five named options is already more than a spoken answer
  /// can walk through.
  static const int maxHits = 5;

  @override
  String get name => 'search_places';

  @override
  String get description =>
      'Searches Apple Maps for real places: shops, cafes, restaurants, '
      'landmarks. Returns real names and addresses. Include the city or '
      'district in the query (for example 大安區 安靜咖啡廳). Use whenever '
      'the user asks about a place to go; never invent place names or '
      'addresses yourself.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
    'query': <String, Object?>{
      'type': 'string',
      'description':
          'What to look for, including the city or district, in the '
          'user\'s language.',
    },
  };

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    final Object? query = arguments['query'];
    if (query is! String || query.trim().isEmpty) {
      return const <String, Object?>{
        'error':
            'query is required: what to look for, including the city '
            'or district.',
      };
    }
    final List<PlaceHit> hits = await _search(query.trim());
    return <String, Object?>{
      'places': <Object?>[
        for (final PlaceHit hit in hits.take(maxHits))
          <String, Object?>{'name': hit.name, 'address': hit.address},
      ],
      'totalFound': hits.length,
    };
  }
}
