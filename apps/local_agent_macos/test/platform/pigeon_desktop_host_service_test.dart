import 'package:agent_core/agent_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/generated/desktop_host_api.g.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';
import 'package:local_agent_macos/platform/pigeon_desktop_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PigeonDesktopHostService', () {
    test('round-trips every typed local-runtime lifecycle operation', () async {
      final hostApi = RecordingLifecycleDesktopHostApi();
      final service = PigeonDesktopHostService(
        hostApi: hostApi,
        now: () => DateTime.utc(2026, 7, 27),
        registerEventApi: false,
      );

      final DesktopRuntimeCapabilities capabilities = await service.handshake();
      final DesktopModelLoadResult loadResult = await service.loadModel(
        const DesktopModelRequest(
          modelId: 'deterministic-model',
          modelPath: '/models/deterministic.bin',
          contextSize: 4096,
        ),
      );
      final DesktopGenerationAcknowledgement startResult = await service
          .startGeneration(
            const DesktopGenerationRequest(
              generationId: 'generation-1',
              sessionId: 'session-1',
              prompt: 'private prompt',
              context: <String>['private context'],
              history: <DesktopConversationTurn>[
                DesktopConversationTurn(
                  role: TurnRole.user,
                  text: 'what was asked before',
                ),
                DesktopConversationTurn(
                  role: TurnRole.assistant,
                  text: 'what was answered before',
                ),
              ],
              temperature: 0.25,
              topP: 0.9,
              maxTokens: 128,
              seed: 7,
            ),
          );
      final DesktopCancellationAcknowledgement cancelResult = await service
          .cancelGeneration('generation-1');
      final DesktopOperationCompletion resetResult = await service.resetSession(
        'session-1',
      );
      final DesktopOperationCompletion unloadResult = await service
          .unloadModel();

      expect(
        capabilities,
        const DesktopRuntimeCapabilities(
          schemaVersion: DesktopHostService.schemaVersion,
          runtimeName: 'deterministic',
          supportsStreaming: true,
          supportsCancellation: true,
        ),
      );
      expect(
        loadResult,
        const DesktopModelLoadResult(
          modelId: 'deterministic-model',
          loaded: true,
        ),
      );
      expect(
        startResult,
        const DesktopGenerationAcknowledgement(
          generationId: 'generation-1',
          accepted: true,
        ),
      );
      expect(
        cancelResult,
        const DesktopCancellationAcknowledgement(
          generationId: 'generation-1',
          acknowledged: true,
        ),
      );
      expect(resetResult, const DesktopOperationCompletion(completed: true));
      expect(unloadResult, const DesktopOperationCompletion(completed: true));

      expect(hostApi.requests, hasLength(6));
      for (final HostRequest request in hostApi.requests) {
        expect(request.schemaVersion, DesktopHostService.schemaVersion);
        expect(request.requestId, isNotEmpty);
        expect(request.timestampMicros, 1785110400000000);
      }
      expect(
        hostApi.model,
        HostModelRequest(
          modelId: 'deterministic-model',
          modelPath: '/models/deterministic.bin',
          contextSize: 4096,
        ),
      );
      expect(
        hostApi.generation,
        HostGenerationRequest(
          generationId: 'generation-1',
          sessionId: 'session-1',
          prompt: 'private prompt',
          context: <String>['private context'],
          history: <HostConversationTurn>[
            HostConversationTurn(
              role: HostTurnRole.user,
              text: 'what was asked before',
            ),
            HostConversationTurn(
              role: HostTurnRole.assistant,
              text: 'what was answered before',
            ),
          ],
          temperature: 0.25,
          topP: 0.9,
          maxTokens: 128,
          seed: 7,
        ),
      );
      expect(hostApi.cancelledGenerationId, 'generation-1');
      expect(hostApi.resetSessionId, 'session-1');
    });

    test('maps every platform error code to a typed app failure', () async {
      for (final DesktopHostFailureCode expected
          in DesktopHostFailureCode.values) {
        final service = PigeonDesktopHostService(
          hostApi: ThrowingDesktopHostApi(expected.pigeonCode),
          registerEventApi: false,
        );

        await expectLater(
          service.showPanel(),
          throwsA(
            isA<DesktopHostFailure>().having(
              (DesktopHostFailure failure) => failure.code,
              'code',
              expected,
            ),
          ),
        );
      }
    });

    test('replaces native error text with stable user-safe messages', () async {
      const Map<DesktopHostFailureCode, String> expectedMessages =
          <DesktopHostFailureCode, String>{
            DesktopHostFailureCode.modelNotInstalled:
                'The local model is not installed.',
            DesktopHostFailureCode.modelLoadFailed:
                'The local model could not be loaded.',
            DesktopHostFailureCode.runtimeUnavailable:
                'Local inference is unavailable.',
            DesktopHostFailureCode.generationBusy:
                'Another response is already being generated.',
            DesktopHostFailureCode.generationFailed: 'Local inference failed.',
            DesktopHostFailureCode.cancelled: 'The response was cancelled.',
            DesktopHostFailureCode.protocolMismatch:
                'The desktop host protocol is incompatible.',
          };

      for (final MapEntry<DesktopHostFailureCode, String> entry
          in expectedMessages.entries) {
        final service = PigeonDesktopHostService(
          hostApi: ThrowingDesktopHostApi(entry.key.pigeonCode),
          registerEventApi: false,
        );

        await expectLater(
          service.showPanel(),
          throwsA(
            isA<DesktopHostFailure>().having(
              (DesktopHostFailure failure) => failure.message,
              'message',
              entry.value,
            ),
          ),
        );
      }
    });

    test('exposes stable recoverability for every typed failure', () {
      const Map<DesktopHostFailureCode, bool> expectedRecoverability =
          <DesktopHostFailureCode, bool>{
            DesktopHostFailureCode.modelNotInstalled: true,
            DesktopHostFailureCode.modelLoadFailed: true,
            DesktopHostFailureCode.runtimeUnavailable: true,
            DesktopHostFailureCode.generationBusy: true,
            DesktopHostFailureCode.generationFailed: true,
            DesktopHostFailureCode.cancelled: false,
            DesktopHostFailureCode.protocolMismatch: false,
          };

      for (final MapEntry<DesktopHostFailureCode, bool> entry
          in expectedRecoverability.entries) {
        final DesktopHostFailure failure = DesktopHostFailure(entry.key);

        expect(failure.isRecoverable, entry.value);
      }
    });

    test('normalizes every protocol rejection to one stable triple', () {
      final List<void Function()> protocolRejections = <void Function()>[
        () =>
            PigeonDesktopHostService(
              hostApi: RecordingDesktopHostApi(),
              registerEventApi: false,
            ).acceptGenerationEvent(
              HostGenerationEvent(
                schemaVersion: DesktopHostService.schemaVersion + 1,
                generationId: 'generation-1',
                sequence: 0,
                type: HostGenerationEventType.started,
              ),
            ),
        () =>
            PigeonDesktopHostService(
              hostApi: RecordingDesktopHostApi(),
              registerEventApi: false,
            ).acceptGenerationEvent(
              HostGenerationEvent(
                schemaVersion: DesktopHostService.schemaVersion,
                generationId: 'generation-1',
                sequence: 0,
                type: HostGenerationEventType.delta,
                delta: 'unexpected',
              ),
            ),
      ];

      for (final void Function() reject in protocolRejections) {
        expect(
          reject,
          throwsA(
            isA<DesktopHostFailure>()
                .having(
                  (DesktopHostFailure failure) => failure.code,
                  'code',
                  DesktopHostFailureCode.protocolMismatch,
                )
                .having(
                  (DesktopHostFailure failure) => failure.message,
                  'message',
                  'The desktop host protocol is incompatible.',
                )
                .having(
                  (DesktopHostFailure failure) => failure.isRecoverable,
                  'isRecoverable',
                  isFalse,
                ),
          ),
        );
      }
    });

    test('maps every failed-event code to its stable Dart triple', () {
      const Map<
        HostFailureCode,
        ({DesktopHostFailureCode code, String message, bool isRecoverable})
      >
      expected =
          <
            HostFailureCode,
            ({DesktopHostFailureCode code, String message, bool isRecoverable})
          >{
            HostFailureCode.modelNotInstalled: (
              code: DesktopHostFailureCode.modelNotInstalled,
              message: 'The local model is not installed.',
              isRecoverable: true,
            ),
            HostFailureCode.modelLoadFailed: (
              code: DesktopHostFailureCode.modelLoadFailed,
              message: 'The local model could not be loaded.',
              isRecoverable: true,
            ),
            HostFailureCode.runtimeUnavailable: (
              code: DesktopHostFailureCode.runtimeUnavailable,
              message: 'Local inference is unavailable.',
              isRecoverable: true,
            ),
            HostFailureCode.generationBusy: (
              code: DesktopHostFailureCode.generationBusy,
              message: 'Another response is already being generated.',
              isRecoverable: true,
            ),
            HostFailureCode.generationFailed: (
              code: DesktopHostFailureCode.generationFailed,
              message: 'Local inference failed.',
              isRecoverable: true,
            ),
            HostFailureCode.cancelled: (
              code: DesktopHostFailureCode.cancelled,
              message: 'The response was cancelled.',
              isRecoverable: false,
            ),
            HostFailureCode.protocolMismatch: (
              code: DesktopHostFailureCode.protocolMismatch,
              message: 'The desktop host protocol is incompatible.',
              isRecoverable: false,
            ),
          };

      for (final MapEntry<
            HostFailureCode,
            ({DesktopHostFailureCode code, String message, bool isRecoverable})
          >
          entry
          in expected.entries) {
        final service = PigeonDesktopHostService(
          hostApi: RecordingDesktopHostApi(),
          registerEventApi: false,
        );
        service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-1',
            sequence: 0,
            type: HostGenerationEventType.started,
          ),
        );

        final DesktopGenerationEvent event = service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-1',
            sequence: 1,
            type: HostGenerationEventType.failed,
            failureCode: entry.key,
            message: 'Native stack: prompt=private user text',
          ),
        );

        expect(event.failureCode, entry.value.code);
        expect(event.message, entry.value.message);
        expect(event.failureCode!.isRecoverable, entry.value.isRecoverable);
      }
    });

    test('rejects an event with a mismatched schema', () async {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );

      expect(
        () => service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion + 1,
            generationId: 'generation-1',
            sequence: 0,
            type: HostGenerationEventType.started,
          ),
        ),
        throwsA(
          isA<DesktopHostFailure>().having(
            (DesktopHostFailure failure) => failure.code,
            'code',
            DesktopHostFailureCode.protocolMismatch,
          ),
        ),
      );
    });

    test('rejects a delta before its generation starts', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );

      expect(
        () => service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-1',
            sequence: 0,
            type: HostGenerationEventType.delta,
            delta: 'unexpected',
          ),
        ),
        throwsA(
          isA<DesktopHostFailure>().having(
            (DesktopHostFailure failure) => failure.code,
            'code',
            DesktopHostFailureCode.protocolMismatch,
          ),
        ),
      );
    });

    test(
      'rejects duplicate and decreasing sequence numbers per generation',
      () {
        final service = PigeonDesktopHostService(
          hostApi: RecordingDesktopHostApi(),
          registerEventApi: false,
        );

        service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-1',
            sequence: 0,
            type: HostGenerationEventType.started,
          ),
        );
        service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-1',
            sequence: 2,
            type: HostGenerationEventType.delta,
            delta: 'A',
          ),
        );

        for (final int staleSequence in <int>[2, 1]) {
          expect(
            () => service.acceptGenerationEvent(
              HostGenerationEvent(
                schemaVersion: DesktopHostService.schemaVersion,
                generationId: 'generation-1',
                sequence: staleSequence,
                type: HostGenerationEventType.delta,
                delta: 'stale',
              ),
            ),
            throwsA(
              isA<DesktopHostFailure>().having(
                (DesktopHostFailure failure) => failure.code,
                'code',
                DesktopHostFailureCode.protocolMismatch,
              ),
            ),
          );
        }
      },
    );

    test('rejects a different generation while one is active', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );

      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );

      expect(
        () => service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-2',
            sequence: 0,
            type: HostGenerationEventType.started,
          ),
        ),
        throwsA(
          isA<DesktopHostFailure>().having(
            (DesktopHostFailure failure) => failure.code,
            'code',
            DesktopHostFailureCode.protocolMismatch,
          ),
        ),
      );
    });

    test('tracks monotonic ordering across sequential generations', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );

      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );
      final first = service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 3,
          type: HostGenerationEventType.delta,
          delta: 'one',
        ),
      );
      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 4,
          type: HostGenerationEventType.completed,
        ),
      );
      final second = service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-2',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );

      expect(first.generationId, 'generation-1');
      expect(second.generationId, 'generation-2');
    });

    test('rejects stale events after a generation terminal', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );
      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );
      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 1,
          type: HostGenerationEventType.completed,
        ),
      );
      service.acceptGenerationEvent(
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-2',
          sequence: 0,
          type: HostGenerationEventType.started,
        ),
      );

      for (final HostGenerationEvent staleEvent in <HostGenerationEvent>[
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 2,
          type: HostGenerationEventType.delta,
          delta: 'late',
        ),
        HostGenerationEvent(
          schemaVersion: DesktopHostService.schemaVersion,
          generationId: 'generation-1',
          sequence: 3,
          type: HostGenerationEventType.completed,
        ),
      ]) {
        expect(
          () => service.acceptGenerationEvent(staleEvent),
          throwsA(
            isA<DesktopHostFailure>().having(
              (DesktopHostFailure failure) => failure.code,
              'code',
              DesktopHostFailureCode.protocolMismatch,
            ),
          ),
        );
      }
    });

    test('evicts the oldest stale ID while rejecting recent stale IDs', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
      );

      for (int index = 0; index <= 32; index += 1) {
        _completeGeneration(service, 'generation-$index');
      }

      _completeGeneration(service, 'generation-0');

      expect(
        () => service.acceptGenerationEvent(
          HostGenerationEvent(
            schemaVersion: DesktopHostService.schemaVersion,
            generationId: 'generation-32',
            sequence: 2,
            type: HostGenerationEventType.started,
          ),
        ),
        throwsA(
          isA<DesktopHostFailure>().having(
            (DesktopHostFailure failure) => failure.code,
            'code',
            DesktopHostFailureCode.protocolMismatch,
          ),
        ),
      );
    });
  });
}

void _completeGeneration(
  PigeonDesktopHostService service,
  String generationId,
) {
  service.acceptGenerationEvent(
    HostGenerationEvent(
      schemaVersion: DesktopHostService.schemaVersion,
      generationId: generationId,
      sequence: 0,
      type: HostGenerationEventType.started,
    ),
  );
  service.acceptGenerationEvent(
    HostGenerationEvent(
      schemaVersion: DesktopHostService.schemaVersion,
      generationId: generationId,
      sequence: 1,
      type: HostGenerationEventType.completed,
    ),
  );
}

final class ThrowingDesktopHostApi extends DesktopHostApi {
  ThrowingDesktopHostApi(this.code);

  final String code;

  @override
  Future<void> showPanel(HostRequest request) {
    throw PlatformException(
      code: code,
      message: 'Native stack: prompt=private user text',
    );
  }
}

final class RecordingDesktopHostApi extends DesktopHostApi {
  @override
  Future<void> showPanel(HostRequest request) async {}
}

final class RecordingLifecycleDesktopHostApi extends DesktopHostApi {
  final List<HostRequest> requests = <HostRequest>[];
  HostModelRequest? model;
  HostGenerationRequest? generation;
  String? cancelledGenerationId;
  String? resetSessionId;

  @override
  Future<HostHandshakeResult> handshake(HostRequest request) async {
    requests.add(request);
    return HostHandshakeResult(
      schemaVersion: DesktopHostService.schemaVersion,
      runtimeName: 'deterministic',
      supportsStreaming: true,
      supportsCancellation: true,
    );
  }

  @override
  Future<HostModelLoadResult> loadModel(
    HostRequest request,
    HostModelRequest model,
  ) async {
    requests.add(request);
    this.model = model;
    return HostModelLoadResult(modelId: model.modelId, loaded: true);
  }

  @override
  Future<HostGenerationAcknowledgement> startGeneration(
    HostRequest request,
    HostGenerationRequest generation,
  ) async {
    requests.add(request);
    this.generation = generation;
    return HostGenerationAcknowledgement(
      generationId: generation.generationId,
      accepted: true,
    );
  }

  @override
  Future<HostCancellationAcknowledgement> cancelGeneration(
    HostRequest request,
    String generationId,
  ) async {
    requests.add(request);
    cancelledGenerationId = generationId;
    return HostCancellationAcknowledgement(
      generationId: generationId,
      acknowledged: true,
    );
  }

  @override
  Future<HostOperationCompletion> resetSession(
    HostRequest request,
    String sessionId,
  ) async {
    requests.add(request);
    resetSessionId = sessionId;
    return HostOperationCompletion(completed: true);
  }

  @override
  Future<HostOperationCompletion> unloadModel(HostRequest request) async {
    requests.add(request);
    return HostOperationCompletion(completed: true);
  }
}
