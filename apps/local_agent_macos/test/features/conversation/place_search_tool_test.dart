import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/place_search_tool.dart';

void main() {
  test('declares itself with a query the model must supply', () {
    final tool = PlaceSearchTool(searchPlaces: (_) async => const []);
    expect(tool.name, 'search_places');
    expect(tool.parameters.keys, contains('query'));
    // The description carries the one instruction that makes results
    // usable without the user's location: name the place in the query.
    expect(tool.description, contains('city or district'));
  });

  test('answers with names and addresses, bounded', () async {
    final tool = PlaceSearchTool(
      searchPlaces: (String query) async => <PlaceHit>[
        for (int i = 0; i < 9; i++)
          PlaceHit(name: '咖啡廳 $i for $query', address: '台北市大安區某路 $i 號'),
      ],
    );

    final result =
        await tool.call(<String, Object?>{'query': '大安區 安靜咖啡廳'})
            as Map<String, Object?>;

    final places = result['places']! as List<Object?>;
    expect(places, hasLength(PlaceSearchTool.maxHits));
    final first = places.first! as Map<String, Object?>;
    expect(first['name'], contains('咖啡廳 0'));
    expect(first['address'], contains('大安區'));
    expect(result['totalFound'], 9);
  });

  test('a missing query is an error the model can read', () async {
    final tool = PlaceSearchTool(searchPlaces: (_) async => const []);
    final result =
        await tool.call(const <String, Object?>{}) as Map<String, Object?>;
    expect(result['error'], isNotNull);
  });

  test('nothing found says so instead of inventing', () async {
    final tool = PlaceSearchTool(searchPlaces: (_) async => const []);
    final result =
        await tool.call(<String, Object?>{'query': '月球 咖啡廳'})
            as Map<String, Object?>;
    expect(result['places'], isEmpty);
    expect(result['totalFound'], 0);
  });
}
