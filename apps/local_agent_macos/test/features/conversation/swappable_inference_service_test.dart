import 'dart:async';

import 'package:agent_core/agent_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/swappable_inference_service.dart';

import '../../support/controlled_inference_service.dart';

void main() {
  const GenerationRequest request = GenerationRequest(
    conversationId: ConversationId('conversation-1'),
    prompt: 'Hi',
  );

  OwnedInferenceService owned(
    ControlledInferenceService service, {
    required List<String> released,
    required String name,
  }) {
    return OwnedInferenceService(
      service: service,
      release: () async {
        released.add(name);
        await service.dispose();
      },
    );
  }

  test('prompts reach whichever model is currently loaded', () async {
    final List<String> released = <String>[];
    final ControlledInferenceService first = ControlledInferenceService();
    final ControlledInferenceService second = ControlledInferenceService();
    final SwappableInferenceService service = SwappableInferenceService(
      owned(first, released: released, name: 'first'),
    );

    service.generate(request).listen(null);
    await first.requestReceived;
    expect(first.requests, hasLength(1));

    await service.replaceWith(
      () async => owned(second, released: released, name: 'second'),
    );

    service.generate(request).listen(null);
    await second.requestReceived;
    // The conversation and its repository were built once and hold this one
    // service, so the model has to change underneath them rather than by
    // rebuilding the graph around them.
    expect(second.requests, hasLength(1));
    expect(first.requests, hasLength(1));
  });

  test('releasing a session reaches the model currently loaded', () async {
    // This is the service the app actually installs, so a delete that stopped
    // here would leave the KV cache resident with nothing to say so.
    final List<String> released = <String>[];
    final ControlledInferenceService first = ControlledInferenceService();
    final ControlledInferenceService second = ControlledInferenceService();
    final SwappableInferenceService service = SwappableInferenceService(
      owned(first, released: released, name: 'first'),
    );

    await service.releaseSession(const ConversationId('conversation-1'));
    await service.replaceWith(
      () async => owned(second, released: released, name: 'second'),
    );
    await service.releaseSession(const ConversationId('conversation-2'));

    expect(first.releasedSessions, <ConversationId>[
      const ConversationId('conversation-1'),
    ]);
    expect(second.releasedSessions, <ConversationId>[
      const ConversationId('conversation-2'),
    ]);
  });

  test('the model being replaced is released before the next one is built', () {
    // The models are gigabytes. Building the new one first would hold two of
    // them in memory at once, and the native runtime serialises a load behind
    // an unload anyway.
    final List<String> order = <String>[];
    final ControlledInferenceService first = ControlledInferenceService();
    final SwappableInferenceService service = SwappableInferenceService(
      OwnedInferenceService(
        service: first,
        release: () async {
          order.add('released the old model');
          await first.dispose();
        },
      ),
    );

    return service
        .replaceWith(() async {
          order.add('built the new model');
          return OwnedInferenceService(
            service: ControlledInferenceService(),
            release: () async {},
          );
        })
        .then((void _) {
          expect(order, <String>[
            'released the old model',
            'built the new model',
          ]);
        });
  });

  test('a prompt sent while the model is changing is told so', () async {
    final Completer<void> buildingTheNewModel = Completer<void>();
    final SwappableInferenceService service = SwappableInferenceService(
      OwnedInferenceService(
        service: ControlledInferenceService(),
        release: () async {},
      ),
    );

    final Future<void> swap = service.replaceWith(() async {
      await buildingTheNewModel.future;
      return OwnedInferenceService(
        service: ControlledInferenceService(),
        release: () async {},
      );
    });

    // Loading a model takes seconds, and for those seconds there is nothing to
    // ask. Saying so is the answer; reporting the released service as disposed
    // would put an implementation detail in front of the user.
    await expectLater(
      service.generate(request),
      emitsError(
        isA<ConversationFailure>().having(
          (ConversationFailure failure) => failure.message,
          'message',
          contains('changing'),
        ),
      ),
    );

    buildingTheNewModel.complete();
    await swap;
  });

  test('a model that fails to load leaves nothing half-installed', () async {
    final SwappableInferenceService service = SwappableInferenceService(
      OwnedInferenceService(
        service: ControlledInferenceService(),
        release: () async {},
      ),
    );

    await expectLater(
      service.replaceWith(
        () async => throw const ConversationFailure('That file is not a model'),
      ),
      throwsA(isA<ConversationFailure>()),
    );

    // The old model is gone and no new one arrived, so the honest answer to a
    // prompt is that there is nothing to ask rather than a stale stream from a
    // service that has already been released.
    await expectLater(
      service.generate(request),
      emitsError(isA<ConversationFailure>()),
    );
  });

  test('disposing releases the model that is loaded', () async {
    final List<String> released = <String>[];
    final ControlledInferenceService only = ControlledInferenceService();
    final SwappableInferenceService service = SwappableInferenceService(
      owned(only, released: released, name: 'only'),
    );

    await service.dispose();

    expect(released, <String>['only']);
  });
}
