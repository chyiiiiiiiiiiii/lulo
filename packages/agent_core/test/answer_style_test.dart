import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

/// How adventurous the model is allowed to be, in the user's words.
///
/// The numbers behind it were fixed at composition time, which meant the one
/// dial that decides whether an answer is careful or inventive could not be
/// touched without rebuilding the app.
void main() {
  test('the balanced style is what the app already shipped', () {
    // Changing the default would change every existing user's answers, which
    // is not what exposing a setting is for.
    expect(AnswerStyle.balanced.temperature, 0.7);
    expect(AnswerStyle.balanced.topP, 0.95);
  });

  test('the three styles are ordered by how far they roam', () {
    final List<AnswerStyle> styles = <AnswerStyle>[
      AnswerStyle.steady,
      AnswerStyle.balanced,
      AnswerStyle.inventive,
    ];
    for (int i = 1; i < styles.length; i += 1) {
      expect(
        styles[i].temperature,
        greaterThan(styles[i - 1].temperature),
        reason: 'the styles must differ, or the setting is decoration',
      );
      expect(styles[i].topP, greaterThanOrEqualTo(styles[i - 1].topP));
    }
  });

  test('every style is a temperature a sampler will accept', () {
    for (final AnswerStyle style in AnswerStyle.values) {
      expect(style.temperature, greaterThan(0));
      expect(style.temperature, lessThanOrEqualTo(2));
      expect(style.topP, greaterThan(0));
      expect(style.topP, lessThanOrEqualTo(1));
    }
  });
}
