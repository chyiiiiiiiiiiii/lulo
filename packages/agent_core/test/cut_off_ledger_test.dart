import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  _coverageGroup();
  _lengthGroup();
  test('one cut-off suggests nothing', () {
    // A single cut-off is an accident. Only recurrence says the ending is
    // the reason rather than the coincidence.
    final CutOffLedger ledger = CutOffLedger();
    ledger.noteCutOff('我想說的是');

    expect(ledger.suggestions, isEmpty);
  });

  test('an ending that keeps getting cut off is suggested', () {
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('那個我想說的是');
    }

    expect(ledger.suggestions, contains('我想說的是'));
  });

  test('the longest ending that recurs is the one suggested', () {
    // Every shorter tail of a repeated phrase also repeats, so all of them
    // cross the threshold together. Suggesting the shortest would hand the
    // user 「的是」, which matches half the language.
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('欸我想說的是');
    }

    expect(ledger.suggestions, <String>['我想說的是']);
  });

  test('a shorter ending shared by different sentences is found', () {
    // Three different lead-ins, one common tail: the tail is the thing.
    final CutOffLedger ledger = CutOffLedger();
    ledger.noteCutOff('我覺得說的是');
    ledger.noteCutOff('他跟我說的是');
    ledger.noteCutOff('重點說的是');

    expect(ledger.suggestions, <String>['說的是']);
  });

  test('an English ending is counted in words, not letters', () {
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('so the thing I wanted to say is because');
    }

    expect(ledger.suggestions.single, endsWith('because'));
    expect(ledger.suggestions.single.split(' ').length, greaterThan(1));
  });

  test('punctuation the recogniser wrote is not part of the ending', () {
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('我想說的是，');
    }

    expect(ledger.suggestions.single, '我想說的是');
  });

  test('an utterance too short to have an ending is ignored', () {
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 5; i++) {
      ledger.noteCutOff('好');
      ledger.noteCutOff('');
      ledger.noteCutOff('   ');
    }

    expect(ledger.suggestions, isEmpty);
  });

  test('a suggestion already in the profile is not suggested again', () {
    // The user has done what was asked; repeating it is nagging, and the
    // cut-offs that produced it are already history.
    final CutOffLedger ledger = CutOffLedger(
      alreadyListed: () => <String>['我想說的是'],
    );
    for (int i = 0; i < 4; i++) {
      ledger.noteCutOff('那個我想說的是');
    }

    expect(ledger.suggestions, isEmpty);
  });

  test('how many times an ending was cut off is readable', () {
    // The suggestion has to carry its own evidence, or it is just the app
    // asserting something about the user's speech.
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('我想說的是');
    }

    expect(ledger.timesCutOff('我想說的是'), 3);
    expect(ledger.timesCutOff('never said'), 0);
  });

  test('the threshold is the caller\'s to choose', () {
    final CutOffLedger eager = CutOffLedger(repeatsBeforeSuggesting: 2);
    eager
      ..noteCutOff('我想說的是')
      ..noteCutOff('我想說的是');

    expect(eager.suggestions, isNotEmpty);
  });
}

void _lengthGroup() {
  test('how long an ending may be is the caller\'s to choose', () {
    final CutOffLedger short = CutOffLedger(longestEnding: 2);
    for (int i = 0; i < 3; i++) {
      short.noteCutOff('那個我想說的是');
    }

    expect(short.suggestions, <String>['的是']);
  });
}

void _coverageGroup() {
  test('a wider ending is still suggested when a narrower one is listed', () {
    // 「我想說的是」 in the profile catches only sentences ending on exactly
    // that. It says nothing about 「他說的是」, so the shorter, more general
    // ending is still worth raising.
    final CutOffLedger ledger = CutOffLedger(
      alreadyListed: () => <String>['我想說的是'],
    );
    ledger.noteCutOff('我覺得說的是');
    ledger.noteCutOff('他跟我說的是');
    ledger.noteCutOff('重點說的是');

    expect(ledger.suggestions, contains('說的是'));
  });

  test('a listed ending covers every longer sentence ending on it', () {
    final CutOffLedger ledger = CutOffLedger(
      alreadyListed: () => <String>['說的是'],
    );
    for (int i = 0; i < 4; i++) {
      ledger.noteCutOff('那個我想說的是');
    }

    expect(ledger.suggestions, isEmpty);
  });

  test('a shorter ending seen more often stands on its own', () {
    final CutOffLedger ledger = CutOffLedger();
    for (int i = 0; i < 3; i++) {
      ledger.noteCutOff('欸我想說的是');
    }
    for (int i = 0; i < 2; i++) {
      ledger.noteCutOff('他跟我說的是');
    }

    expect(ledger.suggestions, containsAll(<String>['我想說的是', '說的是']));
  });
}
