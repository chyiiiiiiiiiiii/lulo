import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/app/fake_runtime.dart';

void main() {
  test(
    'in-memory storage retains terminal turns for the app session',
    () async {
      final storage = InMemoryConversationStorageService();
      const conversationId = ConversationId('conversation-1');
      const request = GenerationRequest(
        conversationId: conversationId,
        prompt: 'Hello',
      );
      const generation = Generation(
        id: GenerationId('generation-1'),
        request: request,
      );

      await storage.saveUserTurn(
        const Turn(
          role: TurnRole.user,
          text: 'Hello',
          status: TurnStatus.completed,
        ),
      );
      await storage.saveTerminalAssistantTurn(
        const Turn(
          role: TurnRole.assistant,
          text: 'Hi',
          status: TurnStatus.completed,
        ),
        generation,
      );

      expect(await storage.loadTurns(conversationId), hasLength(2));
    },
  );
}
