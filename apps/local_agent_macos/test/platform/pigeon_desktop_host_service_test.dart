import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/generated/desktop_host_api.g.dart';
import 'package:local_agent_macos/platform/desktop_host_service.dart';
import 'package:local_agent_macos/platform/pigeon_desktop_host_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PigeonDesktopHostService', () {
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
        final DesktopHostFailure failure = DesktopHostFailure(
          entry.key,
          entry.key.userSafeMessage,
        );

        expect(failure.isRecoverable, entry.value);
      }
    });

    test('sanitizes native failed-event text at the adapter boundary', () {
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
          failureCode: HostFailureCode.modelLoadFailed,
          message: 'Native stack: prompt=private user text',
        ),
      );

      expect(event.failureCode, DesktopHostFailureCode.modelLoadFailed);
      expect(event.message, 'The local model could not be loaded.');
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
  });
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
