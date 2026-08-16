// Prints the instruction the app really sends, for
// `ToolCallProbeTests.swift` to hold verbatim.
//
// The probe measures how a system instruction affects tool calling, so an
// abbreviated copy of it measures the wrong prompt — an earlier version used
// the opening block alone, about half of it, and drew conclusions about
// preface length from the result. Run this by hand and paste the output when
// the profile changes; it is not part of the gate.
//
//     dart run tool/dump_preface.dart            # Chinese, spoken
//     dart run tool/dump_preface.dart --english
//     dart run tool/dump_preface.dart --written  # the typed-channel shape
import 'dart:io';

import 'package:agent_core/agent_core.dart';

void main(List<String> arguments) {
  final bool english = arguments.contains('--english');
  final bool written = arguments.contains('--written');
  final AgentPromptContext context = composeAgentPrompt(
    profile: AgentProfile(),
    prompt: english ? 'What time is it?' : '現在幾點？',
    channel: written ? AnswerChannel.written : AnswerChannel.spoken,
  );
  stdout.writeln(context.systemInstruction);
}
