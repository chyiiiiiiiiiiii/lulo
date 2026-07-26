import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'apps/local_agent_macos/lib/generated/desktop_host_api.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'apps/local_agent_macos/macos/Runner/GeneratedDesktopHostApi.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'local_agent_macos',
  ),
)
enum HostGenerationEventType { started, delta, completed, cancelled, failed }

enum HostFailureCode {
  modelNotInstalled,
  modelLoadFailed,
  runtimeUnavailable,
  generationBusy,
  generationFailed,
  cancelled,
  protocolMismatch,
}

class HostRequest {
  HostRequest({
    required this.schemaVersion,
    required this.requestId,
    required this.timestampMicros,
  });

  int schemaVersion;
  String requestId;
  int timestampMicros;
}

class HostGenerationEvent {
  HostGenerationEvent({
    required this.schemaVersion,
    required this.generationId,
    required this.sequence,
    required this.type,
    this.delta,
    this.failureCode,
    this.message,
  });

  int schemaVersion;
  String generationId;
  int sequence;
  HostGenerationEventType type;
  String? delta;
  HostFailureCode? failureCode;
  String? message;
}

@HostApi()
abstract class DesktopHostApi {
  void showPanel(HostRequest request);

  void hidePanel(HostRequest request);

  void togglePanel(HostRequest request);
}

@FlutterApi()
abstract class DesktopHostEventApi {
  void onGenerationEvent(HostGenerationEvent event);
}
