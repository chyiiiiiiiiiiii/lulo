import 'dart:io';

import 'package:agent_core/agent_core.dart';

/// Prints the instructions `composeMemoryExtraction` emits, for pasting into
/// `RememberProbeTests`.
///
/// The probe measures a Swift copy of these strings, because it drives the
/// runtime directly and cannot call Dart. That copy is only worth its
/// numbers while it matches, so regenerate it here rather than editing it by
/// hand — `tool-calling-readiness.md` records what happens to a table whose
/// prompt drifted from the app's.
///
/// ```sh
/// cd packages/agent_core && dart run tool/dump_extraction_preface.dart
/// ```
void main() {
  final AgentProfile chinese = AgentProfile(
    memories: <AgentMemory>[
      AgentMemory(
        id: 'memory-1',
        kind: AgentMemoryKind.personal,
        content: '使用者住在台北',
      ),
      AgentMemory(
        id: 'memory-2',
        kind: AgentMemoryKind.preference,
        content: '使用者喜歡比較長的說明',
      ),
    ],
  );
  final AgentProfile english = AgentProfile(
    memories: <AgentMemory>[
      AgentMemory(
        id: 'memory-1',
        kind: AgentMemoryKind.personal,
        content: 'The user lives in Taipei',
      ),
    ],
  );

  // 「搬家」 and "moving" only pick the language; the instruction does not
  // otherwise depend on what was said.
  _dump('zh, nothing known', composeMemoryExtraction(said: '搬家'));
  _dump('en, nothing known', composeMemoryExtraction(said: 'moving'));
  _dump(
    'zh, two memories known',
    composeMemoryExtraction(said: '搬家', known: chinese),
  );
  _dump(
    'en, one memory known',
    composeMemoryExtraction(said: 'moving', known: english),
  );
}

void _dump(String label, AgentMemoryExtractionPrompt prompt) {
  stdout.writeln('===== $label =====');
  stdout.writeln(prompt.systemInstruction);
  stdout.writeln();
}
