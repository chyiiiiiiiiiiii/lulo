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

    test('tracks monotonic ordering independently for each generation', () {
      final service = PigeonDesktopHostService(
        hostApi: RecordingDesktopHostApi(),
        registerEventApi: false,
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
  });
}

final class ThrowingDesktopHostApi extends DesktopHostApi {
  ThrowingDesktopHostApi(this.code);

  final String code;

  @override
  Future<void> showPanel(HostRequest request) {
    throw PlatformException(code: code, message: 'safe message');
  }
}

final class RecordingDesktopHostApi extends DesktopHostApi {
  @override
  Future<void> showPanel(HostRequest request) async {}
}
