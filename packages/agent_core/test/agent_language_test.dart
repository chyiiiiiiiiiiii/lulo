import 'package:agent_core/agent_core.dart';
import 'package:test/test.dart';

void main() {
  group('AgentLanguage', () {
    test('names the locale a monolingual recogniser has to be set to', () {
      // The recogniser is chosen once, at begin(), and cannot be asked what
      // language it is hearing — so something has to say. This is that
      // something, and the tag is what the platform wants.
      expect(AgentLanguage.english.localeTag, 'en-US');
      expect(AgentLanguage.chinese.localeTag, 'zh-TW');
    });

    test('reads a stored locale back, however it was written', () {
      // Profiles on disk say zh-TW, zh-Hant-TW, or en-GB depending on when
      // and by what they were written. The language is the first subtag.
      expect(AgentLanguage.ofLocale('zh-TW'), AgentLanguage.chinese);
      expect(AgentLanguage.ofLocale('zh-Hant-TW'), AgentLanguage.chinese);
      expect(AgentLanguage.ofLocale('zh'), AgentLanguage.chinese);
      expect(AgentLanguage.ofLocale('en-US'), AgentLanguage.english);
      expect(AgentLanguage.ofLocale('en_GB'), AgentLanguage.english);
    });

    test('an unreadable locale is English rather than a failure', () {
      // A locale nobody recognises must not leave the app with no language
      // at all: the recogniser would be opened on whatever the system said,
      // which is the behaviour this setting exists to take back.
      expect(AgentLanguage.ofLocale(''), AgentLanguage.english);
      expect(AgentLanguage.ofLocale('  '), AgentLanguage.english);
      expect(AgentLanguage.ofLocale('klingon'), AgentLanguage.english);
    });

    test('the default is English', () {
      // The Chinese voice is measured and imperfect — one word in eight
      // needed a respelling before it could be said aloud — and the English
      // one round-trips through a recogniser word-perfect. The default is
      // the one that works today; the other is a switch away.
      expect(AgentLanguage.byDefault, AgentLanguage.english);
    });
  });
}
