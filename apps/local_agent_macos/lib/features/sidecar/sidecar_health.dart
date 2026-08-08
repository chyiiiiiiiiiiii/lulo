import 'dart:async';
import 'dart:io';

/// One of the two local processes the voice path talks to.
///
/// Neither lives in this repository. Both are started by hand and both fail
/// silently: without the voice, `speakThroughSidecar` returns false and the
/// sentence is skipped; without the ears, the batch transcript never arrives
/// and the streamed one stands. The user sees an agent that heard, thought,
/// wrote, and then did not speak, with nothing on screen saying why.
///
/// The app cannot start them. The sandbox forbids spawning a subprocess, so
/// what it can honestly offer is to say which one is down — not a button
/// that would do nothing.
enum Sidecar {
  /// Speech out. Without it the agent is silent.
  voice(46557),

  /// The batch recogniser the hold-to-talk key uses. Without it the streamed
  /// transcript stands, which is measurably worse but not nothing.
  ears(46558);

  const Sidecar(this.port);

  /// The loopback port it listens on.
  ///
  /// Written here as well as in `VoiceHostAdapter`, which does the actual
  /// talking. Two copies of a number is worth less than a health check that
  /// has to cross the channel to ask a question about a socket.
  final int port;
}

/// Opens a connection to [port] on loopback and closes it again.
///
/// Named rather than private because it is the only way of asking that ever
/// runs outside a test, and a probe with an injected `connect` proves
/// nothing about it. There used to be a `SocketRefused` here as well, thrown
/// by four test fakes and by nothing else — so what the probe's catch was
/// proven against was a type production could not raise. `dart:io` raises
/// `SocketException`, the fakes raise it too now, and this is where it comes
/// from.
Future<void> openLoopbackSocket(int port, Duration timeout) async {
  final Socket socket = await Socket.connect(
    InternetAddress.loopbackIPv4,
    port,
    timeout: timeout,
  );
  // Nothing is sent. Opening it answered the question.
  socket.destroy();
}

/// Which sidecars answered.
final class SidecarHealth {
  /// Creates a result over [running].
  SidecarHealth(Set<Sidecar> running)
    : _running = Set<Sidecar>.unmodifiable(running);

  final Set<Sidecar> _running;

  /// Whether [sidecar] answered.
  bool isRunning(Sidecar sidecar) => _running.contains(sidecar);

  /// Whether both did.
  bool get allRunning => _running.length == Sidecar.values.length;

  /// The ones that did not, in declaration order.
  ///
  /// Ordered so a user with neither running is told about both at once,
  /// rather than discovering the second after fixing the first.
  List<Sidecar> get stopped => <Sidecar>[
    for (final Sidecar sidecar in Sidecar.values)
      if (!_running.contains(sidecar)) sidecar,
  ];
}

/// Asks each sidecar whether it is there.
final class SidecarHealthProbe {
  /// Creates a probe, optionally over an injected [connect].
  const SidecarHealthProbe({
    Future<void> Function(int port, Duration timeout)? connect,
  }) : connect = connect ?? openLoopbackSocket;

  /// How it asks. [openLoopbackSocket] unless a test said otherwise.
  ///
  /// Readable so a test can say that a probe nobody handed anything to is
  /// the one that opens a real socket. Left private, a default swapped for
  /// something else would keep every test passing.
  final Future<void> Function(int port, Duration timeout) connect;

  /// How long a port gets to answer.
  ///
  /// This runs when the settings sheet opens. A refused connection comes
  /// back at once; a port that is firewalled rather than refused hangs until
  /// something gives up, and the sheet must not be what gives up.
  static const Duration timeout = Duration(milliseconds: 400);

  /// Whether each sidecar is listening.
  ///
  /// A connection, not a request. Neither process is in this repository or
  /// under its control, so assuming a `/health` route would report a running
  /// sidecar as stopped the day that route is renamed. A process that
  /// accepts a connection is a process that is there.
  ///
  /// Which is all it proves. A sidecar that has bound its port and is still
  /// loading its model accepts a connection and cannot yet answer, so this
  /// says *answering*, not *well*, and the section that shows it can be
  /// asked again rather than deciding once.
  Future<SidecarHealth> check() async {
    final Set<Sidecar> running = <Sidecar>{};
    // Both at once, so the sheet waits one timeout rather than two, and both
    // are asked whatever the other answers — a user with neither running
    // should be told once rather than discover the second after fixing the
    // first.
    await Future.wait<void>(<Future<void>>[
      for (final Sidecar sidecar in Sidecar.values) _ask(sidecar, running),
    ]);
    return SidecarHealth(running);
  }

  /// Records [sidecar] in [running] if it answers, and says nothing if not.
  ///
  /// Every failure is the same answer here: refused, timed out, or the
  /// platform raising something this app has never seen all mean one thing
  /// to the user, which is that it is not there.
  Future<void> _ask(Sidecar sidecar, Set<Sidecar> running) async {
    try {
      await connect(sidecar.port, timeout);
      running.add(sidecar);
    } on Object {
      return;
    }
  }
}
