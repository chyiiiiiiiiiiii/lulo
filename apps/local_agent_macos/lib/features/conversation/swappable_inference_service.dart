import 'dart:async';

import 'package:agent_core/agent_core.dart';

import 'inference_service.dart';

/// An inference service together with the way it is released.
///
/// Each kind of service is torn down differently — a local runtime has a model
/// to unload and a host to let go of, the built-in preview has neither — and
/// the thing holding one has no business knowing which it has. Pairing the
/// service with its own release is what lets it be exchanged for another.
final class OwnedInferenceService {
  /// Creates a service paired with the way to release it.
  const OwnedInferenceService({required this.service, required this.release});

  /// The service itself.
  final InferenceService service;

  /// Releases everything that service owns.
  final Future<void> Function() release;
}

/// The inference the conversation talks to, with the model changeable beneath.
///
/// The conversation and its repository are built once at launch and hold one
/// inference service for as long as they live, so changing model used to mean
/// restarting the app. This sits in that one place and exchanges what is behind
/// it, which is the only part that actually has to change.
final class SwappableInferenceService implements InferenceService {
  /// Creates the service, starting from [initial].
  SwappableInferenceService(OwnedInferenceService initial) : _current = initial;

  OwnedInferenceService? _current;
  Future<void>? _swap;
  int _changesUnderway = 0;

  @override
  Stream<GenerationEvent> generate(GenerationRequest request) {
    final OwnedInferenceService? current = _current;
    // Fenced the moment a change is asked for rather than when it gets its
    // turn to run: the prompt that arrives in between belongs to neither model
    // and must not be answered by the one on its way out.
    if (current == null || _changesUnderway > 0) {
      return Stream<GenerationEvent>.error(_nothingToAsk);
    }
    return current.service.generate(request);
  }

  @override
  Future<void> cancel(GenerationId generationId) async {
    await _current?.service.cancel(generationId);
  }

  /// Releases the current model and puts the one [build] returns in its place.
  ///
  /// Released first and built second, deliberately: these models are gigabytes
  /// and holding two at once to save a few seconds of overlap is the wrong
  /// trade. For the seconds in between there is genuinely nothing to ask, and
  /// [generate] says so rather than failing as though something broke.
  ///
  /// A [build] that throws leaves nothing installed. The old model has already
  /// gone by then and cannot be brought back for free, and pretending
  /// otherwise would leave the user talking to the model they thought they had
  /// just replaced.
  Future<void> replaceWith(Future<OwnedInferenceService> Function() build) {
    _changesUnderway++;
    final Future<void>? inFlight = _swap;
    return _swap = Future<void>(() async {
      try {
        // Two changes of model in quick succession queue rather than race, or
        // the second would release a model the first is still building.
        if (inFlight != null) {
          await inFlight.catchError((Object _) {});
        }
        final OwnedInferenceService? previous = _current;
        _current = null;
        await previous?.release();
        _current = await build();
      } finally {
        _changesUnderway--;
      }
    });
  }

  /// Releases whichever model is loaded.
  Future<void> dispose() async {
    final OwnedInferenceService? current = _current;
    _current = null;
    await current?.release();
  }

  static const ConversationFailure _nothingToAsk = ConversationFailure(
    'Lulo is changing the model it thinks with. Try again in a moment.',
  );
}
