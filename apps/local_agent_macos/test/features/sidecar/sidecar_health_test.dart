import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/sidecar/sidecar_health.dart';

void main() {
  /// A probe over a machine where [listening] ports answer and nothing else
  /// does.
  ///
  /// Refusal is a `SocketException` because that is what `dart:io` raises
  /// when nothing is listening. A fake that threw a type only fakes can
  /// throw would prove the catch handles fakes.
  SidecarHealthProbe probe(
    Set<int> listening, {
    Duration? hangFor,
    List<int>? tried,
    List<Duration>? given,
  }) => SidecarHealthProbe(
    connect: (int port, Duration timeout) async {
      tried?.add(port);
      given?.add(timeout);
      if (hangFor != null) {
        await Future<void>.delayed(hangFor);
        throw TimeoutException('took too long');
      }
      if (!listening.contains(port)) {
        throw const SocketException('connection refused');
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

  test(
    'the bound that keeps the sheet moving is the one handed down',
    () async {
      // The test above gives up after 5ms of its own accord, which says
      // nothing about whether `timeout` ever reaches the socket. A bound
      // declared and not passed on is a sheet that hangs for as long as the
      // network takes.
      final List<Duration> given = <Duration>[];

      await probe(<int>{}, given: given).check();

      expect(given, hasLength(Sidecar.values.length));
      expect(given, everyElement(SidecarHealthProbe.timeout));
    },
  );

  test('both are asked about, not just the first to fail', () async {
    // A user with neither running needs to be told both, once, rather than
    // discovering the second after fixing the first.
    final List<int> tried = <int>[];
    await probe(<int>{}, tried: tried).check();

    expect(tried, containsAll(<int>[Sidecar.voice.port, Sidecar.ears.port]));
  });

  test('a probe nobody handed a connect to opens a real socket', () {
    // Every test above injects `connect`, which means the one function that
    // ever runs outside a test had no coverage at all. The three tests here
    // are about that function; this one is about it being the one in use.
    expect(const SidecarHealthProbe().connect, same(openLoopbackSocket));
  });

  test('a port something is listening on answers', () async {
    // A real socket rather than a fake, and the sidecar ports are not used:
    // the real 46557 may well be up on the machine running this, and a test
    // that passes only when it is would be reporting the developer's
    // machine.
    final ServerSocket listening = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(listening.close);

    await expectLater(
      openLoopbackSocket(listening.port, SidecarHealthProbe.timeout),
      completes,
    );
  });

  test(
    'a port nothing is listening on throws, and the probe catches it',
    () async {
      // Bound and then released, so the number is a real free port rather
      // than a guess that something might have taken.
      final ServerSocket wasListening = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final int free = wasListening.port;
      await wasListening.close();

      // `SocketException` is what production raises and therefore what the
      // probe has to survive. Asserting the type here is the whole point: the
      // fakes used to throw a type only fakes could throw, so the catch was
      // only ever proven against fiction.
      await expectLater(
        openLoopbackSocket(free, SidecarHealthProbe.timeout),
        throwsA(isA<SocketException>()),
      );

      final SidecarHealth health = await SidecarHealthProbe(
        connect: (int port, Duration timeout) =>
            openLoopbackSocket(free, timeout),
      ).check();

      expect(health.stopped, <Sidecar>[Sidecar.voice, Sidecar.ears]);
    },
  );

  test('each sidecar says what stops working without it', () {
    // A port number is not a thing a user can act on.
    expect(Sidecar.voice.port, 46557);
    expect(Sidecar.ears.port, 46558);
    expect(Sidecar.values.map((Sidecar s) => s.port).toSet().length, 2);
  });
}
