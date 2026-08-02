import XCTest

@testable import Lulo

/// The bookkeeping behind the mute and the endpointer.
///
/// Its failures do not look like themselves — the symptom of getting any of
/// this wrong is "the transcriber is bad" or "it was slow that one time",
/// never "the counter is off". Every case below is a sentence someone would
/// say about the agent's behaviour.
final class SpeechTurnTests: XCTestCase {
  // MARK: - The mute belongs to the answer, not to the sentence

  func testOnlyTheFirstSentenceOfAnAnswerClosesTheMicrophone() {
    var turn = SpeechTurn()
    let first = turn.began(at: 0)
    XCTAssertTrue(first.shouldMute)
    XCTAssertTrue(first.shouldReportStart)

    let second = turn.began(at: 0)
    XCTAssertFalse(second.shouldMute)
    XCTAssertFalse(second.shouldReportStart)
  }

  func testTheMicrophoneWaitsForTheLastSentenceOfTheAnswer() {
    // Sentence one returning while two is still playing must not reopen
    // the microphone, or the agent hears itself finish.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    _ = turn.began(at: 0)

    XCTAssertNil(turn.ended(at: 0))
    XCTAssertNotNil(turn.ended(at: 0))
  }

  func testASupersededUnmuteDoesNotFire() {
    // The 300ms hangover is still running when the next sentence begins;
    // the older unmute must not reopen the microphone underneath it.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    let pending = turn.ended(at: 0)
    XCTAssertNotNil(pending)

    _ = turn.began(at: 0)

    XCTAssertFalse(turn.liftMute(generation: pending!))
  }

  func testTheAnswerReportsItselfOnceAcrossTheHangover() {
    // A second utterance beginning before the first's finish is reported
    // must not produce a second start.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    let pending = turn.ended(at: 0)!
    XCTAssertTrue(turn.liftMute(generation: pending))

    XCTAssertTrue(turn.began(at: 0).shouldReportStart)
  }

  // MARK: - The endpointer only trusts what it measured

  func testSilenceIsNotEnoughWithoutAnUtterance() {
    let turn = SpeechTurn()
    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 5, lastVoiceAt: 100, endpointSilence: 0.8, now: 100
      )
    )
  }

  func testAnUtteranceIsFinalizedOnceAndNotAgain() {
    var turn = SpeechTurn()
    turn.heardVolatile(at: 10)
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      )
    )
    turn.askedToFinalize(at: 11)
    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      )
    )
  }

  func testVoiceHeardBeforeTheAnswerCannotEndTheSentenceAfterIt() {
    // The VAD's clock froze during the mute, so its "last voice" is from
    // before the answer. Trusting it finalizes the user's new sentence at
    // its first word.
    var turn = SpeechTurn()
    turn.microphoneReopened(at: 100)
    turn.heardVolatile(at: 101)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 5, lastVoiceAt: 40, endpointSilence: 0.8, now: 106
      )
    )
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 101, endpointSilence: 0.8, now: 102
      )
    )
  }

  func testRecognitionLagIsForgivenByTheMargin() {
    // The first volatile can arrive after the room already went quiet.
    var turn = SpeechTurn()
    turn.heardVolatile(at: 10)
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 9.2, endpointSilence: 0.8, now: 11
      )
    )
  }

  func testAContinuationPrefixGetsTimeToFinishAfterALongNaturalPause() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "等一下", at: 10)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 1.22, lastVoiceAt: 10, endpointSilence: 0.8, now: 11.22
      )
    )
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.41, lastVoiceAt: 10, endpointSilence: 0.8, now: 11.41
      )
    )
  }

  func testAnOrdinaryCompleteSentenceKeepsTheFastEndpoint() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "好，可以開始了", at: 10)

    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 0.81, lastVoiceAt: 10, endpointSilence: 0.8, now: 10.81
      )
    )
  }

  func testAQuestionLeadInAlsoGetsTheMeasuredThinkingPause() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "我想問的是……", at: 10)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 0.95, lastVoiceAt: 10, endpointSilence: 0.8, now: 10.95
      )
    )
  }

  func testAnEmptyResultStillUnlatchesTheEndpointer() {
    // A finalize that produced nothing must not leave the fast path off
    // for the rest of the session.
    var turn = SpeechTurn()
    turn.heardVolatile(at: 10)
    turn.askedToFinalize(at: 11)
    turn.settled()
    turn.heardVolatile(at: 20)

    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 20, endpointSilence: 0.8, now: 21
      )
    )
  }

  // MARK: - Stopping leaves nothing latched

  func testASentenceFromAStoppedSessionCannotDisturbTheNextOne() {
    // The user turns the microphone off mid-answer and on again, and starts
    // talking. Up to two minutes later — /speak waits that long — the
    // abandoned sentence finally returns. It belongs to a session that no
    // longer exists and must not reopen anything, report anything, or
    // reset the clocks under the sentence being said right now.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    turn.listeningStopped()

    turn.heardVolatile(at: 100)

    XCTAssertNil(turn.ended(at: 0))
    XCTAssertTrue(turn.utteranceInProgress)
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 100, endpointSilence: 0.8, now: 101
      )
    )
  }

  func testAFinalizeThatIsNeverAnsweredIsAskedAgain() {
    // The analyzer accepts the finalize and emits nothing — no final, not
    // even an empty one. Nothing clears the latch, so without a second ask
    // the fast endpointer is off for the rest of the session and every
    // turn silently falls back to the slower Dart settle.
    var turn = SpeechTurn()
    turn.heardVolatile(at: 10)
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      )
    )
    turn.askedToFinalize(at: 11)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 2.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 12
      )
    )
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 5.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 15
      )
    )
  }

  func testAWedgedSentenceDoesNotKeepTheMicrophoneShutForever() {
    // The sidecar accepted the sentence and never answered — /speak waits
    // two minutes for that, and for all of them the agent is deaf while
    // the button still reads as listening.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)

    XCTAssertFalse(turn.muteOverdue(now: 10))
    XCTAssertTrue(turn.muteOverdue(now: 100))

    turn.abandonSpeech()
    XCTAssertEqual(turn.outstanding, 0)
    XCTAssertFalse(turn.muteOverdue(now: 200))
  }

  func testAnAnswerTakingItsTimeIsNotMistakenForAWedgedOne() {
    // A long answer is many sentences; each one starting or finishing is
    // progress, and progress is what the ceiling actually measures.
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    _ = turn.ended(at: 30)
    _ = turn.began(at: 30)
    _ = turn.ended(at: 60)
    _ = turn.began(at: 60)

    XCTAssertFalse(turn.muteOverdue(now: 90))
  }

  func testStoppingListeningOpensTheMicrophoneWhateverWasInFlight() {
    var turn = SpeechTurn()
    _ = turn.began(at: 0)
    _ = turn.began(at: 0)

    turn.listeningStopped()

    XCTAssertEqual(turn.outstanding, 0)
    XCTAssertFalse(turn.speakingReported)
    XCTAssertFalse(turn.utteranceInProgress)
  }
}
