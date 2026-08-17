/// Work the app does with the model that is not the conversation.
///
/// There is exactly one generation slot on the runtime —
/// `LiteRTLMRuntimeBackend` refuses a second `startGeneration` with
/// `generationBusy` — so anything the app runs between turns is borrowing
/// the thing the user's next question needs. This interface is that loan and
/// its recall.
///
/// The conversation calls [yieldSlot] before every question and [consider]
/// after every finished turn, and knows nothing else about what is on the
/// other side. Today that is `AgentMemoryExtractor`; a summariser or a title
/// writer would arrive the same way.
abstract interface class BetweenTurns {
  /// Offers what the user just said, now that the answer is finished.
  ///
  /// Returns immediately. Whatever this starts must be abandonable, because
  /// [yieldSlot] can arrive a moment later.
  void consider(String said);

  /// Gives the runtime slot back, dropping whatever was using it.
  ///
  /// Awaited before a question starts, so the cancellation reaches the host
  /// ahead of the question's own start — the two crossing on the wire is
  /// how a turn gets refused as busy. The user always wins: a fact can be
  /// read out of the next thing they say, and a refused question cannot be
  /// un-refused.
  Future<void> yieldSlot();
}
