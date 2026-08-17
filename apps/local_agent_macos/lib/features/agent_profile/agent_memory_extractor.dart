import 'dart:async';

import 'package:agent_core/agent_core.dart';

import '../conversation/inference_service.dart';

/// Reads each finished turn for something about the user worth keeping.
///
/// The second pass, and the reason there is one: gemma-4-E4B does not call
/// a `remember` tool — 0/5 across eleven conditions, including the one where
/// the user says 「記住我住在台南」 outright, while `search_conversations`
/// fires 5/5 in the same toolbox on the same turn. Asked instead to read one
/// sentence and say what is in it, with no tools and no persona, the same
/// model scored 15/15 recall and 0/15 false keeps. See
/// `docs/decisions/the-model-will-not-interrupt-itself-to-remember.md`.
///
/// **The runtime has one generation slot.** `LiteRTLMRuntimeBackend` refuses
/// a second `startGeneration` with `generationBusy`, so an extraction in
/// flight is the user's next question refused. Every policy in this class
/// follows from that one fact, and it is why the class exists at all rather
/// than a `then()` hung off the end of a turn:
///
/// - it runs at most one extraction at a time;
/// - a turn that arrives while one is running **replaces** whatever was
///   waiting rather than queueing behind it, because the newer turn is the
///   one worth reading and a backlog is a slot held for old news;
/// - [yieldSlot] cancels whatever is in flight and drops the backlog, and
///   the conversation calls it before every question. The user always wins
///   the slot; a memory can be extracted from the next thing they say, and
///   a question that comes back "busy" cannot be un-refused.
///
/// Nothing here reports failure to anyone. An extraction that is cancelled,
/// refused, or misread is a fact not kept, which is the same state the app
/// was in before this existed — where surfacing it would interrupt a user
/// who did not ask for any of this to happen.
final class AgentMemoryExtractor implements BetweenTurns {
  /// Creates an extractor over the runtime and the profile it writes to.
  AgentMemoryExtractor({
    required InferenceService inference,
    required AgentProfile Function() profileOf,
    required Future<void> Function(AgentProfile profile) save,
    bool Function()? enabled,
    DateTime Function() writtenAt = DateTime.now,
    this._onKept,
  }) : _runtime = inference,
       _profile = profileOf,
       _write = save,
       _enabled = enabled ?? _off,
       _clock = writtenAt;

  /// Nothing is remembered until the user says so. See [_enabled].
  static bool _off() => false;

  final InferenceService _runtime;
  final AgentProfile Function() _profile;
  final Future<void> Function(AgentProfile) _write;

  /// Whether the user has agreed to be remembered, read every turn.
  ///
  /// Off by default, and the default is the point.
  /// `docs/features/agent-profile.md` states plainly that the profile is
  /// local but plaintext, and that automatic memory writing waits on a
  /// privacy slice — storage encryption, a sensitive-category policy. That
  /// slice does not exist yet, so this ships behind a switch the user turns
  /// on, the same way `shareFrontmostApp` does: what the agent knows about
  /// them is theirs to give.
  ///
  /// Read per turn rather than held, so switching it off stops the next
  /// extraction without reloading anything.
  final bool Function() _enabled;

  /// When a memory this pass writes was written.
  ///
  /// Injected so a test can state a time instead of racing the machine's,
  /// the same way `ProfileAgentContextProvider` takes its clock.
  final DateTime Function() _clock;

  /// Told each sentence after it has actually landed in the profile.
  ///
  /// After — not before, not instead. The remember tool's measured failure
  /// was confirming a write that never happened, and a light that inherits
  /// that shape would be worse than no light. A pass that is cancelled,
  /// screened, or refused says nothing here.
  final void Function(String fact)? _onKept;

  /// The session an extraction runs in, released after every one.
  ///
  /// Fixed rather than counted, and released each time, because the runtime
  /// keeps one live conversation per session id with its own KV cache and
  /// nothing evicts them. A pass that kept its session would accumulate
  /// every turn of the day into a prompt that is supposed to be one
  /// sentence long. Runs are strictly serialised here, and the release is
  /// awaited before the next one starts, so the id is never in two places.
  static final ConversationId session = ConversationId('memory-extraction');

  /// The shortest turn worth spending a generation on.
  ///
  /// 「好」, 「嗯」, "ok" carry nothing about the user, and there are a great
  /// many of them in a spoken conversation. This is a floor on cost, not a
  /// judgement about content — the judgement is the model's.
  static const int minimumCharacters = 6;

  String? _waiting;
  String? _lastRead;
  StreamSubscription<GenerationEvent>? _running;

  /// The reply the running pass is waiting on.
  ///
  /// Held because cancelling a subscription is silent: it delivers no
  /// terminal event and no `onDone`, so a pass whose listener is torn down
  /// would wait on this forever — never releasing its session, never
  /// letting the drain loop move on. [yieldSlot] settles it by hand, which
  /// is the difference between giving the slot back and leaking it.
  Completer<bool>? _reply;
  Completer<void>? _idle;
  bool _draining = false;
  bool _disposed = false;

  /// Whether an extraction is on the runtime right now.
  bool get isRunning => _running != null;

  /// Reads [said] when the slot is free, replacing anything still waiting.
  ///
  /// Returns immediately. Call it after the answer has finished, never
  /// before: this takes the slot, and the answer needs it.
  @override
  void consider(String said) {
    if (_disposed) {
      return;
    }
    if (!_enabled()) {
      return;
    }
    final String text = said.trim();
    // The same sentence twice is the user's question being re-asked, or a
    // retry after a failure. It was already read.
    if (text.length < minimumCharacters || text == _lastRead) {
      return;
    }
    _waiting = text;
    if (_running == null) {
      unawaited(_drain());
    }
  }

  /// Gives the runtime slot back, dropping whatever was in flight or queued.
  ///
  /// Awaited by the caller before starting a question, so the cancellation
  /// has reached the host before the question's own start does — the two
  /// crossing on the wire is exactly how a turn gets refused as busy.
  @override
  Future<void> yieldSlot() async {
    _waiting = null;
    final StreamSubscription<GenerationEvent>? running = _running;
    if (running == null) {
      return;
    }
    // Cancelling the subscription is what reaches the host: the operation
    // takes the generation back on the listener going away.
    await running.cancel();
    _running = null;
    // And then say so to the pass itself, which is otherwise awaiting a
    // reply that a cancelled stream will never deliver.
    final Completer<bool>? reply = _reply;
    if (reply != null && !reply.isCompleted) {
      reply.complete(false);
    }
    _finishIdle();
  }

  /// Completes when nothing is running and nothing is waiting.
  ///
  /// For tests and for shutdown, so neither has to poll a private field.
  Future<void> get settled {
    if (_running == null && _waiting == null) {
      return Future<void>.value();
    }
    return (_idle ??= Completer<void>()).future;
  }

  /// Stops accepting turns and gives the slot back.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await yieldSlot();
  }

  Future<void> _drain() async {
    _draining = true;
    while (!_disposed && _waiting != null) {
      final String said = _waiting!;
      _waiting = null;
      _lastRead = said;
      await _extract(said);
    }
    _draining = false;
    _finishIdle();
  }

  Future<void> _extract(String said) async {
    // Read now rather than when the reply lands: the profile the model is
    // shown has to be the one whose ids it is asked to supersede.
    final AgentProfile profile = _profile();
    final AgentMemoryExtractionPrompt prompt = composeMemoryExtraction(
      said: said,
      known: profile,
    );
    final StringBuffer reply = StringBuffer();
    final Completer<bool> finished = Completer<bool>();
    _reply = finished;
    late final StreamSubscription<GenerationEvent> subscription;
    subscription = _runtime
        .generate(
          GenerationRequest(
            conversationId: session,
            prompt: prompt.prompt,
            instruction: prompt.systemInstruction,
          ),
        )
        .listen(
          (GenerationEvent event) {
            switch (event) {
              case GenerationDelta(:final String delta):
                reply.write(delta);
              case GenerationCompleted():
                if (!finished.isCompleted) {
                  finished.complete(true);
                }
              case GenerationCancelled():
              case GenerationFailed():
                if (!finished.isCompleted) {
                  finished.complete(false);
                }
              case GenerationStarted():
                break;
            }
          },
          // A refusal — the slot was busy after all, the model is gone —
          // is a fact not kept, and the app is exactly where it was.
          onError: (Object _, StackTrace _) {
            if (!finished.isCompleted) {
              finished.complete(false);
            }
          },
          onDone: () {
            if (!finished.isCompleted) {
              finished.complete(false);
            }
          },
        );
    _running = subscription;

    final bool completed = await finished.future;
    if (identical(_reply, finished)) {
      _reply = null;
    }
    // Only when this subscription is still the live one. `yieldSlot` may
    // have replaced it while the await was outstanding, and clearing the
    // field then would drop a newer run's handle on the floor.
    if (identical(_running, subscription)) {
      _running = null;
      await subscription.cancel();
    }
    // The session goes whether or not the pass worked: a cancelled
    // extraction still left a conversation on the runtime.
    await _releaseQuietly();
    if (!completed || _disposed) {
      return;
    }

    final AgentMemoryExtraction found = readMemoryExtraction(
      reply.toString(),
      maxCharacters: maxAgentMemoryCharacters,
    );
    if (!found.hasFact) {
      return;
    }
    // Against the profile as it is *now*, not the one composed against.
    // The user may have edited it on the settings sheet while the model was
    // reading, and writing the stale list back would undo them.
    final AgentProfile current = _profile();
    final AgentMemoryWriteResult write = writeAgentMemory(
      profile: current,
      content: found.fact,
      replaces: found.replaces,
      // Written unattended, out of a transcript of whatever the microphone
      // heard, so it is screened at the write path in a way a memory the
      // user types is not.
      source: AgentMemorySource.agent,
      now: _clock(),
    );
    if (write.status != AgentMemoryWriteStatus.saved) {
      return;
    }
    await _write(current.copyWith(memories: write.memories));
    _onKept?.call(found.fact);
  }

  Future<void> _releaseQuietly() async {
    try {
      await _runtime.releaseSession(session);
    } on Object {
      // A session that will not release is a KV cache held until the
      // process ends. Worth nothing to the user and not worth a crash.
    }
  }

  void _finishIdle() {
    if (!_draining && _running == null && _waiting == null) {
      final Completer<void>? idle = _idle;
      _idle = null;
      if (idle != null && !idle.isCompleted) {
        idle.complete();
      }
    }
  }
}
