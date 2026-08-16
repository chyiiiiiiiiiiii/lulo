// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get voiceTurnOn => '開啟語音對話';

  @override
  String get voiceTurnOff => '關閉語音對話';

  @override
  String get conversationsTooltip => '對話紀錄';

  @override
  String get localModelLabel => '本機模型';

  @override
  String get localBadge => '本機';

  @override
  String voiceStopped(String reason) {
    return '語音中斷：$reason';
  }

  @override
  String get voiceListening => '聆聽中…';

  @override
  String get voiceThinking => '思考中…';

  @override
  String get voiceSpeaking => '說話中…';

  @override
  String get voicePaused => '已暫停——說句話就繼續';

  @override
  String get voiceHolding => '正在聽你說——放開送出';

  @override
  String get voiceAnswering => '回答中——按住 ⇧⌘Space 可插話';

  @override
  String get composerHint => '跟 Lulo 說些什麼…';

  @override
  String get sendTooltip => '傳送';

  @override
  String get stopAnswerTooltip => '停止回答';

  @override
  String get holdToTalkHint => '按住說話，放開送出';

  @override
  String get turnFailed => '回答失敗';

  @override
  String get turnStopped => '回答已停止';

  @override
  String get turnInterrupted => '回答被中斷';

  @override
  String get roleYou => '你';

  @override
  String get roleAssistant => '助理';

  @override
  String get copyTooltip => '複製';

  @override
  String get copiedNotice => '已複製';

  @override
  String get regenerateTooltip => '重新回答';

  @override
  String get reviseTooltip => '改寫這個問題';

  @override
  String get reviseCancel => '取消';

  @override
  String get reviseSubmit => '再問一次';

  @override
  String get heardDoubtLabel => '不確定有沒有聽對';

  @override
  String heardDoubtTooltip(String score, String threshold) {
    return '最弱的一個詞只有 $score 分；低於 $threshold 就會標記。';
  }

  @override
  String get jumpToNewest => '跳到最新的訊息';

  @override
  String get conversationEmptyTitle => '開始對話';

  @override
  String get conversationModelLoading => '正在載入模型…';

  @override
  String get conversationEmptyNote => '都在這台 Mac 上，不外傳、也不用等。';

  @override
  String get conversationsTitle => '對話紀錄';

  @override
  String get newConversation => '開新對話';

  @override
  String get closeConversations => '關閉對話清單';

  @override
  String get nothingYet => '還沒有紀錄';

  @override
  String get forgetConversation => '忘掉這則對話';

  @override
  String get presenceIdle => '助理待命中';

  @override
  String get presenceListening => '聆聽中';

  @override
  String get presenceThinking => '思考中';

  @override
  String get presenceSpeaking => '說話中';

  @override
  String get presenceWorking => '工作中';

  @override
  String get presenceError => '需要處理';

  @override
  String get desktopOrbLabel => 'Lulo，你的本機助理。點一下開啟對話，或拖曳移動。';

  @override
  String get firstRunTitle => 'Lulo 跑在這台 Mac 上';

  @override
  String get firstRunBody =>
      '你打的、你說的都不會離開這台電腦。但它需要一個模型才能思考 —— 一個檔案，下載一次，就放在這裡。';

  @override
  String get firstRunMicNote => '麥克風會在你第一次開口時才詢問，現在不用。';

  @override
  String get firstRunDismiss => '先看看就好';

  @override
  String get firstRunDownload => '下載';

  @override
  String get firstRunRetry => '再試一次';

  @override
  String get firstRunDownloading => '下載中。你可以繼續用這台 Mac，這個視窗關掉再開也沒關係。';

  @override
  String modelSummary(String description, String size) {
    return '$description $size。';
  }

  @override
  String modelRecommended(String name) {
    return '$name —— 建議';
  }

  @override
  String downloadFailed(String reason) {
    return '下載沒有完成：$reason';
  }

  @override
  String get downloadModel => '下載';

  @override
  String get retryDownload => '重試';

  @override
  String get useModel => '使用';

  @override
  String get settingsTitle => '設定';

  @override
  String get closeSettings => '關閉設定';

  @override
  String get sectionDesktop => '你的桌面';

  @override
  String get keepOrbOnTop => '讓球體浮在其他視窗之上';

  @override
  String get keepOrbOnTopNote => '關掉之後它會回到一般的視窗順序，可能被其他視窗蓋住。';

  @override
  String get followAcrossSpaces => '跟著我切換桌面';

  @override
  String get followAcrossSpacesNote => '關掉之後球體會留在原本開啟的那個桌面。';

  @override
  String get sectionStart => '啟動的時候';

  @override
  String get openOnLaunch => '啟動就打開對話';

  @override
  String get openOnLaunchNote => '關掉的話它會先以球體待命，等你叫它。';

  @override
  String get launchAtLogin => '登入時就在';

  @override
  String get launchAtLoginNote => '開機登入後自動啟動，不用每次自己打開。';

  @override
  String get launchAtLoginNeedsApproval =>
      '還沒生效 —— macOS 要你先到「系統設定 › 一般 › 登入項目」裡允許 Lulo。';

  @override
  String get launchAtLoginUnavailable =>
      '這台 Mac 的 macOS 版本還沒有這個功能，要 macOS 13 以上。';

  @override
  String get launchAtLoginRefused =>
      'macOS 不接受這份 Lulo 的簽章 —— 從「應用程式」資料夾裡的那份開啟再試。';

  @override
  String get launchAtLoginFailed => '問不到 macOS 的設定。';

  @override
  String get sidecarSection => '在背景幫忙的兩個程式';

  @override
  String get sidecarAllRunning => '兩個都有回應。';

  @override
  String get sidecarVoiceStopped => '講話的那個沒在跑 —— Lulo 聽得到也想得出來，但不會出聲。';

  @override
  String get sidecarEarsStopped => '聽寫的那個沒在跑 —— 按住講話還能用，但會用比較不準的那一套。';

  @override
  String get sidecarCannotStart => 'Lulo 在沙盒裡，沒辦法幫你啟動它們。到終端機把它們開起來就好。';

  @override
  String get sidecarRecheck => '重新檢查';

  @override
  String get transcribeSection => '把錄音寫成文字';

  @override
  String get transcribeNote => '選一個錄音檔，用你已經裝好的那套辨識器寫出來。整段都在這台電腦上跑。';

  @override
  String get transcribeChoose => '選檔案';

  @override
  String get transcribeWorking => '寫字中 —— 長一點的錄音要等幾分鐘。';

  @override
  String get transcribeFailed =>
      '沒有寫出東西。可能是聽寫的程式沒在跑，也可能是它讀不到那個檔案 —— 它是另一個行程，第一次讀「下載」或「桌面」時 macOS 會另外要權限。';

  @override
  String transcribeSaved(String name) {
    return '已存成 $name';
  }

  @override
  String get transcribeHeld => '寫好了，但還沒存 —— 文字還在，按「存檔」選個地方就好。';

  @override
  String get transcribeSaveAgain => '存檔';

  @override
  String get documentSection => '拿一份檔案來問';

  @override
  String get documentNote => '選一個文字檔，之後的問題會從裡面找答案。只有跟問題有關的那幾段會被送進去。';

  @override
  String get documentChoose => '選檔案';

  @override
  String documentOpen(String name) {
    return '正在看：$name';
  }

  @override
  String get documentClose => '關掉';

  @override
  String get documentUnreadable => '讀不到那個檔案。';

  @override
  String get sectionModel => '它用來思考的模型';

  @override
  String get noModelChosen => '還沒選模型';

  @override
  String get previewNote => 'Lulo 現在是用內建的預覽回答，每次都講同一句。';

  @override
  String get modelLoadedNote => '已經載入。換另一個要花幾秒鐘。';

  @override
  String get chooseModel => '選擇⋯';

  @override
  String get sectionVoice => '它說話的聲音';

  @override
  String get voiceLabel => '聲音';

  @override
  String get voiceNote => '念出來的回答用的是這台電腦上的合成器。';

  @override
  String get sectionTakingTurns => '輪流講話';

  @override
  String get showVoiceEvidence => '顯示它為什麼接話或讓話';

  @override
  String get showVoiceEvidenceNote => '在對話下方持續記錄：哪些被當成附和而忽略、哪些插了話、每一輪花了多久。';

  @override
  String get sectionSummoning => '叫出來';

  @override
  String get showHideConversation => '顯示或隱藏對話';

  @override
  String get anywhereOnMac => '在這台 Mac 的任何地方都可以。';

  @override
  String get profileWhoItIs => '它是誰';

  @override
  String get profileAgentName => '它的名字';

  @override
  String get profileUserName => '它怎麼稱呼你';

  @override
  String get profileUserNameHint => '留白就不特別稱呼';

  @override
  String get profileHowItTalks => '它怎麼講話';

  @override
  String get profileTone => '語氣';

  @override
  String get profileToneHint => '例如：直接一點，不要客套';

  @override
  String get profileHowMuch => '回答長度';

  @override
  String get lengthShort => '簡短';

  @override
  String get lengthEnough => '適中';

  @override
  String get lengthThorough => '詳細';

  @override
  String get profileAdmitUncertainty => '不確定的時候就說不確定';

  @override
  String get profileAdmitUncertaintyNote => '關掉會讓它把猜測講得像事實。';

  @override
  String get profileLeadWithAnswer => '先講答案，再講原因';

  @override
  String get profileMemories => '它記得的事';

  @override
  String get profileMemoriesNote => '關於你的事實。每一條只會在跟它有關的那一輪被送進去，不是每次都送。';

  @override
  String get profileAddMemoryHint => '記住一件事，例如：我住在台中';

  @override
  String get profileForget => '忘掉這件事';

  @override
  String get profileTurnTaking => '你自己的接話用語';

  @override
  String get profileTurnTakingNote =>
      '這三份清單都是加在內建清單之上。內建的是對「一般人怎麼說話」的猜測，而你怎麼說話只有你知道。';

  @override
  String get profileCarryOn => '這些代表「你繼續」';

  @override
  String get profileCarryOnNote => '它講話時你說這些，它不會停。單一個字也涵蓋連說好幾次的情況。';

  @override
  String get profileCarryOnHint => '例如：蛤';

  @override
  String get profileStop => '這些代表「停」';

  @override
  String get profileStopNote => '不管多短，聽到就結束回答。';

  @override
  String get profileStopHint => '例如：先停';

  @override
  String get profileUnfinished => '這些代表「我還沒講完」';

  @override
  String get profileUnfinishedNote => '句子停在這些字上時，它會多等一下再回答。';

  @override
  String get profileUnfinishedHint => '例如：然後';

  @override
  String get profileVocabulary => '這台電腦上的專有名詞';

  @override
  String get profileVocabularyNote =>
      '名字、產品名、術語。辨識時會偏向聽成它們，文字修正也不會改動它們。這是提示，不保證有效 —— 真的聽錯了，用下面那份。';

  @override
  String get profileVocabularyHint => '例如：Lulo';

  @override
  String get profileMisheard => '它聽錯的字，教一次就好';

  @override
  String get profileMisheardNote => '聽成左邊的時候，直接換成右邊。這是替換，不是提示，所以一定會生效。';

  @override
  String get profileMisheardHeardHint => '它聽成';

  @override
  String get profileMisheardMeantHint => '其實是';

  @override
  String get profileMisheardAdd => '記住這組';

  @override
  String get profileWords => '它聽到的字';

  @override
  String get profileWordsNote => '辨識器沒聽過你的專有名詞，也一定會有它每次都聽錯的字。';

  @override
  String get addTooltip => '新增';

  @override
  String get modelDescriptionBalanced => '平衡的選擇：快到可以用講的，日常對話也夠強。';

  @override
  String get modelDescriptionLight => '輕量的選擇：下載跟回答都更快，但答案比較簡單。';

  @override
  String get modelDescriptionCapable =>
      '最大也最慢的選擇：需要較新的高階 Mac，在較舊的機器上第一個字可能要等數十秒，甚至中途失敗。適合讀寫長文，不適合對話。';

  @override
  String get shareFrontmostApp => '讓它知道你在用哪個 App';

  @override
  String get shareFrontmostAppNote =>
      '每個問題會帶上目前 App 的名稱 —— 只有名稱，不看視窗標題或內容。這樣說「我卡住了」它就知道你卡在哪裡。';

  @override
  String get sectionHearing => '它怎麼聽你說話';

  @override
  String get hearingHoldTitle => '按住麥克風鍵';

  @override
  String get hearingHoldNote =>
      '放開就送出，中文英文都聽得懂。會出錯的地方是那些同時也是普通英文單字的產品名 —— Swift、Dart、test。';

  @override
  String get hearingDuplexTitle => '讓語音一直開著';

  @override
  String get hearingDuplexNote =>
      '持續聆聽，所以你可以插話。它用你偏好語言裡它支援的第一個，在開始聆聽時就決定，整段對話不換。這條路聽英文比較差：量測是 13.4% 錯字率，按住麥克風鍵是 3.8% —— 講英文時按住鍵比較準。';

  @override
  String get sectionAnswerStyle => '它可以放多開';

  @override
  String get answerStyleNote => '從下一個問題開始生效。模型不會重新載入，只有對話會重建。';

  @override
  String get answerStyleSteady => '謹慎';

  @override
  String get answerStyleBalanced => '平衡';

  @override
  String get answerStyleInventive => '發散';

  @override
  String get answerStyleSteadyNote => '同一個問題傾向給同一個答案。';

  @override
  String get answerStyleBalancedNote => 'Lulo 原本就是這個。';

  @override
  String get answerStyleInventiveNote => '更自由，也更不穩定。適合起草，不適合查事實。';

  @override
  String get exportConversation => '存成 Markdown';

  @override
  String get exportFailed => '這則對話沒有存成功。';

  @override
  String get searchConversations => '搜尋對話';

  @override
  String get noMatches => '沒有符合的對話。';

  @override
  String get pinConversation => '釘在最上面';

  @override
  String get unpinConversation => '取消釘選';

  @override
  String get renameConversation => '重新命名';

  @override
  String get conversationActions => '更多';

  @override
  String get menuShow => '顯示 Lulo';

  @override
  String get menuHide => '隱藏 Lulo';

  @override
  String get menuTalk => '跟 Lulo 說話';

  @override
  String get menuRecent => '最近';

  @override
  String get menuQuit => '結束 Lulo';

  @override
  String get activityIdle => '待命中';

  @override
  String get activityListening => '聆聽中…';

  @override
  String get activityThinking => '思考中…';

  @override
  String get activitySpeaking => '說話中…';

  @override
  String get activityWorking => '工作中…';

  @override
  String get activityError => '需要處理';

  @override
  String get answering => '回覆中';

  @override
  String get thinkingPlaceholder => '思考中…';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');
}
