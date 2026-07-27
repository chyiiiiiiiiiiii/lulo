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

class HostHandshakeResult {
  HostHandshakeResult({
    required this.schemaVersion,
    required this.runtimeName,
    required this.supportsStreaming,
    required this.supportsCancellation,
  });

  int schemaVersion;
  String runtimeName;
  bool supportsStreaming;
  bool supportsCancellation;
}

class HostModelRequest {
  HostModelRequest({
    required this.modelId,
    required this.modelPath,
    required this.contextSize,
  });

  String modelId;
  String modelPath;
  int contextSize;
}

class HostModelLoadResult {
  HostModelLoadResult({required this.modelId, required this.loaded});

  String modelId;
  bool loaded;
}

class HostGenerationRequest {
  HostGenerationRequest({
    required this.generationId,
    required this.sessionId,
    required this.prompt,
    required this.context,
    required this.temperature,
    required this.topP,
    required this.maxTokens,
    required this.seed,
  });

  String generationId;
  String sessionId;
  String prompt;
  List<String> context;
  double temperature;
  double topP;
  int maxTokens;
  int seed;
}

class HostGenerationAcknowledgement {
  HostGenerationAcknowledgement({
    required this.generationId,
    required this.accepted,
  });

  String generationId;
  bool accepted;
}

class HostCancellationAcknowledgement {
  HostCancellationAcknowledgement({
    required this.generationId,
    required this.acknowledged,
  });

  String generationId;
  bool acknowledged;
}

class HostOperationCompletion {
  HostOperationCompletion({required this.completed});

  bool completed;
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
  HostHandshakeResult handshake(HostRequest request);

  HostModelLoadResult loadModel(HostRequest request, HostModelRequest model);

  HostGenerationAcknowledgement startGeneration(
    HostRequest request,
    HostGenerationRequest generation,
  );

  HostCancellationAcknowledgement cancelGeneration(
    HostRequest request,
    String generationId,
  );

  HostOperationCompletion resetSession(HostRequest request, String sessionId);

  HostOperationCompletion unloadModel(HostRequest request);

  void showPanel(HostRequest request);

  void hidePanel(HostRequest request);

  void togglePanel(HostRequest request);
}

@FlutterApi()
abstract class DesktopHostEventApi {
  void onGenerationEvent(HostGenerationEvent event);
}
