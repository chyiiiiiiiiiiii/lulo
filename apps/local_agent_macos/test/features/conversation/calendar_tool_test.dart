import 'package:flutter_test/flutter_test.dart';
import 'package:local_agent_macos/features/conversation/calendar_tool.dart';

void main() {
  CalendarWindowAnswer answerWith(List<CalendarEventHit> events) =>
      CalendarWindowAnswer(authorized: true, events: events);

  test('declares itself with the date window the model must supply', () {
    final tool = CalendarTool(
      readCalendar: (_, _) async => answerWith(const []),
    );
    expect(tool.name, 'read_calendar');
    expect(tool.parameters.keys, containsAll(<String>['from', 'to']));
  });

  test('answers with the events inside the window', () async {
    (DateTime, DateTime)? asked;
    final tool = CalendarTool(
      readCalendar: (DateTime from, DateTime to) async {
        asked = (from, to);
        return answerWith(<CalendarEventHit>[
          CalendarEventHit(
            title: '牙醫',
            start: DateTime(2026, 8, 22, 14, 30),
            end: DateTime(2026, 8, 22, 15),
            calendar: '個人',
            allDay: false,
          ),
        ]);
      },
    );

    final result =
        await tool.call(<String, Object?>{
              'from': '2026-08-22',
              'to': '2026-08-23',
            })
            as Map<String, Object?>;

    expect(asked, isNotNull);
    final events = result['events']! as List<Object?>;
    final event = events.single! as Map<String, Object?>;
    expect(event['title'], '牙醫');
    expect(event['start'], contains('14:30'));
    expect(event['calendar'], '個人');
  });

  test('denied access is said plainly, never an empty day', () async {
    // An empty list reads as "you are free that day", which is a fabricated
    // schedule when the truth is "I was not allowed to look".
    final tool = CalendarTool(
      readCalendar: (_, _) async =>
          CalendarWindowAnswer(authorized: false, events: const []),
    );
    final result =
        await tool.call(<String, Object?>{
              'from': '2026-08-22',
              'to': '2026-08-23',
            })
            as Map<String, Object?>;
    expect(result['error'], contains('access'));
    expect(result.containsKey('events'), isFalse);
  });

  test('unreadable dates are an error the model can read', () async {
    final tool = CalendarTool(
      readCalendar: (_, _) async => answerWith(const []),
    );
    final result =
        await tool.call(<String, Object?>{'from': '昨天', 'to': '明天'})
            as Map<String, Object?>;
    expect(result['error'], isNotNull);
  });
}
