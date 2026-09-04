import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @voiceTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn voice on'**
  String get voiceTurnOn;

  /// No description provided for @voiceTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn voice off'**
  String get voiceTurnOff;

  /// No description provided for @conversationsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsTooltip;

  /// No description provided for @localModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Local model'**
  String get localModelLabel;

  /// No description provided for @localBadge.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get localBadge;

  /// No description provided for @voiceStopped.
  ///
  /// In en, this message translates to:
  /// **'Voice stopped: {reason}'**
  String voiceStopped(String reason);

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get voiceListening;

  /// No description provided for @voiceThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get voiceThinking;

  /// No description provided for @voiceSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking…'**
  String get voiceSpeaking;

  /// No description provided for @voicePaused.
  ///
  /// In en, this message translates to:
  /// **'Paused — say something to carry on'**
  String get voicePaused;

  /// No description provided for @voiceHolding.
  ///
  /// In en, this message translates to:
  /// **'Listening — let go to send'**
  String get voiceHolding;

  /// No description provided for @voiceAnswering.
  ///
  /// In en, this message translates to:
  /// **'Answering — hold ⇧⌘Space to cut in'**
  String get voiceAnswering;

  /// No description provided for @composerHint.
  ///
  /// In en, this message translates to:
  /// **'Say something to Lulo…'**
  String get composerHint;

  /// No description provided for @sendTooltip.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get sendTooltip;

  /// No description provided for @stopAnswerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Stop the answer'**
  String get stopAnswerTooltip;

  /// No description provided for @holdToTalkHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk, let go to send'**
  String get holdToTalkHint;

  /// No description provided for @turnFailed.
  ///
  /// In en, this message translates to:
  /// **'Response failed'**
  String get turnFailed;

  /// No description provided for @turnStopped.
  ///
  /// In en, this message translates to:
  /// **'Response stopped'**
  String get turnStopped;

  /// No description provided for @turnInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Response interrupted'**
  String get turnInterrupted;

  /// No description provided for @roleYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get roleYou;

  /// No description provided for @roleAssistant.
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get roleAssistant;

  /// No description provided for @copyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// No description provided for @copiedNotice.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copiedNotice;

  /// No description provided for @regenerateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Answer again'**
  String get regenerateTooltip;

  /// No description provided for @reviseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rewrite this question'**
  String get reviseTooltip;

  /// No description provided for @reviseCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reviseCancel;

  /// No description provided for @reviseSubmit.
  ///
  /// In en, this message translates to:
  /// **'Ask again'**
  String get reviseSubmit;

  /// No description provided for @heardDoubtLabel.
  ///
  /// In en, this message translates to:
  /// **'Not sure it heard this right'**
  String get heardDoubtLabel;

  /// No description provided for @heardDoubtTooltip.
  ///
  /// In en, this message translates to:
  /// **'The weakest word scored {score}; anything under {threshold} is marked.'**
  String heardDoubtTooltip(String score, String threshold);

  /// No description provided for @jumpToNewest.
  ///
  /// In en, this message translates to:
  /// **'Jump to the newest message'**
  String get jumpToNewest;

  /// No description provided for @conversationEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get conversationEmptyTitle;

  /// Shown while the local model is still loading, so a question asked in the first seconds after launch is not a silent wait.
  ///
  /// In en, this message translates to:
  /// **'Loading the model…'**
  String get conversationModelLoading;

  /// No description provided for @conversationEmptyNote.
  ///
  /// In en, this message translates to:
  /// **'Private, fast, and ready on this Mac.'**
  String get conversationEmptyNote;

  /// No description provided for @conversationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversationsTitle;

  /// No description provided for @newConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversation;

  /// No description provided for @closeConversations.
  ///
  /// In en, this message translates to:
  /// **'Close the conversation list'**
  String get closeConversations;

  /// No description provided for @nothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get nothingYet;

  /// No description provided for @forgetConversation.
  ///
  /// In en, this message translates to:
  /// **'Forget this conversation'**
  String get forgetConversation;

  /// No description provided for @presenceIdle.
  ///
  /// In en, this message translates to:
  /// **'Agent ready'**
  String get presenceIdle;

  /// No description provided for @presenceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get presenceListening;

  /// No description provided for @presenceThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get presenceThinking;

  /// No description provided for @presenceSpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking'**
  String get presenceSpeaking;

  /// No description provided for @presenceWorking.
  ///
  /// In en, this message translates to:
  /// **'Working'**
  String get presenceWorking;

  /// No description provided for @presenceError.
  ///
  /// In en, this message translates to:
  /// **'Attention needed'**
  String get presenceError;

  /// No description provided for @desktopOrbLabel.
  ///
  /// In en, this message translates to:
  /// **'Lulo, your local assistant. Click to open the conversation, or drag to move it.'**
  String get desktopOrbLabel;

  /// No description provided for @desktopOrbNoticedLabel.
  ///
  /// In en, this message translates to:
  /// **'Lulo, your local assistant. It quietly noted something — click to look, or drag to move it.'**
  String get desktopOrbNoticedLabel;

  /// No description provided for @noticeDismiss.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get noticeDismiss;

  /// No description provided for @noticesMemoryWriteLabel.
  ///
  /// In en, this message translates to:
  /// **'The quiet light for kept memories'**
  String get noticesMemoryWriteLabel;

  /// No description provided for @noticesMemoryWriteNote.
  ///
  /// In en, this message translates to:
  /// **'When Lulo keeps a fact while resting, the orb glows once — no sound, no popup. Open it or ignore it; a light you keep ignoring goes dark by itself.'**
  String get noticesMemoryWriteNote;

  /// No description provided for @noticesTally.
  ///
  /// In en, this message translates to:
  /// **'Lit {lit} times · opened {glanced}'**
  String noticesTally(int lit, int glanced);

  /// No description provided for @noticesMutedNote.
  ///
  /// In en, this message translates to:
  /// **'It kept going unopened, so it has gone dark. It stays dark until you light it again.'**
  String get noticesMutedNote;

  /// No description provided for @noticesReenable.
  ///
  /// In en, this message translates to:
  /// **'Light it again'**
  String get noticesReenable;

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Lulo runs on this Mac'**
  String get firstRunTitle;

  /// No description provided for @firstRunBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing you type or say leaves it. To think, it needs a model — one file, downloaded once, kept here.'**
  String get firstRunBody;

  /// No description provided for @firstRunMicNote.
  ///
  /// In en, this message translates to:
  /// **'The microphone is asked for the first time you talk, not now.'**
  String get firstRunMicNote;

  /// No description provided for @firstRunDismiss.
  ///
  /// In en, this message translates to:
  /// **'Look around first'**
  String get firstRunDismiss;

  /// No description provided for @firstRunDownload.
  ///
  /// In en, this message translates to:
  /// **'Download it'**
  String get firstRunDownload;

  /// No description provided for @firstRunRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get firstRunRetry;

  /// No description provided for @firstRunDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading. You can keep using the Mac; this window can go away and come back.'**
  String get firstRunDownloading;

  /// No description provided for @modelSummary.
  ///
  /// In en, this message translates to:
  /// **'{description} {size}.'**
  String modelSummary(String description, String size);

  /// No description provided for @modelRecommended.
  ///
  /// In en, this message translates to:
  /// **'{name} — recommended'**
  String modelRecommended(String name);

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'The download did not finish: {reason}'**
  String downloadFailed(String reason);

  /// No description provided for @downloadModel.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadModel;

  /// No description provided for @retryDownload.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryDownload;

  /// No description provided for @useModel.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get useModel;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @closeSettings.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get closeSettings;

  /// No description provided for @sectionDesktop.
  ///
  /// In en, this message translates to:
  /// **'Your desktop'**
  String get sectionDesktop;

  /// No description provided for @keepOrbOnTop.
  ///
  /// In en, this message translates to:
  /// **'Keep the orb above other windows'**
  String get keepOrbOnTop;

  /// No description provided for @keepOrbOnTopNote.
  ///
  /// In en, this message translates to:
  /// **'Off puts it in the normal window order, where other windows can cover it.'**
  String get keepOrbOnTopNote;

  /// No description provided for @followAcrossSpaces.
  ///
  /// In en, this message translates to:
  /// **'Follow me between Spaces'**
  String get followAcrossSpaces;

  /// No description provided for @followAcrossSpacesNote.
  ///
  /// In en, this message translates to:
  /// **'Off leaves the orb on the Space it was opened in.'**
  String get followAcrossSpacesNote;

  /// No description provided for @sectionStart.
  ///
  /// In en, this message translates to:
  /// **'When it starts'**
  String get sectionStart;

  /// No description provided for @openOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'Open the conversation on launch'**
  String get openOnLaunch;

  /// No description provided for @openOnLaunchNote.
  ///
  /// In en, this message translates to:
  /// **'Off rests as an orb until you summon it.'**
  String get openOnLaunchNote;

  /// No description provided for @launchAtLogin.
  ///
  /// In en, this message translates to:
  /// **'Be here when I log in'**
  String get launchAtLogin;

  /// No description provided for @launchAtLoginNote.
  ///
  /// In en, this message translates to:
  /// **'Starts Lulo after you log in, so you do not have to.'**
  String get launchAtLoginNote;

  /// No description provided for @launchAtLoginNeedsApproval.
  ///
  /// In en, this message translates to:
  /// **'Not in effect yet — macOS wants you to allow Lulo in System Settings › General › Login Items.'**
  String get launchAtLoginNeedsApproval;

  /// No description provided for @launchAtLoginUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This Mac\'s macOS is too old for this; it needs macOS 13 or later.'**
  String get launchAtLoginUnavailable;

  /// No description provided for @launchAtLoginRefused.
  ///
  /// In en, this message translates to:
  /// **'macOS will not accept this copy of Lulo — open the one in your Applications folder and try again.'**
  String get launchAtLoginRefused;

  /// No description provided for @launchAtLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not ask macOS about this.'**
  String get launchAtLoginFailed;

  /// No description provided for @sidecarSection.
  ///
  /// In en, this message translates to:
  /// **'The two helpers running behind this'**
  String get sidecarSection;

  /// No description provided for @sidecarAllRunning.
  ///
  /// In en, this message translates to:
  /// **'Both are answering.'**
  String get sidecarAllRunning;

  /// No description provided for @sidecarVoiceStopped.
  ///
  /// In en, this message translates to:
  /// **'The voice is not running — Lulo will hear you and think, and stay silent.'**
  String get sidecarVoiceStopped;

  /// No description provided for @sidecarEarsStopped.
  ///
  /// In en, this message translates to:
  /// **'The transcriber is not running — holding the key still works, on the less accurate one.'**
  String get sidecarEarsStopped;

  /// No description provided for @sidecarCannotStart.
  ///
  /// In en, this message translates to:
  /// **'Lulo is sandboxed and cannot start them for you. Start them from a terminal.'**
  String get sidecarCannotStart;

  /// No description provided for @sidecarRecheck.
  ///
  /// In en, this message translates to:
  /// **'Check again'**
  String get sidecarRecheck;

  /// No description provided for @transcribeSection.
  ///
  /// In en, this message translates to:
  /// **'Write a recording out'**
  String get transcribeSection;

  /// No description provided for @transcribeNote.
  ///
  /// In en, this message translates to:
  /// **'Pick an audio file and write it out with the recogniser you already have installed. All of it runs on this computer.'**
  String get transcribeNote;

  /// No description provided for @transcribeChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get transcribeChoose;

  /// No description provided for @transcribeWorking.
  ///
  /// In en, this message translates to:
  /// **'Writing it out — a long recording takes a few minutes.'**
  String get transcribeWorking;

  /// No description provided for @transcribeFailed.
  ///
  /// In en, this message translates to:
  /// **'Nothing came back. Either the transcriber is not running, or it could not read that file — it is a separate process, and macOS asks it separately for Downloads and Desktop.'**
  String get transcribeFailed;

  /// No description provided for @transcribeSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved as {name}'**
  String transcribeSaved(String name);

  /// No description provided for @transcribeHeld.
  ///
  /// In en, this message translates to:
  /// **'Written out but not saved — the text is still here, just pick somewhere.'**
  String get transcribeHeld;

  /// No description provided for @transcribeSaveAgain.
  ///
  /// In en, this message translates to:
  /// **'Save it'**
  String get transcribeSaveAgain;

  /// No description provided for @documentSection.
  ///
  /// In en, this message translates to:
  /// **'Ask about a file'**
  String get documentSection;

  /// No description provided for @documentNote.
  ///
  /// In en, this message translates to:
  /// **'Pick a text file and questions will be answered out of it. Only the parts a question is about are sent.'**
  String get documentNote;

  /// No description provided for @documentChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose a file'**
  String get documentChoose;

  /// No description provided for @documentOpen.
  ///
  /// In en, this message translates to:
  /// **'Reading: {name}'**
  String documentOpen(String name);

  /// No description provided for @documentClose.
  ///
  /// In en, this message translates to:
  /// **'Close it'**
  String get documentClose;

  /// No description provided for @documentUnreadable.
  ///
  /// In en, this message translates to:
  /// **'That file could not be read.'**
  String get documentUnreadable;

  /// No description provided for @sectionModel.
  ///
  /// In en, this message translates to:
  /// **'The model it thinks with'**
  String get sectionModel;

  /// No description provided for @noModelChosen.
  ///
  /// In en, this message translates to:
  /// **'No model chosen'**
  String get noModelChosen;

  /// No description provided for @previewNote.
  ///
  /// In en, this message translates to:
  /// **'Lulo is answering from its built-in preview, which says the same thing every time.'**
  String get previewNote;

  /// No description provided for @modelLoadedNote.
  ///
  /// In en, this message translates to:
  /// **'Loaded now. Choosing another takes a few seconds to swap.'**
  String get modelLoadedNote;

  /// No description provided for @chooseModel.
  ///
  /// In en, this message translates to:
  /// **'Choose…'**
  String get chooseModel;

  /// No description provided for @sectionVoice.
  ///
  /// In en, this message translates to:
  /// **'The voice it speaks with'**
  String get sectionVoice;

  /// No description provided for @voiceLabel.
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voiceLabel;

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Spoken answers use the resident local synthesizer.'**
  String get voiceNote;

  /// No description provided for @sectionTakingTurns.
  ///
  /// In en, this message translates to:
  /// **'Taking turns'**
  String get sectionTakingTurns;

  /// No description provided for @liveConversation.
  ///
  /// In en, this message translates to:
  /// **'Live conversation'**
  String get liveConversation;

  /// No description provided for @liveConversationNote.
  ///
  /// In en, this message translates to:
  /// **'Keeps the microphone open so you can talk any time — and quiets every other app\'s audio while it listens. Off, hold the mic button or ⌘⇧Space to talk.'**
  String get liveConversationNote;

  /// No description provided for @showVoiceEvidence.
  ///
  /// In en, this message translates to:
  /// **'Show why it took the floor'**
  String get showVoiceEvidence;

  /// No description provided for @showVoiceEvidenceNote.
  ///
  /// In en, this message translates to:
  /// **'A running account under the conversation: what was ignored as an acknowledgement, what cut in, and what each turn cost.'**
  String get showVoiceEvidenceNote;

  /// No description provided for @sectionSummoning.
  ///
  /// In en, this message translates to:
  /// **'Summoning'**
  String get sectionSummoning;

  /// No description provided for @showHideConversation.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the conversation'**
  String get showHideConversation;

  /// No description provided for @anywhereOnMac.
  ///
  /// In en, this message translates to:
  /// **'Anywhere on the Mac.'**
  String get anywhereOnMac;

  /// No description provided for @profileWhoItIs.
  ///
  /// In en, this message translates to:
  /// **'Who it is'**
  String get profileWhoItIs;

  /// No description provided for @profileAgentName.
  ///
  /// In en, this message translates to:
  /// **'What it is called'**
  String get profileAgentName;

  /// No description provided for @profileUserName.
  ///
  /// In en, this message translates to:
  /// **'What it calls you'**
  String get profileUserName;

  /// No description provided for @profileUserNameHint.
  ///
  /// In en, this message translates to:
  /// **'Left empty it uses no name'**
  String get profileUserNameHint;

  /// No description provided for @profileHowItTalks.
  ///
  /// In en, this message translates to:
  /// **'How it talks'**
  String get profileHowItTalks;

  /// No description provided for @profileTone.
  ///
  /// In en, this message translates to:
  /// **'Tone'**
  String get profileTone;

  /// No description provided for @profileToneHint.
  ///
  /// In en, this message translates to:
  /// **'Built in: warm, without pretending familiarity. Type to replace it.'**
  String get profileToneHint;

  /// No description provided for @profileHowMuch.
  ///
  /// In en, this message translates to:
  /// **'How much it says'**
  String get profileHowMuch;

  /// No description provided for @lengthShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get lengthShort;

  /// No description provided for @lengthEnough.
  ///
  /// In en, this message translates to:
  /// **'Enough'**
  String get lengthEnough;

  /// No description provided for @lengthThorough.
  ///
  /// In en, this message translates to:
  /// **'Thorough'**
  String get lengthThorough;

  /// No description provided for @profileAdmitUncertainty.
  ///
  /// In en, this message translates to:
  /// **'Say so when it is not sure'**
  String get profileAdmitUncertainty;

  /// No description provided for @profileAdmitUncertaintyNote.
  ///
  /// In en, this message translates to:
  /// **'Off lets it state a guess as though it were a fact.'**
  String get profileAdmitUncertaintyNote;

  /// No description provided for @profileLeadWithAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer first, explain after'**
  String get profileLeadWithAnswer;

  /// No description provided for @profileMemories.
  ///
  /// In en, this message translates to:
  /// **'What it remembers'**
  String get profileMemories;

  /// No description provided for @profileMemoriesNote.
  ///
  /// In en, this message translates to:
  /// **'Facts about you. Each one reaches the model only on a turn it is relevant to, rather than being sent every time.'**
  String get profileMemoriesNote;

  /// No description provided for @profileAddMemoryHint.
  ///
  /// In en, this message translates to:
  /// **'Remember something, such as 我住在台中'**
  String get profileAddMemoryHint;

  /// No description provided for @profileForget.
  ///
  /// In en, this message translates to:
  /// **'Forget this'**
  String get profileForget;

  /// No description provided for @profileTurnTaking.
  ///
  /// In en, this message translates to:
  /// **'Your own words for taking turns'**
  String get profileTurnTaking;

  /// No description provided for @profileTurnTakingNote.
  ///
  /// In en, this message translates to:
  /// **'Each list is added to a built-in one. The built-in lists are a guess about how someone talks, and how you talk is something only you know.'**
  String get profileTurnTakingNote;

  /// No description provided for @profileCarryOn.
  ///
  /// In en, this message translates to:
  /// **'These mean carry on'**
  String get profileCarryOn;

  /// No description provided for @profileCarryOnNote.
  ///
  /// In en, this message translates to:
  /// **'Said while it is talking, these never stop it. A single character also covers being said several times over.'**
  String get profileCarryOnNote;

  /// No description provided for @profileCarryOnHint.
  ///
  /// In en, this message translates to:
  /// **'For example: 蛤'**
  String get profileCarryOnHint;

  /// No description provided for @profileStop.
  ///
  /// In en, this message translates to:
  /// **'These mean stop'**
  String get profileStop;

  /// No description provided for @profileStopNote.
  ///
  /// In en, this message translates to:
  /// **'However short, these end the answer.'**
  String get profileStopNote;

  /// No description provided for @profileStopHint.
  ///
  /// In en, this message translates to:
  /// **'For example: 先停'**
  String get profileStopHint;

  /// No description provided for @profileUnfinished.
  ///
  /// In en, this message translates to:
  /// **'These mean you have not finished'**
  String get profileUnfinished;

  /// No description provided for @profileUnfinishedNote.
  ///
  /// In en, this message translates to:
  /// **'A sentence ending on one of these buys you longer before it answers.'**
  String get profileUnfinishedNote;

  /// No description provided for @profileUnfinishedHint.
  ///
  /// In en, this message translates to:
  /// **'For example: 然後'**
  String get profileUnfinishedHint;

  /// No description provided for @profileVocabulary.
  ///
  /// In en, this message translates to:
  /// **'Names this computer is about'**
  String get profileVocabulary;

  /// No description provided for @profileVocabularyNote.
  ///
  /// In en, this message translates to:
  /// **'Names, products, jargon. The recogniser leans towards these and the text repair leaves them alone. It is a hint, not a guarantee — for a word it actually gets wrong, use the list below.'**
  String get profileVocabularyNote;

  /// No description provided for @profileVocabularyHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Lulo'**
  String get profileVocabularyHint;

  /// No description provided for @profileMisheard.
  ///
  /// In en, this message translates to:
  /// **'Fix a word it mishears, once'**
  String get profileMisheard;

  /// No description provided for @profileMisheardNote.
  ///
  /// In en, this message translates to:
  /// **'When it hears the left, it writes the right instead. A substitution rather than a hint, so it always takes effect.'**
  String get profileMisheardNote;

  /// No description provided for @profileMisheardHeardHint.
  ///
  /// In en, this message translates to:
  /// **'It heard'**
  String get profileMisheardHeardHint;

  /// No description provided for @profileMisheardMeantHint.
  ///
  /// In en, this message translates to:
  /// **'You said'**
  String get profileMisheardMeantHint;

  /// No description provided for @profileMisheardAdd.
  ///
  /// In en, this message translates to:
  /// **'Remember this'**
  String get profileMisheardAdd;

  /// No description provided for @profileWords.
  ///
  /// In en, this message translates to:
  /// **'The words it hears'**
  String get profileWords;

  /// No description provided for @profileWordsNote.
  ///
  /// In en, this message translates to:
  /// **'The recogniser has never met your jargon, and there will always be a word it gets wrong every time.'**
  String get profileWordsNote;

  /// No description provided for @addTooltip.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addTooltip;

  /// No description provided for @modelDescriptionBalanced.
  ///
  /// In en, this message translates to:
  /// **'The balanced choice: answers fast enough to speak with, and strong enough for everyday conversation.'**
  String get modelDescriptionBalanced;

  /// No description provided for @modelDescriptionLight.
  ///
  /// In en, this message translates to:
  /// **'The light choice: quicker to fetch and to answer, with simpler answers.'**
  String get modelDescriptionLight;

  /// No description provided for @modelDescriptionCapable.
  ///
  /// In en, this message translates to:
  /// **'The largest and slowest choice: it needs a recent high-end Mac, and on older machines the first word can take tens of seconds or the answer can fail partway. For long reading and writing, never for talking.'**
  String get modelDescriptionCapable;

  /// No description provided for @speakTooltip.
  ///
  /// In en, this message translates to:
  /// **'Read this aloud'**
  String get speakTooltip;

  /// No description provided for @lookAtScreenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Look at my screen'**
  String get lookAtScreenTooltip;

  /// No description provided for @lookDefaultPrompt.
  ///
  /// In en, this message translates to:
  /// **'Look at my screen and tell me what you see. If something seems off or could be done better, say so.'**
  String get lookDefaultPrompt;

  /// No description provided for @lookDeniedNotice.
  ///
  /// In en, this message translates to:
  /// **'Lulo can’t see the screen — allow Screen Recording for Lulo in System Settings › Privacy & Security. If you just allowed it, quit and reopen Lulo for it to take effect.'**
  String get lookDeniedNotice;

  /// No description provided for @lookFailedNotice.
  ///
  /// In en, this message translates to:
  /// **'That look didn’t work — nothing was captured.'**
  String get lookFailedNotice;

  /// No description provided for @shareFrontmostApp.
  ///
  /// In en, this message translates to:
  /// **'Let it know which app you’re in'**
  String get shareFrontmostApp;

  /// No description provided for @shareFrontmostAppNote.
  ///
  /// In en, this message translates to:
  /// **'Each question carries the name of the app you’re in — the name only, never window titles or contents. It’s how “I’m stuck” knows where.'**
  String get shareFrontmostAppNote;

  /// No description provided for @rememberFacts.
  ///
  /// In en, this message translates to:
  /// **'Let it remember things about you'**
  String get rememberFacts;

  /// No description provided for @rememberFactsNote.
  ///
  /// In en, this message translates to:
  /// **'After each answer it reads what you said for one durable fact — where you live, how you want to be answered — and keeps it in the profile below, where you can switch any of them off. Everything stays on this machine, in plain text.'**
  String get rememberFactsNote;

  /// No description provided for @profileMemoryByAgent.
  ///
  /// In en, this message translates to:
  /// **'Lulo remembered this'**
  String get profileMemoryByAgent;

  /// No description provided for @profileMemoryByUser.
  ///
  /// In en, this message translates to:
  /// **'You wrote this'**
  String get profileMemoryByUser;

  /// No description provided for @profileMemoryByDeveloper.
  ///
  /// In en, this message translates to:
  /// **'From the profile file'**
  String get profileMemoryByDeveloper;

  /// No description provided for @profileForgetLearned.
  ///
  /// In en, this message translates to:
  /// **'Forget everything Lulo has learned'**
  String get profileForgetLearned;

  /// No description provided for @profileForgetLearnedNote.
  ///
  /// In en, this message translates to:
  /// **'Deletes only what Lulo wrote by itself. What you typed here, and what came from the profile file, stays.'**
  String get profileForgetLearnedNote;

  /// No description provided for @profileForgetLearnedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Forget the 1 thing Lulo learned} other{Forget the {count} things Lulo learned}}'**
  String profileForgetLearnedCount(int count);

  /// No description provided for @sectionHearing.
  ///
  /// In en, this message translates to:
  /// **'How it hears you'**
  String get sectionHearing;

  /// No description provided for @hearingHoldTitle.
  ///
  /// In en, this message translates to:
  /// **'Holding the microphone button'**
  String get hearingHoldTitle;

  /// No description provided for @hearingHoldNote.
  ///
  /// In en, this message translates to:
  /// **'Sends when you let go, and hears English as well as Chinese. Where it slips is product names that are also ordinary words — LiteRT as “light RT”, Gemma as “German”, Dart test as “Dark text”. Teach it those once, under the words it keeps mishearing below, and the correction holds for every sentence after.'**
  String get hearingHoldNote;

  /// No description provided for @hearingDuplexTitle.
  ///
  /// In en, this message translates to:
  /// **'Leaving voice on'**
  String get hearingDuplexTitle;

  /// No description provided for @hearingDuplexNote.
  ///
  /// In en, this message translates to:
  /// **'Listens continuously so it can be interrupted, in the language chosen by the setting above — fixed when listening starts and kept for the whole conversation. English is weaker on this path: measured at 13.4% character error against 3.8% when holding the key, so for English the microphone key hears better.'**
  String get hearingDuplexNote;

  /// No description provided for @sectionAnswerStyle.
  ///
  /// In en, this message translates to:
  /// **'How far it may roam'**
  String get sectionAnswerStyle;

  /// No description provided for @answerStyleNote.
  ///
  /// In en, this message translates to:
  /// **'This sets how far it may roam, not how much it says — answer length lives under Agent profile below. Applies to the next question; the model stays loaded.'**
  String get answerStyleNote;

  /// No description provided for @answerStyleSteady.
  ///
  /// In en, this message translates to:
  /// **'Careful'**
  String get answerStyleSteady;

  /// No description provided for @answerStyleBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get answerStyleBalanced;

  /// No description provided for @answerStyleInventive.
  ///
  /// In en, this message translates to:
  /// **'Inventive'**
  String get answerStyleInventive;

  /// No description provided for @answerStyleSteadyNote.
  ///
  /// In en, this message translates to:
  /// **'The same question tends to the same answer.'**
  String get answerStyleSteadyNote;

  /// No description provided for @answerStyleBalancedNote.
  ///
  /// In en, this message translates to:
  /// **'What Lulo shipped with.'**
  String get answerStyleBalancedNote;

  /// No description provided for @answerStyleInventiveNote.
  ///
  /// In en, this message translates to:
  /// **'Freer, and less steady. Good for drafting, not for facts.'**
  String get answerStyleInventiveNote;

  /// No description provided for @exportConversation.
  ///
  /// In en, this message translates to:
  /// **'Save as Markdown'**
  String get exportConversation;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save that conversation.'**
  String get exportFailed;

  /// No description provided for @searchConversations.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get searchConversations;

  /// No description provided for @noMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches that.'**
  String get noMatches;

  /// No description provided for @pinConversation.
  ///
  /// In en, this message translates to:
  /// **'Keep at the top'**
  String get pinConversation;

  /// No description provided for @unpinConversation.
  ///
  /// In en, this message translates to:
  /// **'Stop keeping at the top'**
  String get unpinConversation;

  /// No description provided for @renameConversation.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameConversation;

  /// No description provided for @conversationActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get conversationActions;

  /// No description provided for @menuShow.
  ///
  /// In en, this message translates to:
  /// **'Show Lulo'**
  String get menuShow;

  /// No description provided for @menuHide.
  ///
  /// In en, this message translates to:
  /// **'Hide Lulo'**
  String get menuHide;

  /// No description provided for @menuTalk.
  ///
  /// In en, this message translates to:
  /// **'Talk to Lulo'**
  String get menuTalk;

  /// No description provided for @menuRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get menuRecent;

  /// No description provided for @menuQuit.
  ///
  /// In en, this message translates to:
  /// **'Quit Lulo'**
  String get menuQuit;

  /// No description provided for @orbTalk.
  ///
  /// In en, this message translates to:
  /// **'Talk'**
  String get orbTalk;

  /// No description provided for @orbStopTalking.
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get orbStopTalking;

  /// No description provided for @orbLook.
  ///
  /// In en, this message translates to:
  /// **'Look at my screen'**
  String get orbLook;

  /// No description provided for @orbStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get orbStop;

  /// No description provided for @profileRespelling.
  ///
  /// In en, this message translates to:
  /// **'Words it says wrongly'**
  String get profileRespelling;

  /// No description provided for @profileRespellingNote.
  ///
  /// In en, this message translates to:
  /// **'The voice mispronounces some words badly enough to sound like a different word. Spell one the way it should sound — 企業 as 氣業 — and it will say it right. Only the voice sees the respelling; your transcript keeps the real word.'**
  String get profileRespellingNote;

  /// No description provided for @profileRespellingWordHint.
  ///
  /// In en, this message translates to:
  /// **'The word'**
  String get profileRespellingWordHint;

  /// No description provided for @profileRespellingSaidAsHint.
  ///
  /// In en, this message translates to:
  /// **'Spell it this way'**
  String get profileRespellingSaidAsHint;

  /// No description provided for @profileRespellingAdd.
  ///
  /// In en, this message translates to:
  /// **'Teach'**
  String get profileRespellingAdd;

  /// No description provided for @orbActionsSetting.
  ///
  /// In en, this message translates to:
  /// **'Buttons under the resting orb'**
  String get orbActionsSetting;

  /// No description provided for @orbActionsSettingNote.
  ///
  /// In en, this message translates to:
  /// **'Hover the orb to talk, take a look at your screen, or stop an answer — without opening the window.'**
  String get orbActionsSettingNote;

  /// No description provided for @sectionObsidian.
  ///
  /// In en, this message translates to:
  /// **'Your notes'**
  String get sectionObsidian;

  /// No description provided for @obsidianJournal.
  ///
  /// In en, this message translates to:
  /// **'Write finished exchanges into my notes'**
  String get obsidianJournal;

  /// No description provided for @obsidianJournalNote.
  ///
  /// In en, this message translates to:
  /// **'One page a day, appended as you go, in Markdown. Nothing already written is ever changed — the page is yours, and it stays readable long after Lulo is gone.'**
  String get obsidianJournalNote;

  /// No description provided for @obsidianChooseFolder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder…'**
  String get obsidianChooseFolder;

  /// No description provided for @obsidianChangeFolder.
  ///
  /// In en, this message translates to:
  /// **'Change folder…'**
  String get obsidianChangeFolder;

  /// No description provided for @obsidianNoFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder chosen yet.'**
  String get obsidianNoFolder;

  /// No description provided for @obsidianForget.
  ///
  /// In en, this message translates to:
  /// **'Stop and forget the folder'**
  String get obsidianForget;

  /// No description provided for @obsidianDayHeading.
  ///
  /// In en, this message translates to:
  /// **'Talking with Lulo'**
  String get obsidianDayHeading;

  /// No description provided for @obsidianWriteDenied.
  ///
  /// In en, this message translates to:
  /// **'The folder can no longer be opened. It was moved, renamed, or deleted — choose it again.'**
  String get obsidianWriteDenied;

  /// No description provided for @obsidianWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'The last entry could not be written.'**
  String get obsidianWriteFailed;

  /// No description provided for @obsidianWriteNoVault.
  ///
  /// In en, this message translates to:
  /// **'Nothing is being written: no folder has been chosen.'**
  String get obsidianWriteNoVault;

  /// No description provided for @activityIdle.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get activityIdle;

  /// No description provided for @activityListening.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get activityListening;

  /// No description provided for @activityThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get activityThinking;

  /// No description provided for @activitySpeaking.
  ///
  /// In en, this message translates to:
  /// **'Speaking…'**
  String get activitySpeaking;

  /// No description provided for @activityWorking.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get activityWorking;

  /// No description provided for @activityError.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get activityError;

  /// No description provided for @answering.
  ///
  /// In en, this message translates to:
  /// **'Answering'**
  String get answering;

  /// No description provided for @thinkingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get thinkingPlaceholder;

  /// No description provided for @sectionConversationLanguage.
  ///
  /// In en, this message translates to:
  /// **'The language it talks in'**
  String get sectionConversationLanguage;

  /// No description provided for @conversationLanguageNote.
  ///
  /// In en, this message translates to:
  /// **'Which language the microphone is opened on. A typed question is answered in whatever language it was asked in, either way.'**
  String get conversationLanguageNote;

  /// No description provided for @conversationLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get conversationLanguageEnglish;

  /// No description provided for @conversationLanguageEnglishNote.
  ///
  /// In en, this message translates to:
  /// **'The default. Measured: the voice reads English back word-perfect through a recogniser, with no pronunciation table needed.'**
  String get conversationLanguageEnglishNote;

  /// No description provided for @conversationLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'中文'**
  String get conversationLanguageChinese;

  /// No description provided for @conversationLanguageChineseNote.
  ///
  /// In en, this message translates to:
  /// **'Taiwanese Mandarin. The voice needs a table of 214 respellings to say ordinary words correctly; one screened word in eight was wrong before it was taught.'**
  String get conversationLanguageChineseNote;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
