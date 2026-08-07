// Prints the instruction the app really sends, for
// `ToolCallProbeTests.swift` to hold verbatim.
//
// The probe measures how a system instruction affects tool calling, so an
// abbreviated copy of it measures the wrong prompt — an earlier version used
// the opening block alone, about half of it, and drew conclusions about
// preface length from the result. Run this by hand and paste the output when
// the profile changes; it is not part of the gate.
//
//     dart run tool/dump_preface.dart            # Chinese
//     dart run tool/dump_preface.dart --english
import 'dart:io';

import 'package:agent_core/agent_core.dart';

void main(List<String> arguments) {
  final bool english = arguments.contains('--english');
  final AgentPromptContext context = composeAgentPrompt(
    profile: AgentProfile(),
    prompt: english ? 'What time is it?' : '現在幾點？',
  );
  stdout.writeln(context.systemInstruction);
}
