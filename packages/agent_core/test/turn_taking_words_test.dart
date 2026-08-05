import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  test('a profile that says nothing gets the built-in policy', () {
    final AgentProfile profile = AgentProfile.builtIn();

    expect(profile.turnTaking.acknowledgements, isEmpty);
    expect(profile.turnTaking.corrections, isEmpty);
    expect(profile.turnTaking.unfinished, isEmpty);
    expect(profile.floorControl.classify('嗯嗯'), FloorClaim.backchannel);
  });

  test('the profile builds the policy that decides interruptions', () {
    // The whole point of putting these in the profile: the file is watched,
    // so a word added while the app is running takes effect on the next
    // thing said rather than at the next build.
    final AgentProfile profile = AgentProfile(
      turnTaking: const TurnTakingWords(
        acknowledgements: <String>['蛤'],
        corrections: <String>['先停'],
      ),
    );

    expect(profile.floorControl.classify('蛤蛤'), FloorClaim.backchannel);
    expect(profile.floorControl.classify('先停一下'), FloorClaim.correction);
  });

  test('the policy is built once, not per utterance', () {
    // classify runs on every partial, a few times a second for as long as
    // the microphone is open.
    final AgentProfile profile = AgentProfile(
      turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
    );

    expect(identical(profile.floorControl, profile.floorControl), isTrue);
  });

  test('two profiles saying the same thing are the same profile', () {
    // The store compares before replacing, so an unchanged file must not
    // look like a change and bump the revision.
    expect(
      AgentProfile(
        turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
      ),
      AgentProfile(
        turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
      ),
    );
    expect(
      AgentProfile(
        turnTaking: const TurnTakingWords(acknowledgements: <String>['蛤']),
      ),
      isNot(AgentProfile.builtIn()),
    );
  });

  test('the endpointer words are carried but not interpreted here', () {
    // TurnCompletion lives in Swift, because the endpointer runs on a 50ms
    // tick in the audio path. This side only has to deliver them.
    final AgentProfile profile = AgentProfile(
      turnTaking: const TurnTakingWords(unfinished: <String>['我的意思是說']),
    );

    expect(profile.turnTaking.unfinished, <String>['我的意思是說']);
  });
}
