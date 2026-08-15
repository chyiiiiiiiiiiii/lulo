import 'dart:convert';

import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

final class _Clock implements AgentTool {
  int calls = 0;

  @override
  String get name => 'get_current_time';

  @override
  String get description => 'Returns the current time on this computer.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{};

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    calls += 1;
    return <String, Object?>{'time': '02:53'};
  }
}

final class _Echo implements AgentTool {
  @override
  String get name => 'echo';

  @override
  String get description => 'Repeats what it is given.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
    'text': <String, Object?>{
      'type': 'string',
      'description': 'What to repeat.',
    },
  };

  @override
  Future<Object?> call(Map<String, Object?> arguments) async =>
      arguments['text'];
}

void main() {
  group('AgentToolbox declarations', () {
    test('an empty toolbox declares nothing at all', () {
      expect(AgentToolbox(const <AgentTool>[]).declarationsJson, isNull);
      expect(AgentToolbox(const <AgentTool>[]).isEmpty, isTrue);
    });

    test('declares every tool in the shape the runtime template renders', () {
      final toolbox = AgentToolbox(<AgentTool>[_Clock(), _Echo()]);
      final decoded = jsonDecode(toolbox.declarationsJson!) as List<Object?>;
      expect(decoded, hasLength(2));
      final clock = decoded.first! as Map<String, Object?>;
      expect(clock['type'], 'function');
      final function = clock['function']! as Map<String, Object?>;
      expect(function['name'], 'get_current_time');
      expect(
        function['description'],
        'Returns the current time on this computer.',
      );
      final echo = decoded.last! as Map<String, Object?>;
      final echoFunction = echo['function']! as Map<String, Object?>;
      final echoParameters =
          echoFunction['parameters']! as Map<String, Object?>;
      expect(echoParameters['type'], 'object');
      expect(
        (echoParameters['properties']! as Map<String, Object?>).keys,
        contains('text'),
      );
    });

    test('a tool with no parameters still declares an object schema', () {
      final toolbox = AgentToolbox(<AgentTool>[_Clock()]);
      final decoded = jsonDecode(toolbox.declarationsJson!) as List<Object?>;
      final function =
          (decoded.single! as Map<String, Object?>)['function']!
              as Map<String, Object?>;
      final parameters = function['parameters']! as Map<String, Object?>;
      expect(parameters['type'], 'object');
      expect(parameters['properties'], isEmpty);
    });

    test('two tools with one name is a wiring mistake, said out loud', () {
      expect(
        () => AgentToolbox(<AgentTool>[_Clock(), _Clock()]),
        throwsArgumentError,
      );
    });
  });

  group('AgentToolbox execution', () {
    test('routes a call to the tool that owns the name', () async {
      final clock = _Clock();
      final toolbox = AgentToolbox(<AgentTool>[clock, _Echo()]);
      final result = await toolbox.call(
        const AgentToolCall(name: 'get_current_time'),
      );
      expect(clock.calls, 1);
      expect(result.name, 'get_current_time');
      expect(result.result, <String, Object?>{'time': '02:53'});
    });

    test('hands the arguments through untouched', () async {
      final toolbox = AgentToolbox(<AgentTool>[_Echo()]);
      final result = await toolbox.call(
        const AgentToolCall(
          name: 'echo',
          arguments: <String, Object?>{'text': '你好'},
        ),
      );
      expect(result.result, '你好');
    });

    test('a name nothing owns becomes an error result, not a crash', () async {
      // The name came from the model, and a model invents names the way it
      // invents clocks. The turn must survive it: the model reads the error
      // and answers without the tool.
      final toolbox = AgentToolbox(<AgentTool>[_Clock()]);
      final result = await toolbox.call(
        const AgentToolCall(name: 'get_weather'),
      );
      expect(result.name, 'get_weather');
      expect(
        (result.result! as Map<String, Object?>)['error'],
        contains('get_weather'),
      );
    });

    test(
      'a tool that throws becomes an error result the model can read',
      () async {
        final toolbox = AgentToolbox(<AgentTool>[_Failing()]);
        final result = await toolbox.call(const AgentToolCall(name: 'failing'));
        expect((result.result! as Map<String, Object?>)['error'], isNotEmpty);
      },
    );
  });

  group('AgentToolCall wire format', () {
    test('reads the list the runtime hands over', () {
      final calls = AgentToolCall.listFromJson(
        '[{"name":"get_current_time","id":"c1","arguments":{}},'
        '{"name":"echo","id":"","arguments":{"text":"hi"}}]',
      );
      expect(calls, hasLength(2));
      expect(calls.first.name, 'get_current_time');
      expect(calls.first.id, 'c1');
      expect(calls.last.arguments, <String, Object?>{'text': 'hi'});
    });

    test('malformed JSON is an empty list, never a crash mid-turn', () {
      expect(AgentToolCall.listFromJson('not json'), isEmpty);
      expect(AgentToolCall.listFromJson('{"lone":"object"}'), isEmpty);
    });
  });

  group('AgentToolResult wire format', () {
    test('encodes the responses the runtime feeds back to the model', () {
      final json = encodeAgentToolResults(<AgentToolResult>[
        const AgentToolResult(
          name: 'get_current_time',
          id: 'c1',
          result: <String, Object?>{'time': '02:53'},
        ),
      ]);
      final decoded = jsonDecode(json) as List<Object?>;
      final response = decoded.single! as Map<String, Object?>;
      expect(response['name'], 'get_current_time');
      expect(response['id'], 'c1');
      expect(response['response'], <String, Object?>{'time': '02:53'});
    });
  });
}

final class _Failing implements AgentTool {
  @override
  String get name => 'failing';

  @override
  String get description => 'Always fails.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{};

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    throw StateError('the disk is on fire');
  }
}
