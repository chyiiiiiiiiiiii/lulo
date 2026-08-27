/// Something the resting agent can be asked to do without being opened.
///
/// The bar an action has to clear to earn a place here is narrow on purpose:
/// **doing it any other way has to cost a summon.** The orb is a resting
/// agent, not a launcher, and a strip that filled up with everything the app
/// can do would be a worse menu bar drawn on top of the desktop. Three
/// candidates cleared it, and several did not — a new conversation, a
/// clipboard question and a settings shortcut are all one keystroke or one
/// click away from a window the user is already opening.
enum OrbActionKind {
  /// Open or close the microphone, leaving the agent resting.
  ///
  /// The one that matters most. The conversation stays mounted while the orb
  /// rests, so the ears can open without the window coming back — which is
  /// the difference between an assistant that lives on the desktop and a
  /// window that happens to be small.
  talk,

  /// Take one look at the screen and ask about it.
  ///
  /// Otherwise: summon, find the eye in the composer, press it, ask. The
  /// answer has to be readable, so this one does bring the window back.
  look,

  /// Stop the answer being produced or spoken.
  ///
  /// Interrupting by voice only works while the microphone is open, and an
  /// answer being read aloud to a resting orb is exactly when the user has no
  /// window to press stop in.
  stop,
}

/// What the resting orb should offer right now.
///
/// The order never changes and the positions never shift: a button that moves
/// under the pointer between one hover and the next cannot be learned, and
/// learning it is the entire reason to prefer this to the menu bar. [stop]
/// appears and disappears at the end rather than pushing its way to the
/// front, even though it is the urgent one.
///
/// Nothing at all is offered without a model: an orb whose microphone opens
/// onto something that cannot answer is worse than an orb that offers
/// nothing, because the failure arrives after the user has spoken.
List<OrbActionKind> orbActionsFor({
  required bool hasModel,
  required bool canTalk,
  required bool canLook,
  required bool busy,
}) {
  if (!hasModel) {
    return const <OrbActionKind>[];
  }
  return <OrbActionKind>[
    if (canTalk) OrbActionKind.talk,
    if (canLook) OrbActionKind.look,
    if (busy) OrbActionKind.stop,
  ];
}
