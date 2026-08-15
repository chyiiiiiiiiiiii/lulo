import 'dart:convert';

/// A capability the agent can decide to use during a turn.
///
/// Tools live in Dart because policy lives in Dart: what exists, what it is
/// allowed to do, and what the model is told about it are all product
/// decisions, and the next platform reuses them unchanged. The runtime's
/// only involvement is rendering [parameters] into the chat template and
/// handing back the model's decision to call.
///
/// Not everything that looks like a tool should be one. A fact that is
/// cheap, small, and always available is context — the clock is told in the
/// turn instruction, measured at 5/5 with zero extra latency, and the model
/// does not double-fetch what it was told (0/5 calls with the clock in the
/// prompt). Tools are for what telling cannot do: side effects, expensive
/// lookups, results too big or variable to send unconditionally. See
/// `docs/decisions/tool-calling-readiness.md`.
abstract interface class AgentTool {
  /// What the model calls this tool. Snake case, unique within a toolbox.
  String get name;

  /// What the model is told the tool does. This is the whole interface the
  /// model reasons about; write it for the model, not for a reader of code.
  String get description;

  /// OpenAPI property schemas for the arguments, keyed by argument name.
  ///
  /// Empty means the tool takes no arguments. Only the properties map is
  /// declared here; the enclosing `{"type": "object", ...}` wrapper is the
  /// toolbox's to write, so a tool cannot get the envelope wrong.
  Map<String, Object?> get parameters;

  /// Runs the tool. What it returns is shown to the model, not the user —
  /// keep it small, structured, and readable by a model mid-answer.
  Future<Object?> call(Map<String, Object?> arguments);
}

/// One call the model decided to make.
final class AgentToolCall {
  /// Creates a call to [name] with [arguments].
  const AgentToolCall({
    required this.name,
    this.id = '',
    this.arguments = const <String, Object?>{},
  });

  /// The tool the model asked for. The model writes this, so nothing
  /// guarantees a tool by this name exists — see [AgentToolbox.call].
  final String name;

  /// The runtime's identifier for pairing the response, empty when the
  /// runtime did not assign one.
  final String id;

  /// The arguments the model supplied.
  final Map<String, Object?> arguments;

  /// Reads the list the native runtime hands over:
  /// `[{"name": …, "id": …, "arguments": {…}}]`.
  ///
  /// Anything malformed is an empty list rather than a throw: this string
  /// arrives mid-turn from the far side of a message channel, and a turn
  /// must degrade to "answered without tools", never to a crash.
  static List<AgentToolCall> listFromJson(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return const <AgentToolCall>[];
    }
    if (decoded is! List<Object?>) {
      return const <AgentToolCall>[];
    }
    final calls = <AgentToolCall>[];
    for (final Object? entry in decoded) {
      if (entry is! Map<String, Object?>) {
        continue;
      }
      final Object? name = entry['name'];
      if (name is! String || name.isEmpty) {
        continue;
      }
      final Object? arguments = entry['arguments'];
      calls.add(
        AgentToolCall(
          name: name,
          id: entry['id'] is String ? entry['id']! as String : '',
          arguments: arguments is Map<String, Object?>
              ? arguments
              : const <String, Object?>{},
        ),
      );
    }
    return calls;
  }
}

/// What running one call produced, in the shape the model reads back.
final class AgentToolResult {
  /// Creates a result for the call named [name].
  const AgentToolResult({
    required this.name,
    required this.id,
    required this.result,
  });

  /// The tool that ran — or was asked for and did not exist.
  final String name;

  /// The identifier of the call this answers, carried through unchanged.
  final String id;

  /// What the model is shown. An error is a result too: `{"error": …}`
  /// keeps the turn alive where a thrown exception would end it.
  final Object? result;
}

/// Encodes [results] for the native runtime to feed back to the model:
/// `[{"name": …, "id": …, "response": …}]`.
String encodeAgentToolResults(List<AgentToolResult> results) {
  return jsonEncode(<Object?>[
    for (final AgentToolResult result in results)
      <String, Object?>{
        'name': result.name,
        'id': result.id,
        'response': result.result,
      },
  ]);
}

/// The set of tools offered on a conversation, and their wire form.
final class AgentToolbox {
  /// Creates a toolbox over [tools], refusing duplicate names out loud —
  /// a second tool under one name silently answering for the first is the
  /// same bug `GlobalHotKeyController` had, and it was found in production.
  AgentToolbox(List<AgentTool> tools)
    : _tools = <String, AgentTool>{
        for (final AgentTool tool in tools) tool.name: tool,
      } {
    if (_tools.length != tools.length) {
      throw ArgumentError('Two tools share one name.');
    }
  }

  final Map<String, AgentTool> _tools;

  /// Whether there is nothing here, which callers use to skip the whole
  /// tool path — an empty toolbox must cost what no toolbox costs.
  bool get isEmpty => _tools.isEmpty;

  /// The declarations the model sees, as OpenAPI function JSON, or null
  /// when there is nothing to declare.
  ///
  /// The shape is the one the probe measured working — each entry
  /// `{"type": "function", "function": {name, description, parameters}}`,
  /// with parameters always an object schema so no tool can be rendered
  /// half-declared.
  String? get declarationsJson {
    if (_tools.isEmpty) {
      return null;
    }
    return jsonEncode(<Object?>[
      for (final AgentTool tool in _tools.values)
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': tool.parameters,
            },
          },
        },
    ]);
  }

  /// Runs [call] and always returns a result the model can read.
  ///
  /// A name nothing owns and a tool that throws both become `{"error": …}`
  /// results rather than exceptions: the name and the failure came from
  /// the model's side of the conversation, and the turn has to survive
  /// them the way it survives any other wrong answer.
  Future<AgentToolResult> call(AgentToolCall call) async {
    final AgentTool? tool = _tools[call.name];
    if (tool == null) {
      return AgentToolResult(
        name: call.name,
        id: call.id,
        result: <String, Object?>{
          'error': 'No tool named ${call.name} exists.',
        },
      );
    }
    try {
      return AgentToolResult(
        name: call.name,
        id: call.id,
        result: await tool.call(call.arguments),
      );
    } on Object catch (error) {
      return AgentToolResult(
        name: call.name,
        id: call.id,
        result: <String, Object?>{'error': error.toString()},
      );
    }
  }
}
