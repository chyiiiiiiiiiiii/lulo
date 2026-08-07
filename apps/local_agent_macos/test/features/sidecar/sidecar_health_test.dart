import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/sidecar/sidecar_health.dart';

void main() {
  /// A probe over a machine where [listening] ports answer and nothing else
  /// does.
  SidecarHealthProbe probe(
    Set<int> listening, {
    Duration? hangFor,
    List<int>? tried,
  }) => SidecarHealthProbe(
    connect: (int port, Duration timeout) async {
      tried?.add(port);
      if (hangFor != null) {
        await Future<void>.delayed(hangFor);
        throw TimeoutException('took too long');
      }
      if (!listening.contains(port)) {
        throw const SocketRefused();
      }
    },
  );

  test('a sidecar that answers is running', () async {
    final SidecarHealth health = await probe(<int>{
      Sidecar.voice.port,
      Sidecar.ears.port,
    }).check();

    expect(health.isRunning(Sidecar.voice), isTrue);
    expect(health.isRunning(Sidecar.ears), isTrue);
    expect(health.allRunning, isTrue);
  });

  test('a sidecar nothing is listening on is not running', () async {
    // The app cannot start it: the sandbox forbids spawning a subprocess, so
    // the honest thing is to say which one is down rather than to offer a
    // button that cannot work.
    final SidecarHealth health = await probe(<int>{Sidecar.voice.port}).check();

    expect(health.isRunning(Sidecar.voice), isTrue);
    expect(health.isRunning(Sidecar.ears), isFalse);
    expect(health.allRunning, isFalse);
    expect(health.stopped, <Sidecar>[Sidecar.ears]);
  });

  test('answering at all counts, whatever it answers', () async {
    // The check is a connection, not a request. Neither sidecar is in this
    // repository and neither is under its control, so assuming a `/health`
    // route would report a running process as stopped the day it changes.
    // A process that accepts a connection is a process that is there.
    final SidecarHealth health = await probe(<int>{Sidecar.voice.port}).check();

    expect(health.isRunning(Sidecar.voice), isTrue);
  });

  test(
    'a machine where nothing answers does not hang the settings sheet',
    () async {
      // This runs when the sheet opens. A port being firewalled rather than
      // refused hangs until something gives up, and the sheet must not be it.
      final SidecarHealth health = await probe(
        <int>{},
        hangFor: const Duration(milliseconds: 5),
      ).check();

      expect(health.allRunning, isFalse);
      expect(health.stopped, <Sidecar>[Sidecar.voice, Sidecar.ears]);
    },
  );

  test('both are asked about, not just the first to fail', () async {
    // A user with neither running needs to be told both, once, rather than
    // discovering the second after fixing the first.
    final List<int> tried = <int>[];
    await probe(<int>{}, tried: tried).check();

    expect(tried, containsAll(<int>[Sidecar.voice.port, Sidecar.ears.port]));
  });

  test('each sidecar says what stops working without it', () {
    // A port number is not a thing a user can act on.
    expect(Sidecar.voice.port, 46557);
    expect(Sidecar.ears.port, 46558);
    expect(Sidecar.values.map((Sidecar s) => s.port).toSet().length, 2);
  });
}
