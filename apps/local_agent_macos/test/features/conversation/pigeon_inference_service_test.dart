import 'dart:async';
import 'dart:ui' show Rect, Size;

import 'package:agent_core/agent_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/pigeon_inference_service.dart';
import 'package:local_agent_macos/generated/desktop_host_api.g.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';

void main() {
  test(
    'subscribes before start so a fast native lifecycle is not lost',
    () async {
      final host = RecordingDesktopHostService(
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 0,
                  type: HostGenerationEventType.started,
                ),
              );
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 1,
                  type: HostGenerationEventType.delta,
                  delta: 'Hello',
                ),
              );
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 2,
                  type: HostGenerationEventType.completed,
                ),
              );
              return DesktopGenerationAcknowledgement(
                generationId: request.generationId,
                accepted: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      const request = GenerationRequest(
        conversationId: ConversationId('conversation-1'),
        prompt: 'Hi',
      );

      final events = await service.generate(request).toList();

      expect(events, hasLength(3));
      expect(events[0], isA<GenerationStarted>());
      expect(
        (events[0] as GenerationStarted).generation.request,
        same(request),
      );
      expect((events[1] as GenerationDelta).delta, 'Hello');
      expect(events[2], isA<GenerationCompleted>());
      expect(host.eventListenerCountAtStart, 1);
    },
  );

  test(
    'shares one successful handshake and model load across generations',
    () async {
      final host = RecordingDesktopHostService(
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 0,
                  type: HostGenerationEventType.started,
                ),
              );
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 1,
                  type: HostGenerationEventType.completed,
                ),
              );
              return DesktopGenerationAcknowledgement(
                generationId: request.generationId,
                accepted: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );

      await service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'First',
            ),
          )
          .drain<void>();
      await service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'Second',
            ),
          )
          .drain<void>();

      expect(host.handshakeCount, 1);
      expect(host.loadModelCount, 1);
    },
  );

  test(
    'retries a failed model load without repeating a valid handshake',
    () async {
      final host = RecordingDesktopHostService(
        loadFailuresRemaining: 1,
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 0,
                  type: HostGenerationEventType.started,
                ),
              );
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 1,
                  type: HostGenerationEventType.completed,
                ),
              );
              return DesktopGenerationAcknowledgement(
                generationId: request.generationId,
                accepted: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      const request = GenerationRequest(
        conversationId: ConversationId('conversation-1'),
        prompt: 'Retry',
      );

      await expectLater(
        service.generate(request),
        emitsError(
          isA<ConversationFailure>().having(
            (failure) => failure.message,
            'message',
            DesktopHostFailureCode.modelLoadFailed.userSafeMessage,
          ),
        ),
      );
      await service.generate(request).drain<void>();

      expect(host.handshakeCount, 1);
      expect(host.loadModelCount, 2);
    },
  );

  test(
    'sends the exact generation payload and rejects a mismatched ack',
    () async {
      final host = RecordingDesktopHostService(
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              return const DesktopGenerationAcknowledgement(
                generationId: 'wrong-generation',
                accepted: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      const request = GenerationRequest(
        conversationId: ConversationId('conversation-42'),
        prompt: 'Exact private prompt',
      );

      await expectLater(
        service.generate(request).timeout(const Duration(milliseconds: 100)),
        emitsError(
          isA<ConversationFailure>().having(
            (failure) => failure.message,
            'message',
            DesktopHostFailureCode.protocolMismatch.userSafeMessage,
          ),
        ),
      );

      final payload = host.generationRequests.single;
      expect(payload.generationId, 'litert-generation-1');
      expect(payload.sessionId, 'conversation-42');
      // The question is carried verbatim, behind an instruction to answer
      // in prose. Without it the model wrote Markdown, which shows its own
      // asterisks on screen and has to be stripped again before speech.
      expect(payload.prompt, endsWith('Exact private prompt'));
      expect(payload.prompt, contains('No Markdown'));
      expect(payload.context, isEmpty);
      expect(payload.temperature, 0.25);
      expect(payload.topP, 0.9);
      expect(payload.maxTokens, 128);
      expect(payload.seed, 7);
    },
  );

  test(
    'cancels the exact active generation and fences late native events',
    () async {
      final host = RecordingDesktopHostService(
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 0,
                  type: HostGenerationEventType.started,
                ),
              );
              return DesktopGenerationAcknowledgement(
                generationId: request.generationId,
                accepted: true,
              );
            },
        onCancel:
            (RecordingDesktopHostService host, String generationId) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: generationId,
                  sequence: 1,
                  type: HostGenerationEventType.delta,
                  delta: 'late during cancel',
                ),
              );
              return DesktopCancellationAcknowledgement(
                generationId: generationId,
                acknowledged: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      final events = <GenerationEvent>[];
      final started = Completer<GenerationId>();
      final subscription = service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'Cancel',
            ),
          )
          .listen((event) {
            events.add(event);
            if (event case GenerationStarted(:final generation)) {
              started.complete(generation.id);
            }
          });
      final generationId = await started.future;

      await service.cancel(generationId);
      await service.cancel(generationId);
      host.emit(
        DesktopGenerationEvent(
          generationId: generationId.value,
          sequence: 2,
          type: HostGenerationEventType.completed,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(host.cancelledGenerationIds, <String>[generationId.value]);
      expect(events, hasLength(1));
      expect(events.single, isA<GenerationStarted>());
    },
  );

  test(
    'dispose cancels, resets, and unloads once without disposing host',
    () async {
      final host = RecordingDesktopHostService(
        onStart:
            (
              RecordingDesktopHostService host,
              DesktopGenerationRequest request,
            ) async {
              host.emit(
                DesktopGenerationEvent(
                  generationId: request.generationId,
                  sequence: 0,
                  type: HostGenerationEventType.started,
                ),
              );
              return DesktopGenerationAcknowledgement(
                generationId: request.generationId,
                accepted: true,
              );
            },
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      final started = Completer<void>();
      final subscription = service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-dispose'),
              prompt: 'Dispose',
            ),
          )
          .listen((event) {
            if (event is GenerationStarted && !started.isCompleted) {
              started.complete();
            }
          });
      await started.future;

      await service.dispose();
      await service.dispose();
      await subscription.cancel();

      expect(host.lifecycleOperations, <String>[
        'cancel:litert-generation-1',
        'reset:conversation-dispose',
        'unload',
      ]);
      expect(host.disposeCount, 0);
      expect(host.eventListenerCount, 0);
    },
  );

  test('overlapping dispose calls share one teardown sequence', () async {
    final host = RecordingDesktopHostService(
      onStart:
          (
            RecordingDesktopHostService host,
            DesktopGenerationRequest request,
          ) async {
            host.emit(
              DesktopGenerationEvent(
                generationId: request.generationId,
                sequence: 0,
                type: HostGenerationEventType.started,
              ),
            );
            return DesktopGenerationAcknowledgement(
              generationId: request.generationId,
              accepted: true,
            );
          },
    );
    final service = PigeonInferenceService(
      desktopHostService: host,
      config: testModelConfig,
    );
    final started = Completer<void>();
    final subscription = service
        .generate(
          const GenerationRequest(
            conversationId: ConversationId('conversation-dispose'),
            prompt: 'Dispose',
          ),
        )
        .listen((event) {
          if (event is GenerationStarted && !started.isCompleted) {
            started.complete();
          }
        });
    await started.future;

    final first = service.dispose();
    final second = service.dispose();
    await Future.wait<void>(<Future<void>>[first, second]);
    await subscription.cancel();

    expect(host.lifecycleOperations, <String>[
      'cancel:litert-generation-1',
      'reset:conversation-dispose',
      'unload',
    ]);
    expect(host.disposeCount, 0);
  });
  test(
    'warmUp loads the model once so the first prompt does not pay for it',
    () async {
      final host = RecordingDesktopHostService();
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );

      await service.warmUp();
      await service.warmUp();

      expect(host.handshakeCount, 1);
      expect(host.loadModelCount, 1);

      final events = <GenerationEvent>[];
      final subscription = service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'Hello',
            ),
          )
          .listen(events.add);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(
        host.loadModelCount,
        1,
        reason: 'A warmed service must not reload on the first generation.',
      );
      await service.dispose();
    },
  );

  test(
    'a cancel the host cannot acknowledge is a generation already gone',
    () async {
      // The native side answers acknowledged: false for exactly one reason —
      // it is not running this generation. That is what "make it stop" was
      // asking for, so it is the successful outcome, not a failure. Treating
      // it as one threw out of a caller that cannot catch it: the voice
      // controller yields to the user with unawaited(stop()), and every
      // barge-in takes this path.
      final host = RecordingDesktopHostService(
        onCancel:
            (RecordingDesktopHostService host, String generationId) async =>
                DesktopCancellationAcknowledgement(
                  generationId: generationId,
                  acknowledged: false,
                ),
      );
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      final errors = <Object>[];
      final started = Completer<GenerationId>();
      final subscription = service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'Cancel',
            ),
          )
          .listen((event) {
            if (event case GenerationStarted(:final generation)) {
              started.complete(generation.id);
            }
          }, onError: errors.add);
      await Future<void>.delayed(Duration.zero);
      host.emit(
        DesktopGenerationEvent(
          generationId: 'litert-generation-1',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );
      final generationId = await started.future;

      await expectLater(service.cancel(generationId), completes);
      expect(errors, isEmpty);

      await subscription.cancel();
    },
  );

  test(
    'a generation cancelled before it reached the host never starts',
    () async {
      // Barging in during prefill cancels while readiness is still loading the
      // model, seconds before the start goes out. Sending it anyway leaves a
      // native generation nobody is listening to and nobody will cancel; it
      // holds the runtime's single slot until it burns its whole token budget,
      // and every turn in between is rejected as busy.
      final host = RecordingDesktopHostService()..loadGate = Completer<void>();
      final service = PigeonInferenceService(
        desktopHostService: host,
        config: testModelConfig,
      );
      final errors = <Object>[];
      final subscription = service
          .generate(
            const GenerationRequest(
              conversationId: ConversationId('conversation-1'),
              prompt: 'Cancel during prefill',
            ),
          )
          .listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      final Future<void> cancelled = subscription.cancel();
      host.loadGate!.complete();
      await cancelled;
      await Future<void>.delayed(Duration.zero);

      expect(host.generationRequests, isEmpty);
      expect(errors, isEmpty);
    },
  );

  test('a start that outran its cancel is taken back', () async {
    // The cancel and the start crossed on the wire: the host had not
    // registered the generation when it was asked to cancel, then accepted
    // the start a moment later. Nothing else will ever cancel it, so the
    // start has to be undone here.
    final startGate = Completer<void>();
    var hostHasGeneration = false;
    final host = RecordingDesktopHostService(
      onStart:
          (
            RecordingDesktopHostService host,
            DesktopGenerationRequest request,
          ) async {
            await startGate.future;
            hostHasGeneration = true;
            return DesktopGenerationAcknowledgement(
              generationId: request.generationId,
              accepted: true,
            );
          },
      onCancel: (RecordingDesktopHostService host, String generationId) async =>
          DesktopCancellationAcknowledgement(
            generationId: generationId,
            acknowledged: hostHasGeneration,
          ),
    );
    final service = PigeonInferenceService(
      desktopHostService: host,
      config: testModelConfig,
    );
    final errors = <Object>[];
    final subscription = service
        .generate(
          const GenerationRequest(
            conversationId: ConversationId('conversation-1'),
            prompt: 'Cancel mid-start',
          ),
        )
        .listen((_) {}, onError: errors.add);
    await Future<void>.delayed(Duration.zero);

    final Future<void> cancelled = subscription.cancel();
    startGate.complete();
    await cancelled;
    await Future<void>.delayed(Duration.zero);

    expect(host.hostCallLog, <String>[
      'start:litert-generation-1',
      'cancel:litert-generation-1',
      'cancel:litert-generation-1',
    ]);
    expect(errors, isEmpty);
  });

  test('the instruction is written in the language of the question', () async {
    // A small model answers in the language it was instructed in. An English
    // preamble in front of a Chinese question turned every reply English,
    // however plainly the preamble asked for the language of the question —
    // the instruction is simply the strongest signal in the prompt.
    final host = RecordingDesktopHostService();
    final service = PigeonInferenceService(
      desktopHostService: host,
      config: testModelConfig,
    );

    final chinese = service
        .generate(
          const GenerationRequest(
            conversationId: ConversationId('conversation-1'),
            prompt: '你可以跟我說一下意大利麵的做法。',
          ),
        )
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);
    final english = service
        .generate(
          const GenerationRequest(
            conversationId: ConversationId('conversation-1'),
            prompt: 'How do I make spaghetti?',
          ),
        )
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);

    expect(host.generationRequests, hasLength(2));
    // "Markdown" is the term in both, so the tell is the surrounding prose.
    expect(host.generationRequests[0].prompt, contains('口語回答'));
    // Traditional, not Simplified: the model answered 咱们/东西/开发 to a
    // Traditional question because nothing said which script to use.
    expect(host.generationRequests[0].prompt, contains('繁體'));
    // The question arrives from a speech recogniser, so it can be misheard.
    // Saying so costs nothing and lets the answer interpret rather than take
    // "Frant" literally and explain a thing that does not exist.
    expect(host.generationRequests[0].prompt, contains('語音辨識'));
    expect(
      host.generationRequests[0].prompt,
      isNot(contains('plain spoken prose')),
    );
    expect(host.generationRequests[1].prompt, contains('plain spoken prose'));
    expect(host.generationRequests[1].prompt, isNot(contains('口語回答')));

    await chinese.cancel();
    await english.cancel();
  });

  test('warmUp reports a failure instead of hiding it', () async {
    final host = RecordingDesktopHostService(loadFailuresRemaining: 1);
    final service = PigeonInferenceService(
      desktopHostService: host,
      config: testModelConfig,
    );

    await expectLater(service.warmUp(), throwsA(isA<DesktopHostFailure>()));
    await service.dispose();
  });
}

const LocalModelConfig testModelConfig = LocalModelConfig(
  modelId: 'model-1',
  modelPath: '/models/model-1.litertlm',
  contextSize: 4096,
  temperature: 0.25,
  topP: 0.9,
  maxTokens: 128,
  seed: 7,
);

typedef StartHandler =
    Future<DesktopGenerationAcknowledgement> Function(
      RecordingDesktopHostService host,
      DesktopGenerationRequest request,
    );

typedef CancelHandler =
    Future<DesktopCancellationAcknowledgement> Function(
      RecordingDesktopHostService host,
      String generationId,
    );

final class RecordingDesktopHostService implements DesktopHostService {
  RecordingDesktopHostService({
    this.onStart,
    this.onCancel,
    this.loadFailuresRemaining = 0,
  }) {
    _events = StreamController<DesktopGenerationEvent>.broadcast(
      sync: true,
      onListen: () => eventListenerCount += 1,
      onCancel: () => eventListenerCount -= 1,
    );
  }

  final StartHandler? onStart;
  final CancelHandler? onCancel;
  int loadFailuresRemaining;

  /// Held open to keep readiness — and so the start behind it — in flight.
  Completer<void>? loadGate;

  /// Starts and cancels in the order the host was asked for them.
  ///
  /// [lifecycleOperations] deliberately omits starts, and several tests
  /// assert its exact contents; ordering between the two calls needs its own
  /// log.
  final List<String> hostCallLog = <String>[];
  late final StreamController<DesktopGenerationEvent> _events;
  int eventListenerCount = 0;
  int? eventListenerCountAtStart;
  int handshakeCount = 0;
  int loadModelCount = 0;
  int disposeCount = 0;
  final List<DesktopGenerationRequest> generationRequests =
      <DesktopGenerationRequest>[];
  final List<String> cancelledGenerationIds = <String>[];
  final List<String> lifecycleOperations = <String>[];

  void emit(DesktopGenerationEvent event) {
    _events.add(event);
  }

  @override
  Stream<DesktopGenerationEvent> get generationEvents => _events.stream;

  @override
  Future<DesktopRuntimeCapabilities> handshake() async {
    handshakeCount += 1;
    return const DesktopRuntimeCapabilities(
      schemaVersion: DesktopHostService.schemaVersion,
      runtimeName: 'litert-lm',
      supportsStreaming: true,
      supportsCancellation: true,
    );
  }

  @override
  Future<DesktopModelLoadResult> loadModel(DesktopModelRequest model) async {
    loadModelCount += 1;
    final Completer<void>? gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
    if (loadFailuresRemaining > 0) {
      loadFailuresRemaining -= 1;
      throw const DesktopHostFailure(DesktopHostFailureCode.modelLoadFailed);
    }
    return DesktopModelLoadResult(modelId: model.modelId, loaded: true);
  }

  @override
  Future<DesktopGenerationAcknowledgement> startGeneration(
    DesktopGenerationRequest generation,
  ) async {
    eventListenerCountAtStart = eventListenerCount;
    generationRequests.add(generation);
    hostCallLog.add('start:${generation.generationId}');
    return onStart?.call(this, generation) ??
        DesktopGenerationAcknowledgement(
          generationId: generation.generationId,
          accepted: true,
        );
  }

  @override
  Future<DesktopCancellationAcknowledgement> cancelGeneration(
    String generationId,
  ) async {
    cancelledGenerationIds.add(generationId);
    lifecycleOperations.add('cancel:$generationId');
    hostCallLog.add('cancel:$generationId');
    return onCancel?.call(this, generationId) ??
        DesktopCancellationAcknowledgement(
          generationId: generationId,
          acknowledged: true,
        );
  }

  @override
  Future<DesktopOperationCompletion> resetSession(String sessionId) async {
    lifecycleOperations.add('reset:$sessionId');
    return const DesktopOperationCompletion(completed: true);
  }

  @override
  Future<DesktopOperationCompletion> unloadModel() async {
    lifecycleOperations.add('unload');
    return const DesktopOperationCompletion(completed: true);
  }

  @override
  final ValueNotifier<DesktopPresentation> presentation =
      ValueNotifier<DesktopPresentation>(DesktopPresentation.expanded);

  @override
  Future<void> setPresentation(DesktopPresentation mode) async {
    presentation.value = mode;
  }

  @override
  Future<void> moveWindowBy(Offset delta) async {}

  @override
  Stream<DesktopPresentation> get presentationRequests =>
      const Stream<DesktopPresentation>.empty();

  @override
  Stream<void> get settingsRequests => const Stream<void>.empty();

  @override
  Stream<DesktopTransitionGeometry> get geometryChanges =>
      const Stream<DesktopTransitionGeometry>.empty();

  @override
  Future<String> chooseModelFile() async => '';

  @override
  Future<void> setWindowBehaviour({
    required bool keepOrbOnTop,
    required bool followAcrossSpaces,
  }) async {}

  @override
  Future<DesktopTransitionGeometry> presentationGeometry() async =>
      beginPresentationTransition(DesktopPresentation.orb);

  @override
  Future<DesktopTransitionGeometry> beginPresentationTransition(
    DesktopPresentation target,
  ) async => DesktopTransitionGeometry(
    size: const Size.square(168),
    conversation: const Rect.fromLTWH(0, 0, 168, 168),
    orb: const Rect.fromLTWH(0, 0, 148, 148),
  );

  @override
  Future<void> endPresentationTransition(DesktopPresentation mode) async {}

  @override
  Future<void> showPanel() async {}

  @override
  Future<void> hidePanel() async {}

  @override
  Future<void> togglePanel() async {}

  @override
  Future<void> dispose() async {
    disposeCount += 1;
    await _events.close();
  }
}
