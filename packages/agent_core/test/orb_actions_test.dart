import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('offers nothing at all without a model', () {
    expect(
      orbActionsFor(hasModel: false, canTalk: true, canLook: true, busy: true),
      isEmpty,
    );
  });

  test('offers talking and looking while the agent is resting', () {
    expect(
      orbActionsFor(hasModel: true, canTalk: true, canLook: true, busy: false),
      <OrbActionKind>[OrbActionKind.talk, OrbActionKind.look],
    );
  });

  test('offers stopping only while there is something to stop', () {
    expect(
      orbActionsFor(hasModel: true, canTalk: true, canLook: true, busy: true),
      <OrbActionKind>[
        OrbActionKind.talk,
        OrbActionKind.look,
        OrbActionKind.stop,
      ],
    );
  });

  test('what is offered never changes place', () {
    // Stop arrives at the end rather than pushing to the front, so the button
    // under the pointer is the one that was there last time.
    final List<OrbActionKind> resting = orbActionsFor(
      hasModel: true,
      canTalk: true,
      canLook: true,
      busy: false,
    );
    final List<OrbActionKind> working = orbActionsFor(
      hasModel: true,
      canTalk: true,
      canLook: true,
      busy: true,
    );
    expect(working.take(resting.length), resting);
  });

  test('leaves out what the machine cannot do', () {
    expect(
      orbActionsFor(
        hasModel: true,
        canTalk: false,
        canLook: false,
        busy: false,
      ),
      isEmpty,
    );
  });
}
