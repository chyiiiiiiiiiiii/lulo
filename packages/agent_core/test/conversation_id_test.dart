import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('ConversationId compares equal when its value is equal', () {
    expect(
      ConversationId('conversation-1'),
      equals(ConversationId('conversation-1')),
    );
  });
}
