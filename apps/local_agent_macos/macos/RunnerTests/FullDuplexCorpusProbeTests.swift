import AVFoundation
import Speech
import XCTest

@testable import Lulo

/// Runs the full-duplex recogniser over a corpus file instead of a microphone.
///
/// `docs/features/voice.md` scores three ways in beside each other, and the
/// full-duplex column reads "never measured" for English. That was not an
/// oversight about English: it is that the full-duplex recogniser had no way
/// to be measured at all. `benchmarks/voice_eval` scores files, and
/// `SpeechTranscriber` existed in exactly one place — `VoiceHostAdapter`,
/// wired to a live `AVAudioEngine` — so the only way to produce a transcript
/// from it was to speak into the machine. A number obtained that way cannot be
/// re-run, and a column that cannot be re-run is one nobody fills in.
///
/// `SpeechAnalyzer` does not require an engine. It takes any
/// `AsyncSequence<AnalyzerInput>`, so a corpus `.wav` read off disk feeds it
/// the same way the microphone tap does, and the result lands in the candidate
/// JSON `voice_eval` already knows how to score.
///
/// **This is the same pipeline, deliberately.** The transcriber's locale,
/// reporting options and attribute options are the ones `begin()` uses, and
/// the contextual bias is `VoiceHostAdapter.spokenVocabulary` — the
/// benchmark's README warns that a candidate produced without that bias is
/// not measuring the same thing. What it cannot reproduce is the engine: no
/// voice-processing unit, no half-duplex mute, no microphone array. So this
/// measures **the recogniser**, and a live session can still be worse than
/// what it reports. It cannot be better.
///
/// Skipped unless both paths are set, because the first run downloads a
/// system asset. The `TEST_RUNNER_` prefix is required and is not decoration:
/// `xcodebuild` does not hand the shell's environment to the test process, and
/// without it the run reports success having skipped the only test in it.
///
/// ```sh
/// TEST_RUNNER_VOICE_CORPUS=$PWD/benchmarks/voice_eval/corpus/en-spoken-v1.json \
/// TEST_RUNNER_VOICE_CANDIDATE_OUT=candidate-full-duplex-en.json \
///   xcodebuild test-without-building -workspace Runner.xcworkspace \
///     -scheme Runner -destination platform=macOS \
///     -only-testing:RunnerTests/FullDuplexCorpusProbeTests
/// ```
///
/// Only the *name* of the output is honoured; the file lands in the sandboxed
/// host's temporary directory and the run prints where. See the write below.
@available(macOS 26.0, *)
final class FullDuplexCorpusProbeTests: XCTestCase {
  /// One corpus entry, as much of it as this probe needs.
  private struct CorpusCase: Decodable {
    let id: String
    let audioPath: String
  }

  /// The corpus file's envelope.
  private struct Corpus: Decodable {
    let corpusId: String
    let locale: String
    let cases: [CorpusCase]
  }

  func testTheFullDuplexRecogniserOverACorpus() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard
      let corpusPath = environment["VOICE_CORPUS"],
      let outPath = environment["VOICE_CANDIDATE_OUT"]
    else {
      throw XCTSkip(
        "Set VOICE_CORPUS and VOICE_CANDIDATE_OUT to run the full-duplex probe."
      )
    }

    let corpusURL = URL(fileURLWithPath: corpusPath)
    let corpus = try JSONDecoder().decode(
      Corpus.self,
      from: Data(contentsOf: corpusURL)
    )
    let audioRoot = corpusURL.deletingLastPathComponent()
    guard let locale = await Self.supportedLocale(matching: corpus.locale) else {
      XCTFail(
        "\(corpus.locale) is not installed for SpeechTranscriber. The "
          + "full-duplex path refuses the same way at begin()."
      )
      return
    }

    // Whether the recogniser is handed the app's vocabulary. Off is not a
    // configuration anybody ships — it exists so the bias can be shown to
    // reach the recogniser at all. A candidate produced without the bias is
    // not measuring this app's pipeline, and a harness that silently drops it
    // would report exactly the same thing while measuring something else.
    let biased = environment["VOICE_NO_BIAS"] == nil

    var rows: [[String: Any]] = []
    for entry in corpus.cases {
      let audioURL = audioRoot.appendingPathComponent(entry.audioPath)
      let started = Date()
      let heard = try await Self.transcribe(audioURL, as: locale, biased: biased)
      let elapsed = Int(Date().timeIntervalSince(started) * 1000)
      print("PROBE \(entry.id): \(heard)")
      rows.append([
        "caseId": entry.id,
        "rawTranscript": heard,
        "refinedTranscript": NSNull(),
        "partialEvents": [],
        "finalAtMs": elapsed,
      ])
    }

    // `runId` carries no clock beyond the corpus it ran over: the file is
    // committed as evidence, and a timestamp would make every re-run a diff
    // even when the transcripts are identical.
    let candidate: [String: Any] = [
      "schemaVersion": 1,
      "runId": "full-duplex-\(corpus.corpusId)",
      "corpusId": corpus.corpusId,
      "kind": "transcript",
      "adapter": [
        "name": "apple-speech-transcriber",
        "version": "SpeechTranscriber locale=\(locale.identifier(.bcp47)) "
          + "bias=\(biased ? "app-vocabulary" : "none")",
      ],
      "cases": rows,
    ]
    // Written inside the container, under the name asked for rather than at
    // the path asked for. The test host is the real app and it is sandboxed:
    // it may read the corpus out of the repository and may not write a file
    // back beside it, which fails as NSCocoaErrorDomain 513 at the very end,
    // after every case has already been recognised. The caller copies it out
    // from the path printed below.
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent(URL(fileURLWithPath: outPath).lastPathComponent)
    try JSONSerialization
      .data(withJSONObject: candidate, options: [.prettyPrinted, .sortedKeys])
      .write(to: destination)
    print("PROBE wrote \(destination.path)")
  }

  /// The installed locale that serves [wanted], or nil if none does.
  ///
  /// Matched on the language rather than the exact tag for the reason
  /// `begin()` does it: the app pins one locale for a whole session from
  /// `Locale.preferredLanguages`, and `en-US` standing in for `en` is the
  /// ordinary case rather than a fallback worth failing over.
  private static func supportedLocale(matching wanted: String) async -> Locale? {
    let asked = Locale(identifier: wanted)
    let supported = await SpeechTranscriber.supportedLocales
    if let exact = supported.first(where: {
      $0.identifier(.bcp47) == asked.identifier(.bcp47)
    }) {
      return exact
    }
    return supported.first {
      $0.language.languageCode == asked.language.languageCode
    }
  }

  /// Everything the recogniser settled on for [audioURL].
  ///
  /// Only finals are joined. Volatile results are still requested, because
  /// asking for them is what the app does and `fastResults` changes what the
  /// finals look like; they are simply not what a transcript is scored on.
  private static func transcribe(
    _ audioURL: URL,
    as locale: Locale,
    biased: Bool
  ) async throws -> String {
    let transcriber = SpeechTranscriber(
      locale: locale,
      transcriptionOptions: [],
      reportingOptions: [.volatileResults, .fastResults],
      attributeOptions: [.transcriptionConfidence]
    )
    if let installation = try await AssetInventory.assetInstallationRequest(
      supporting: [transcriber]
    ) {
      try await installation.downloadAndInstall()
    }

    let context = AnalysisContext()
    if biased {
      context.contextualStrings[.general] = VoiceHostAdapter.spokenVocabulary
    }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.setContext(context)
    guard
      let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }

    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
    let collecting = Task { () -> String in
      var settled = ""
      for try await result in transcriber.results where result.isFinal {
        settled += String(result.text.characters)
      }
      return settled
    }

    try await analyzer.start(inputSequence: stream)
    for buffer in try Self.buffers(of: audioURL, converted: analyzerFormat) {
      continuation.yield(AnalyzerInput(buffer: buffer))
    }
    continuation.finish()
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    return try await collecting.value
  }

  /// [audioURL] read whole and converted to the format the analyzer asked for.
  ///
  /// Whole rather than streamed in real time: the recogniser is being scored
  /// on what it heard, and playing a twelve-second file over twelve seconds
  /// would measure patience. The endpointer is not in this path at all — the
  /// corpus's pause timings are scored by the shadow harness instead.
  private static func buffers(
    of audioURL: URL,
    converted format: AVAudioFormat
  ) throws -> [AVAudioPCMBuffer] {
    let file = try AVAudioFile(forReading: audioURL)
    guard
      let source = AVAudioPCMBuffer(
        pcmFormat: file.processingFormat,
        frameCapacity: AVAudioFrameCount(file.length)
      )
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    try file.read(into: source)

    if file.processingFormat == format {
      return [source]
    }
    guard let converter = AVAudioConverter(from: file.processingFormat, to: format)
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    let ratio = format.sampleRate / file.processingFormat.sampleRate
    // Rounded up and given a whole extra frame: a capacity computed exactly
    // truncates the last partial frame, which is a clipped final word and
    // reads as the recogniser being worse than it is.
    let capacity = AVAudioFrameCount((Double(source.frameLength) * ratio).rounded(.up)) + 1
    guard
      let destination = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    else {
      throw VoiceHostError.audioFormatUnavailable
    }
    var handed = false
    var conversionError: NSError?
    converter.convert(to: destination, error: &conversionError) { _, status in
      if handed {
        status.pointee = .endOfStream
        return nil
      }
      handed = true
      status.pointee = .haveData
      return source
    }
    if let conversionError {
      throw conversionError
    }
    return [destination]
  }
}
