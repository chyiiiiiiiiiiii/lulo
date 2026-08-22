import 'package:agent_core/agent_core.dart';

/// One event from the user's calendar.
final class CalendarEventHit {
  /// Creates an event.
  const CalendarEventHit({
    required this.title,
    required this.start,
    required this.end,
    required this.calendar,
    required this.allDay,
  });

  /// What the event is called.
  final String title;

  /// When it starts, local time.
  final DateTime start;

  /// When it ends, local time.
  final DateTime end;

  /// Which calendar it lives on.
  final String calendar;

  /// Whether it spans the whole day rather than hours.
  final bool allDay;
}

/// What a calendar read produced, including whether it was allowed to.
final class CalendarWindowAnswer {
  /// Creates the answer.
  const CalendarWindowAnswer({required this.authorized, required this.events});

  /// Whether the user has granted calendar access.
  final bool authorized;

  /// The events in the asked window, empty when none or unauthorized.
  final List<CalendarEventHit> events;
}

/// Lets the agent read the user's calendar for a window of days.
///
/// Read-only on purpose: reading answers 「我明天有什麼行程」, and writing
/// is a side effect that deserves its own consent story before it exists
/// at all. Access is the OS's own EventKit permission — the system asks
/// the user directly, and a denial reaches the model as a denial, never as
/// an empty day: an empty list reads as "you are free", which is a
/// fabricated schedule when the truth is "I was not allowed to look".
final class CalendarTool implements AgentTool {
  /// Creates the tool over whatever reads the calendar.
  CalendarTool({
    required Future<CalendarWindowAnswer> Function(DateTime from, DateTime to)
    readCalendar,
  }) : _read = readCalendar;

  final Future<CalendarWindowAnswer> Function(DateTime, DateTime) _read;

  /// The most events one answer carries.
  static const int maxEvents = 12;

  @override
  String get name => 'read_calendar';

  @override
  String get description =>
      'Reads the user\'s own calendar. Returns their events between two '
      'dates: title, time, and which calendar. Use when the user asks '
      'about their schedule, what they have planned, or whether they are '
      'free.';

  @override
  Map<String, Object?> get parameters => const <String, Object?>{
    'from': <String, Object?>{
      'type': 'string',
      'description': 'First day to read, as YYYY-MM-DD.',
    },
    'to': <String, Object?>{
      'type': 'string',
      'description': 'Day after the last day to read, as YYYY-MM-DD.',
    },
  };

  @override
  Future<Object?> call(Map<String, Object?> arguments) async {
    final DateTime? from = _day(arguments['from']);
    final DateTime? to = _day(arguments['to']);
    if (from == null || to == null) {
      return const <String, Object?>{
        'error': 'from and to are required, as YYYY-MM-DD dates.',
      };
    }
    final CalendarWindowAnswer answer = await _read(from, to);
    if (!answer.authorized) {
      return const <String, Object?>{
        'error':
            'The user has not granted calendar access. Say so; do not '
            'guess their schedule.',
      };
    }
    return <String, Object?>{
      'events': <Object?>[
        for (final CalendarEventHit event in answer.events.take(maxEvents))
          <String, Object?>{
            'title': event.title,
            'start': event.allDay ? _date(event.start) : _minute(event.start),
            'end': event.allDay ? _date(event.end) : _minute(event.end),
            'calendar': event.calendar,
            if (event.allDay) 'allDay': true,
          },
      ],
      'totalEvents': answer.events.length,
    };
  }

  static DateTime? _day(Object? value) {
    if (value is! String) {
      return null;
    }
    return DateTime.tryParse(value.trim());
  }

  static String _date(DateTime moment) =>
      moment.toIso8601String().substring(0, 10);

  static String _minute(DateTime moment) =>
      moment.toIso8601String().substring(0, 16).replaceFirst('T', ' ');
}
