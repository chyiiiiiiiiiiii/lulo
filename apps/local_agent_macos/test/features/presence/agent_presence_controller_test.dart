import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/presence/agent_presence_controller.dart';
import 'package:local_agent_macos/features/presence/agent_presence_state.dart';

void main() {
  group('AgentPresenceController', () {
    test('notifies semantic listeners only when the target state changes', () {
      final AgentPresenceController controller = AgentPresenceController();
      var semanticNotifications = 0;
      var visualNotifications = 0;
      controller.semanticStateListenable.addListener(() {
        semanticNotifications += 1;
      });
      controller.visualInputListenable.addListener(() {
        visualNotifications += 1;
      });

      controller.dispatch(AgentPresenceEvent.idleRequested, Duration.zero);
      controller.dispatch(
        AgentPresenceEvent.listeningStarted,
        const Duration(milliseconds: 1),
      );
      controller.dispatch(
        AgentPresenceEvent.listeningStarted,
        const Duration(milliseconds: 2),
      );

      expect(
        controller.semanticStateListenable.value,
        AgentPresenceState.listening,
      );
      expect(semanticNotifications, 1);
      expect(visualNotifications, 1);
    });

    test('an accepted amplitude sample updates only the visual listenable', () {
      final AgentPresenceController controller = AgentPresenceController();
      var semanticNotifications = 0;
      var visualNotifications = 0;
      controller.semanticStateListenable.addListener(() {
        semanticNotifications += 1;
      });
      controller.visualInputListenable.addListener(() {
        visualNotifications += 1;
      });

      controller.acceptAudioRms(0.42, Duration.zero);

      expect(semanticNotifications, 0);
      expect(visualNotifications, 1);
      expect(controller.visualInputListenable.value.amplitude, 0);
    });

    test('rejects stale, backwards, and non-finite samples', () {
      final AgentPresenceController controller = AgentPresenceController();
      var visualNotifications = 0;
      controller.visualInputListenable.addListener(() {
        visualNotifications += 1;
      });

      controller.acceptAudioRms(0, Duration.zero);
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 10));
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 9));
      controller.acceptAudioRms(double.nan, const Duration(milliseconds: 20));
      controller.acceptAudioRms(
        double.infinity,
        const Duration(milliseconds: 20),
      );

      expect(visualNotifications, 1);
      expect(controller.visualInputListenable.value.amplitude, 0);
    });

    test('clamps finite RMS samples outside the normalized range', () {
      final AgentPresenceController controller = AgentPresenceController();
      var visualNotifications = 0;
      controller.visualInputListenable.addListener(() {
        visualNotifications += 1;
      });

      controller.acceptAudioRms(-1, Duration.zero);
      controller.acceptAudioRms(2, const Duration(milliseconds: 55));

      expect(visualNotifications, 2);
      expect(
        controller.visualInputListenable.value.amplitude,
        closeTo(1 - math.exp(-1), 1e-12),
      );
    });

    test('uses a 55 millisecond exponential attack envelope', () {
      final AgentPresenceController controller = AgentPresenceController();

      controller.acceptAudioRms(0, Duration.zero);
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 55));

      expect(
        controller.visualInputListenable.value.amplitude,
        closeTo(1 - math.exp(-1), 1e-12),
      );
    });

    test('uses a 180 millisecond release constant within the delta cap', () {
      final AgentPresenceController controller = AgentPresenceController();

      controller.acceptAudioRms(0, Duration.zero);
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 55));
      controller.acceptAudioRms(0, const Duration(milliseconds: 235));

      expect(
        controller.visualInputListenable.value.amplitude,
        closeTo((1 - math.exp(-1)) * math.exp(-100 / 180), 1e-12),
      );
    });

    test('caps an envelope delta at 100 milliseconds', () {
      final AgentPresenceController controller = AgentPresenceController();

      controller.acceptAudioRms(0, Duration.zero);
      controller.acceptAudioRms(0.42, const Duration(seconds: 1));

      expect(
        controller.visualInputListenable.value.amplitude,
        closeTo(1 - math.exp(-100 / 55), 1e-12),
      );
    });

    test('snaps a released amplitude below the silence threshold to zero', () {
      final AgentPresenceController controller = AgentPresenceController();

      controller.acceptAudioRms(0, Duration.zero);
      controller.acceptAudioRms(0.42, const Duration(milliseconds: 55));
      controller.acceptAudioRms(0, const Duration(milliseconds: 155));
      controller.acceptAudioRms(0, const Duration(milliseconds: 255));
      controller.acceptAudioRms(0, const Duration(milliseconds: 355));
      controller.acceptAudioRms(0, const Duration(milliseconds: 455));
      controller.acceptAudioRms(0, const Duration(milliseconds: 555));
      controller.acceptAudioRms(0, const Duration(milliseconds: 655));
      controller.acceptAudioRms(0, const Duration(milliseconds: 755));
      controller.acceptAudioRms(0, const Duration(milliseconds: 855));

      expect(controller.visualInputListenable.value.amplitude, 0);
    });

    test('does not publish updates after disposal', () {
      final AgentPresenceController controller = AgentPresenceController();
      var semanticNotifications = 0;
      var visualNotifications = 0;
      controller.semanticStateListenable.addListener(() {
        semanticNotifications += 1;
      });
      controller.visualInputListenable.addListener(() {
        visualNotifications += 1;
      });

      controller.dispose();
      controller.dispatch(AgentPresenceEvent.listeningStarted, Duration.zero);
      controller.acceptAudioRms(0.42, Duration.zero);

      expect(semanticNotifications, 0);
      expect(visualNotifications, 0);
    });
  });
}
