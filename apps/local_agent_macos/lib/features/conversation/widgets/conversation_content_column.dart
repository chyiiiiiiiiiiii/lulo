import 'package:flutter/widgets.dart';

/// Widest the conversation's content column grows, in logical points.
///
/// One column holds everything — the header, the turns, the composer — so
/// their leading edges always agree. Sized for comfortable reading: lines of
/// prose stop being scannable much past this.
const double conversationContentMaxWidth = 820;

/// The margin between the window's edge and the content column.
const double conversationContentMargin = 24;

/// The centred column every part of the conversation lives in.
///
/// The title, the messages and the composer share one column, so however the
/// window is sized — dragged wide, zoomed, full screen — their leading edges
/// stay aligned. Anything laid out against the window instead drifts away
/// from the rest the moment the window grows past the column.
final class ConversationContentColumn extends StatelessWidget {
  /// Places [child] in the shared column.
  const ConversationContentColumn({required this.child, super.key});

  /// The content to align with everything else.
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: conversationContentMaxWidth),
      child: child,
    ),
  );
}
