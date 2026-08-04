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

  // MARK: - The words decide how long the silence has to be

  func testAHalfFinishedThoughtBuysItselfMoreSilence() {
    // The corpus has mid-sentence pauses of 1.02s, past the 0.8s that
    // submits a turn. Nothing in the audio separates them from the end of
    // a turn — but the words before the pause do, and a sentence that
    // stops on a connective has not stopped.
    for opening in ["等一下", "我想問的是", "然後", "但是", "因為", "如果", "而且", "就是", "我覺得", "所以"] {
      XCTAssertEqual(
        TurnCompletion.of(opening),
        .continuing,
        "\"\(opening)\" is the middle of a sentence, not the end of one."
      )
    }
  }

  func testAFinishedQuestionDoesNotWaitTheFullSilenceOut() {
    for question in ["這樣可以嗎", "你覺得呢", "那到底是什麼？", "所以要怎麼做啊，你說嘛"] {
      XCTAssertEqual(
        TurnCompletion.of(question),
        .settled,
        "\"\(question)\" has visibly finished."
      )
    }
  }

  func testATooShortUtteranceIsNeverCalledFinished() {
    // A stray "嗎" is one misheard syllable, not a question, and shortening
    // the endpoint on it would cut the user off for a mishearing.
    for scrap in ["嗎", "呢", "我呢", "好？"] {
      XCTAssertEqual(
        TurnCompletion.of(scrap),
        .unknown,
        "\"\(scrap)\" is too little to shorten anything on."
      )
    }
  }

  func testOrdinarySpeechDecidesNothing() {
    for plain in ["", "介紹一下台北的天氣", "tell me about flutter"] {
      XCTAssertEqual(TurnCompletion.of(plain), .unknown)
    }
  }

  func testAHalfFinishedThoughtIsGivenLongerToFinishIt() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "我想問的是", at: 10)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 1.0, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      ),
      "A connective must outlast the ordinary 0.8s."
    )
    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 1.5, lastVoiceAt: 10, endpointSilence: 0.8, now: 12
      )
    )
  }

  func testAFinishedQuestionIsAnsweredSooner() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "這樣可以嗎", at: 10)

    XCTAssertTrue(
      turn.shouldFinalize(
        silence: 0.6, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      ),
      "A finished question should not sit through the full silence."
    )
  }

  func testSilenceStillHasToBeSilenceForAFinishedQuestion() {
    var turn = SpeechTurn()
    turn.heardVolatile(text: "這樣可以嗎", at: 10)

    XCTAssertFalse(
      turn.shouldFinalize(
        silence: 0.3, lastVoiceAt: 10, endpointSilence: 0.8, now: 11
      ),
      "Shortening the wait is not removing it."
    )
  }

  // MARK: - Read back over the corpus the endpointer was tuned on

  /// Every sentence in `benchmarks/voice_eval/corpus/zh-TW-v1.json`, cut at
  /// each clause boundary the corpus records a pause at, with the verdict
  /// the endpointer reaches there.
  ///
  /// This is the falsifiable half of the lexicon: the table below was not
  /// chosen, it was read off the classifier and then checked case by case
  /// against what a person would do. Two of the twelve — `short-answer-not-yet`
  /// and `endpoint-thinking-pause` — are the pauses of 1.02s and 1.10s that
  /// `docs/decisions/voice-turn-latency.md` measured running *past* the 0.8s
  /// that submits a turn, and both now buy themselves the grace to finish.
  func testTheCorpusEndsWhereTheEndpointerThinksItDoes() {
    let cases: [(String, TurnCompletion)] = [
      // short-answer-ready
      ("好", .unknown),
      ("好，可以開始了。", .settled),
      // short-answer-not-yet — the 1.02s mid-utterance pause
      ("等一下", .continuing),
      ("等一下，還沒。", .settled),
      // code-switch-product-names
      ("我剛剛把 Flutter 跟 MLX 的版本都更新了。", .settled),
      // code-switch-agent-tools
      ("先用 Codex 檢查", .unknown),
      ("先用 Codex 檢查，再跑 Dart test。", .settled),
      // numbers-date-time
      ("八月二日下午三點半提醒我。", .settled),
      // numbers-money-version
      ("預算是一萬二", .unknown),
      ("預算是一萬二，版本先用三點五。", .settled),
      // disfluency-self-correction
      ("我想看明天", .unknown),
      ("我想看明天，欸不是", .unknown),
      ("我想看明天，欸不是，後天的天氣。", .settled),
      // punctuation-natural-clauses
      ("先回答核心", .unknown),
      ("先回答核心，細節我等等再補。", .settled),
      // long-form-project-request
      ("幫我先確認目前專案在哪個分支", .unknown),
      ("幫我先確認目前專案在哪個分支，測試有沒有通過", .unknown),
      ("幫我先確認目前專案在哪個分支，測試有沒有通過，再告訴我最值得先修的地方。", .settled),
      // long-form-conversational
      ("我不是要你全部重做", .unknown),
      ("我不是要你全部重做，我只是想知道現在這個版本", .unknown),
      ("我不是要你全部重做，我只是想知道現在這個版本，哪一段聽起來最不像臺灣人平常講話。", .settled),
      // barge-in-stop-answer
      ("等一下，先不要念完。", .settled),
      // endpoint-thinking-pause — the 1.10s mid-utterance pause
      ("我想問的是", .continuing),
      ("我想問的是……如果完全離線的話", .continuing),
      ("我想問的是……如果完全離線的話，記憶要怎麼同步？", .settled),
    ]
    for (heard, expected) in cases {
      XCTAssertEqual(
        TurnCompletion.of(heard),
        expected,
        "\"\(heard)\" was read as \(TurnCompletion.of(heard)), not \(expected)."
      )
    }
  }

  func testNoCorpusSentenceIsHeldOpenAfterItEnds() {
    // The expensive mistake in the other direction: treating a finished
    // sentence as unfinished adds 0.6s to a turn that was already over.
    for finished in [
      "好，可以開始了。",
      "等一下，還沒。",
      "先用 Codex 檢查，再跑 Dart test。",
      "八月二日下午三點半提醒我。",
      "預算是一萬二，版本先用三點五。",
      "我想看明天，欸不是，後天的天氣。",
      "先回答核心，細節我等等再補。",
      "幫我先確認目前專案在哪個分支，測試有沒有通過，再告訴我最值得先修的地方。",
      "我不是要你全部重做，我只是想知道現在這個版本，哪一段聽起來最不像臺灣人平常講話。",
      "等一下，先不要念完。",
      "我想問的是……如果完全離線的話，記憶要怎麼同步？",
    ] {
      XCTAssertNotEqual(
        TurnCompletion.of(finished),
        .continuing,
        "\"\(finished)\" has finished and must not be waited out."
      )
    }
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
