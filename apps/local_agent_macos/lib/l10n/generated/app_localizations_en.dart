// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get voiceTurnOn => 'Turn voice on';

  @override
  String get voiceTurnOff => 'Turn voice off';

  @override
  String get conversationsTooltip => 'Conversations';

  @override
  String get localModelLabel => 'Local model';

  @override
  String get localBadge => 'Local';

  @override
  String voiceStopped(String reason) {
    return 'Voice stopped: $reason';
  }

  @override
  String get voiceListening => 'Listening…';

  @override
  String get voiceThinking => 'Thinking…';

  @override
  String get voiceSpeaking => 'Speaking…';

  @override
  String get voicePaused => 'Paused — say something to carry on';

  @override
  String get voiceHolding => 'Listening — let go to send';

  @override
  String get voiceAnswering => 'Answering — hold ⇧⌘Space to cut in';

  @override
  String get composerHint => 'Say something to Lulo…';

  @override
  String get sendTooltip => 'Send';

  @override
  String get stopAnswerTooltip => 'Stop the answer';

  @override
  String get holdToTalkHint => 'Hold to talk, let go to send';

  @override
  String get turnFailed => 'Response failed';

  @override
  String get turnStopped => 'Response stopped';

  @override
  String get turnInterrupted => 'Response interrupted';

  @override
  String get roleYou => 'You';

  @override
  String get roleAssistant => 'Assistant';

  @override
  String get copyTooltip => 'Copy';

  @override
  String get copiedNotice => 'Copied';

  @override
  String get regenerateTooltip => 'Answer again';

  @override
  String get reviseTooltip => 'Rewrite this question';

  @override
  String get reviseCancel => 'Cancel';

  @override
  String get reviseSubmit => 'Ask again';

  @override
  String get heardDoubtLabel => 'Not sure it heard this right';

  @override
  String heardDoubtTooltip(String score, String threshold) {
    return 'The weakest word scored $score; anything under $threshold is marked.';
  }

  @override
  String get jumpToNewest => 'Jump to the newest message';

  @override
  String get conversationEmptyTitle => 'Start a conversation';

  @override
  String get conversationModelLoading => 'Loading the model…';

  @override
  String get conversationEmptyNote => 'Private, fast, and ready on this Mac.';

  @override
  String get conversationsTitle => 'Conversations';

  @override
  String get newConversation => 'New conversation';

  @override
  String get closeConversations => 'Close the conversation list';

  @override
  String get nothingYet => 'Nothing yet';

  @override
  String get forgetConversation => 'Forget this conversation';

  @override
  String get presenceIdle => 'Agent ready';

  @override
  String get presenceListening => 'Listening';

  @override
  String get presenceThinking => 'Thinking';

  @override
  String get presenceSpeaking => 'Speaking';

  @override
  String get presenceWorking => 'Working';

  @override
  String get presenceError => 'Attention needed';

  @override
  String get desktopOrbLabel =>
      'Lulo, your local assistant. Click to open the conversation, or drag to move it.';

  @override
  String get firstRunTitle => 'Lulo runs on this Mac';

  @override
  String get firstRunBody =>
      'Nothing you type or say leaves it. To think, it needs a model — one file, downloaded once, kept here.';

  @override
  String get firstRunMicNote =>
      'The microphone is asked for the first time you talk, not now.';

  @override
  String get firstRunDismiss => 'Look around first';

  @override
  String get firstRunDownload => 'Download it';

  @override
  String get firstRunRetry => 'Try again';

  @override
  String get firstRunDownloading =>
      'Downloading. You can keep using the Mac; this window can go away and come back.';

  @override
  String modelSummary(String description, String size) {
    return '$description $size.';
  }

  @override
  String modelRecommended(String name) {
    return '$name — recommended';
  }

  @override
  String downloadFailed(String reason) {
    return 'The download did not finish: $reason';
  }

  @override
  String get downloadModel => 'Download';

  @override
  String get retryDownload => 'Retry';

  @override
  String get useModel => 'Use';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get closeSettings => 'Close settings';

  @override
  String get sectionDesktop => 'Your desktop';

  @override
  String get keepOrbOnTop => 'Keep the orb above other windows';

  @override
  String get keepOrbOnTopNote =>
      'Off puts it in the normal window order, where other windows can cover it.';

  @override
  String get followAcrossSpaces => 'Follow me between Spaces';

  @override
  String get followAcrossSpacesNote =>
      'Off leaves the orb on the Space it was opened in.';

  @override
  String get sectionStart => 'When it starts';

  @override
  String get openOnLaunch => 'Open the conversation on launch';

  @override
  String get openOnLaunchNote => 'Off rests as an orb until you summon it.';

  @override
  String get launchAtLogin => 'Be here when I log in';

  @override
  String get launchAtLoginNote =>
      'Starts Lulo after you log in, so you do not have to.';

  @override
  String get launchAtLoginNeedsApproval =>
      'Not in effect yet — macOS wants you to allow Lulo in System Settings › General › Login Items.';

  @override
  String get launchAtLoginUnavailable =>
      'This Mac\'s macOS is too old for this; it needs macOS 13 or later.';

  @override
  String get launchAtLoginRefused =>
      'macOS will not accept this copy of Lulo — open the one in your Applications folder and try again.';

  @override
  String get launchAtLoginFailed => 'Could not ask macOS about this.';

  @override
  String get sidecarSection => 'The two helpers running behind this';

  @override
  String get sidecarAllRunning => 'Both are answering.';

  @override
  String get sidecarVoiceStopped =>
      'The voice is not running — Lulo will hear you and think, and stay silent.';

  @override
  String get sidecarEarsStopped =>
      'The transcriber is not running — holding the key still works, on the less accurate one.';

  @override
  String get sidecarCannotStart =>
      'Lulo is sandboxed and cannot start them for you. Start them from a terminal.';

  @override
  String get sidecarRecheck => 'Check again';

  @override
  String get transcribeSection => 'Write a recording out';

  @override
  String get transcribeNote =>
      'Pick an audio file and write it out with the recogniser you already have installed. All of it runs on this computer.';

  @override
  String get transcribeChoose => 'Choose a file';

  @override
  String get transcribeWorking =>
      'Writing it out — a long recording takes a few minutes.';

  @override
  String get transcribeFailed =>
      'Nothing came back. Either the transcriber is not running, or it could not read that file — it is a separate process, and macOS asks it separately for Downloads and Desktop.';

  @override
  String transcribeSaved(String name) {
    return 'Saved as $name';
  }

  @override
  String get transcribeHeld =>
      'Written out but not saved — the text is still here, just pick somewhere.';

  @override
  String get transcribeSaveAgain => 'Save it';

  @override
  String get documentSection => 'Ask about a file';

  @override
  String get documentNote =>
      'Pick a text file and questions will be answered out of it. Only the parts a question is about are sent.';

  @override
  String get documentChoose => 'Choose a file';

  @override
  String documentOpen(String name) {
    return 'Reading: $name';
  }

  @override
  String get documentClose => 'Close it';

  @override
  String get documentUnreadable => 'That file could not be read.';

  @override
  String get sectionModel => 'The model it thinks with';

  @override
  String get noModelChosen => 'No model chosen';

  @override
  String get previewNote =>
      'Lulo is answering from its built-in preview, which says the same thing every time.';

  @override
  String get modelLoadedNote =>
      'Loaded now. Choosing another takes a few seconds to swap.';

  @override
  String get chooseModel => 'Choose…';

  @override
  String get sectionVoice => 'The voice it speaks with';

  @override
  String get voiceLabel => 'Voice';

  @override
  String get voiceNote => 'Spoken answers use the resident local synthesizer.';

  @override
  String get sectionTakingTurns => 'Taking turns';

  @override
  String get showVoiceEvidence => 'Show why it took the floor';

  @override
  String get showVoiceEvidenceNote =>
      'A running account under the conversation: what was ignored as an acknowledgement, what cut in, and what each turn cost.';

  @override
  String get sectionSummoning => 'Summoning';

  @override
  String get showHideConversation => 'Show or hide the conversation';

  @override
  String get anywhereOnMac => 'Anywhere on the Mac.';

  @override
  String get profileWhoItIs => 'Who it is';

  @override
  String get profileAgentName => 'What it is called';

  @override
  String get profileUserName => 'What it calls you';

  @override
  String get profileUserNameHint => 'Left empty it uses no name';

  @override
  String get profileHowItTalks => 'How it talks';

  @override
  String get profileTone => 'Tone';

  @override
  String get profileToneHint => 'For example: 直接一點，不要客套';

  @override
  String get profileHowMuch => 'How much it says';

  @override
  String get lengthShort => 'Short';

  @override
  String get lengthEnough => 'Enough';

  @override
  String get lengthThorough => 'Thorough';

  @override
  String get profileAdmitUncertainty => 'Say so when it is not sure';

  @override
  String get profileAdmitUncertaintyNote =>
      'Off lets it state a guess as though it were a fact.';

  @override
  String get profileLeadWithAnswer => 'Answer first, explain after';

  @override
  String get profileMemories => 'What it remembers';

  @override
  String get profileMemoriesNote =>
      'Facts about you. Each one reaches the model only on a turn it is relevant to, rather than being sent every time.';

  @override
  String get profileAddMemoryHint => 'Remember something, such as 我住在台中';

  @override
  String get profileForget => 'Forget this';

  @override
  String get profileTurnTaking => 'Your own words for taking turns';

  @override
  String get profileTurnTakingNote =>
      'Each list is added to a built-in one. The built-in lists are a guess about how someone talks, and how you talk is something only you know.';

  @override
  String get profileCarryOn => 'These mean carry on';

  @override
  String get profileCarryOnNote =>
      'Said while it is talking, these never stop it. A single character also covers being said several times over.';

  @override
  String get profileCarryOnHint => 'For example: 蛤';

  @override
  String get profileStop => 'These mean stop';

  @override
  String get profileStopNote => 'However short, these end the answer.';

  @override
  String get profileStopHint => 'For example: 先停';

  @override
  String get profileUnfinished => 'These mean you have not finished';

  @override
  String get profileUnfinishedNote =>
      'A sentence ending on one of these buys you longer before it answers.';

  @override
  String get profileUnfinishedHint => 'For example: 然後';

  @override
  String get profileVocabulary => 'Names this computer is about';

  @override
  String get profileVocabularyNote =>
      'Names, products, jargon. The recogniser leans towards these and the text repair leaves them alone. It is a hint, not a guarantee — for a word it actually gets wrong, use the list below.';

  @override
  String get profileVocabularyHint => 'For example: Lulo';

  @override
  String get profileMisheard => 'Fix a word it mishears, once';

  @override
  String get profileMisheardNote =>
      'When it hears the left, it writes the right instead. A substitution rather than a hint, so it always takes effect.';

  @override
  String get profileMisheardHeardHint => 'It heard';

  @override
  String get profileMisheardMeantHint => 'You said';

  @override
  String get profileMisheardAdd => 'Remember this';

  @override
  String get profileWords => 'The words it hears';

  @override
  String get profileWordsNote =>
      'The recogniser has never met your jargon, and there will always be a word it gets wrong every time.';

  @override
  String get addTooltip => 'Add';

  @override
  String get modelDescriptionBalanced =>
      'The balanced choice: answers fast enough to speak with, and strong enough for everyday conversation.';

  @override
  String get modelDescriptionLight =>
      'The light choice: quicker to fetch and to answer, with simpler answers.';

  @override
  String get modelDescriptionCapable =>
      'The largest and slowest choice: it needs a recent high-end Mac, and on older machines the first word can take tens of seconds or the answer can fail partway. For long reading and writing, never for talking.';

  @override
  String get shareFrontmostApp => 'Let it know which app you’re in';

  @override
  String get shareFrontmostAppNote =>
      'Each question carries the name of the app you’re in — the name only, never window titles or contents. It’s how “I’m stuck” knows where.';

  @override
  String get sectionHearing => 'How it hears you';

  @override
  String get hearingHoldTitle => 'Holding the microphone button';

  @override
  String get hearingHoldNote =>
      'Sends when you let go, and hears English as well as Chinese. Product names that are also ordinary English words are where it slips — Swift, Dart, test.';

  @override
  String get hearingDuplexTitle => 'Leaving voice on';

  @override
  String get hearingDuplexNote =>
      'Listens continuously so it can be interrupted, using the first of your preferred languages it supports — chosen when listening starts and kept for the whole conversation. English is weaker on this path: measured at 13.4% character error against 3.8% when holding the key, so for English the microphone key hears better.';

  @override
  String get sectionAnswerStyle => 'How far it may roam';

  @override
  String get answerStyleNote =>
      'Applies to the next question. The model stays loaded; only the conversation is rebuilt.';

  @override
  String get answerStyleSteady => 'Careful';

  @override
  String get answerStyleBalanced => 'Balanced';

  @override
  String get answerStyleInventive => 'Inventive';

  @override
  String get answerStyleSteadyNote =>
      'The same question tends to the same answer.';

  @override
  String get answerStyleBalancedNote => 'What Lulo shipped with.';

  @override
  String get answerStyleInventiveNote =>
      'Freer, and less steady. Good for drafting, not for facts.';

  @override
  String get exportConversation => 'Save as Markdown';

  @override
  String get exportFailed => 'Could not save that conversation.';

  @override
  String get searchConversations => 'Search conversations';

  @override
  String get noMatches => 'Nothing matches that.';

  @override
  String get pinConversation => 'Keep at the top';

  @override
  String get unpinConversation => 'Stop keeping at the top';

  @override
  String get renameConversation => 'Rename';

  @override
  String get conversationActions => 'More';

  @override
  String get menuShow => 'Show Lulo';

  @override
  String get menuHide => 'Hide Lulo';

  @override
  String get menuTalk => 'Talk to Lulo';

  @override
  String get menuRecent => 'Recent';

  @override
  String get menuQuit => 'Quit Lulo';

  @override
  String get activityIdle => 'Ready';

  @override
  String get activityListening => 'Listening…';

  @override
  String get activityThinking => 'Thinking…';

  @override
  String get activitySpeaking => 'Speaking…';

  @override
  String get activityWorking => 'Working…';

  @override
  String get activityError => 'Needs attention';

  @override
  String get answering => 'Answering';

  @override
  String get thinkingPlaceholder => 'Thinking…';
}
