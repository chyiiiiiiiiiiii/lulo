import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/agent_profile/agent_context_provider.dart';

void main() {
  // The model cannot read the machine's clock and does not say so when it
  // cannot — asked the time under this app's own instruction, with a clock
  // tool registered and available, it invented an answer 5 times out of 5.
  // `docs/decisions/tool-calling-readiness.md` has the probe. The provider
  // is the one place that knows when the turn started, so it is the one
  // place that can tell it.
  test('the turn carries the time it was asked at', () {
    final ProfileAgentContextProvider provider = ProfileAgentContextProvider(
      AgentProfile.builtIn,
      clock: () => DateTime(2026, 8, 7, 2, 53),
    );

    final AgentPromptContext context = provider.compose('現在幾點？');

    expect(context.turnInstruction, contains('[背景：現在]'));
    expect(context.turnInstruction, contains('2026 年 8 月 7 日'));
    expect(context.turnInstruction, contains('02:53'));
  });

  // Read per turn rather than once, or an app left open overnight would
  // spend the next day insisting it is still yesterday.
  test('the clock is read again for every turn', () {
    final List<DateTime> times = <DateTime>[
      DateTime(2026, 8, 7, 23, 59),
      DateTime(2026, 8, 8, 0, 1),
    ];
    int index = 0;
    final ProfileAgentContextProvider provider = ProfileAgentContextProvider(
      AgentProfile.builtIn,
      clock: () => times[index++],
    );

    expect(provider.compose('現在幾點？').turnInstruction, contains('8 月 7 日'));
    expect(provider.compose('現在幾點？').turnInstruction, contains('8 月 8 日'));
  });

  // 40 pages do not fit a 4096-token window. Only the passages this
  // question turns out to be about are sent, so a document that is open and
  // irrelevant costs nothing — which is what makes keeping one open safe.
  test('a question about an open document carries the relevant part', () {
    final ProfileAgentContextProvider provider = ProfileAgentContextProvider(
      AgentProfile.builtIn,
      clock: () => DateTime(2026, 8, 7, 2, 53),
      documentOf: () => '第三條 期間\n本租約為期一年。\n\n第九條 保固\n提供五年保固。',
    );

    final AgentPromptContext asked = provider.compose('保固幾年');
    expect(asked.turnInstruction, contains('五年保固'));
    expect(asked.documentCharacters, greaterThan(0));

    final AgentPromptContext unrelated = provider.compose('今天天氣如何');
    expect(unrelated.documentCharacters, 0);
  });

  test('no document open sends none of one', () {
    final ProfileAgentContextProvider provider = ProfileAgentContextProvider(
      AgentProfile.builtIn,
      clock: () => DateTime(2026, 8, 7, 2, 53),
    );

    expect(provider.compose('保固幾年').documentCharacters, 0);
  });
}
