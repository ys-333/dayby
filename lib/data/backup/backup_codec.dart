import 'dart:convert';

import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/commitment_icon.dart';
import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/civil_date.dart';

import 'backup_document.dart';

/// Reads and writes the backup format.
///
/// Hand-written rather than generated. A backup format is a long-lived contract
/// with the user's own history: it has to stay readable by future versions, and
/// codegen would tie its shape to whatever the model classes happen to look
/// like today. Explicit encoding also lets dates stay human-readable, so a
/// corrupted file can be inspected and repaired by hand.
class BackupCodec {
  const BackupCodec();

  // ------------------------------------------------------------------ encode

  String encode(BackupDocument doc, {bool pretty = true}) {
    final map = <String, dynamic>{
      'format': BackupDocument.formatTag,
      'version': doc.version,
      'exportedAt': doc.exportedAt.toUtc().toIso8601String(),
      'settings': {
        'timezone': doc.timezoneName,
        'dayBoundaryHour': doc.dayBoundaryHour,
        'weekStartsOn': doc.weekStartsOn,
      },
      'commitments': [for (final c in doc.commitments) _commitment(c)],
      'schedules': [for (final s in doc.schedules) _schedule(s)],
      'pauses': [for (final p in doc.pauses) _pause(p)],
      'events': [for (final e in doc.events) _event(e)],
    };
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(map)
        : jsonEncode(map);
  }

  Map<String, dynamic> _commitment(Commitment c) => {
        'id': c.id,
        'name': c.name,
        'startedOn': c.startedOn.iso,
        if (c.description != null) 'description': c.description,
        if (c.icon != null) 'icon': c.icon,
        if (c.categoryId != null) 'categoryId': c.categoryId,
        'state': c.state.name,
        if (c.archivedOn != null) 'archivedOn': c.archivedOn!.iso,
      };

  Map<String, dynamic> _schedule(CommitmentSchedule s) => {
        'id': s.id,
        'commitmentId': s.commitmentId,
        'effectiveFrom': s.effectiveFrom.iso,
        if (s.effectiveTo != null) 'effectiveTo': s.effectiveTo!.iso,
        'frequency': _frequency(s.frequency),
        if (s.targetMinutes != null) 'targetMinutes': s.targetMinutes,
      };

  Map<String, dynamic> _frequency(Frequency f) => switch (f) {
        DailyFrequency(:final target) => {'type': 'daily', 'target': target},
        WeekdaysFrequency(:final days, :final target) => {
            'type': 'weekdays',
            'days': (days.toList()..sort()),
            'target': target,
          },
        EveryNDaysFrequency(:final n, :final target) => {
            'type': 'everyNDays',
            'n': n,
            'target': target,
          },
        TimesPerWeekFrequency(:final target) => {
            'type': 'timesPerWeek',
            'target': target,
          },
        TimesPerMonthFrequency(:final target) => {
            'type': 'timesPerMonth',
            'target': target,
          },
      };

  /// The `to` key is always written, `null` and all.
  ///
  /// Omitting it for an open pause would make "still paused" and "field lost
  /// in a truncated write" the same bytes. The file is meant to be repairable
  /// by hand, so an explicit null is worth the four characters.
  Map<String, dynamic> _pause(PausePeriod p) => {
        'id': p.id,
        'commitmentId': p.commitmentId,
        'from': p.from.iso,
        'to': p.to?.iso,
      };

  Map<String, dynamic> _event(TrackingEvent e) => {
        'id': e.id,
        'commitmentId': e.commitmentId,
        'accountingDate': e.accountingDate.iso,
        'recordedAtUtc': e.recordedAtUtc.toUtc().toIso8601String(),
        'kind': e.kind.name,
        'count': e.count,
        if (e.minutes != null) 'minutes': e.minutes,
        if (e.note != null) 'note': e.note,
      };

  // ------------------------------------------------------------------ decode

  /// Parses and structurally validates. Throws [BackupFormatException] on
  /// anything it cannot vouch for — a half-understood backup is worse than a
  /// refused one, because it silently loses history.
  BackupDocument decode(String json) {
    final dynamic raw;
    try {
      raw = jsonDecode(json);
    } on FormatException catch (e) {
      throw BackupFormatException('Not valid JSON: ${e.message}');
    }
    if (raw is! Map<String, dynamic>) {
      throw const BackupFormatException(
        'Expected a JSON object at the top level.',
      );
    }

    if (raw['format'] != BackupDocument.formatTag) {
      throw const BackupFormatException(
        'This does not look like a Riyaz backup.',
      );
    }

    final version = raw['version'];
    if (version is! int) {
      throw const BackupFormatException('Missing or invalid version.');
    }
    if (version > BackupDocument.currentVersion) {
      throw BackupFormatException(
        'This backup was written by a newer version of Riyaz '
        '(format $version, this build reads up to '
        '${BackupDocument.currentVersion}). Update the app and try again.',
      );
    }

    final settings = raw['settings'];
    if (settings is! Map<String, dynamic>) {
      throw const BackupFormatException('Missing settings block.');
    }

    return BackupDocument(
      version: version,
      exportedAt: _instant(raw['exportedAt'], 'exportedAt'),
      timezoneName: _string(settings['timezone'], 'settings.timezone'),
      dayBoundaryHour: _int(settings['dayBoundaryHour'], 'dayBoundaryHour'),
      weekStartsOn: _int(settings['weekStartsOn'], 'weekStartsOn'),
      commitments: _list(raw['commitments'], 'commitments', _readCommitment),
      schedules: _list(raw['schedules'], 'schedules', _readSchedule),
      pauses: _list(raw['pauses'], 'pauses', _readPause),
      events: _list(raw['events'], 'events', _readEvent),
    );
  }

  List<T> _list<T>(
    dynamic value,
    String field,
    T Function(Map<String, dynamic>) read,
  ) {
    if (value == null) return const [];
    if (value is! List) {
      throw BackupFormatException('$field must be a list.');
    }
    return [
      for (final entry in value)
        if (entry is Map<String, dynamic>)
          read(entry)
        else
          throw BackupFormatException('$field contains a non-object entry.'),
    ];
  }

  /// Icons arriving as legacy emoji are normalised to glyph keys on the way
  /// in, so a restore converges on the same vocabulary the schema v4 migration
  /// produced. Anything the table does not recognise is kept verbatim — the
  /// mark is the user's, and `CommitmentIcon` can still draw it.
  ///
  /// No format-version bump for this. An icon is a display value: an older
  /// build meeting an unknown key draws the raw string and carries on, which
  /// is a cosmetic surprise rather than a misread record. That is the line the
  /// version number is for, and a nullable `pause.to` crossed it where this
  /// does not.
  Commitment _readCommitment(Map<String, dynamic> m) => Commitment(
        id: _string(m['id'], 'commitment.id'),
        name: _string(m['name'], 'commitment.name'),
        startedOn: _date(m['startedOn'], 'commitment.startedOn'),
        description: m['description'] as String?,
        icon: iconKeyFor(m['icon'] as String?) ?? m['icon'] as String?,
        categoryId: m['categoryId'] as String?,
        state: _enum(m['state'], CommitmentState.values, 'commitment.state'),
        archivedOn: m['archivedOn'] == null
            ? null
            : _date(m['archivedOn'], 'commitment.archivedOn'),
      );

  CommitmentSchedule _readSchedule(Map<String, dynamic> m) => CommitmentSchedule(
        id: _string(m['id'], 'schedule.id'),
        commitmentId: _string(m['commitmentId'], 'schedule.commitmentId'),
        effectiveFrom: _date(m['effectiveFrom'], 'schedule.effectiveFrom'),
        effectiveTo: m['effectiveTo'] == null
            ? null
            : _date(m['effectiveTo'], 'schedule.effectiveTo'),
        frequency: _readFrequency(m['frequency']),
        targetMinutes: m['targetMinutes'] as int?,
      );

  Frequency _readFrequency(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const BackupFormatException('schedule.frequency must be an object.');
    }
    final target = value['target'] as int? ?? 1;
    return switch (value['type']) {
      'daily' => Frequency.daily(target: target),
      'weekdays' => Frequency.weekdays(
          days: {
            for (final d in (value['days'] as List? ?? const []))
              if (d is int && d >= 1 && d <= 7)
                d
              else
                throw const BackupFormatException(
                  'frequency.days must contain weekday numbers 1-7.',
                ),
          },
          target: target,
        ),
      'everyNDays' => Frequency.everyNDays(
          n: _int(value['n'], 'frequency.n'),
          target: target,
        ),
      'timesPerWeek' => Frequency.timesPerWeek(target: target),
      'timesPerMonth' => Frequency.timesPerMonth(target: target),
      _ => throw BackupFormatException(
          'Unknown frequency type "${value['type']}".',
        ),
    };
  }

  /// A missing or null `to` is an open pause.
  ///
  /// Both spellings are accepted on read even though only one is written: a
  /// v1 file always carried a date, and a hand-repaired file may well have had
  /// the key deleted rather than set to null.
  PausePeriod _readPause(Map<String, dynamic> m) => PausePeriod(
        id: _string(m['id'], 'pause.id'),
        commitmentId: _string(m['commitmentId'], 'pause.commitmentId'),
        from: _date(m['from'], 'pause.from'),
        to: m['to'] == null ? null : _date(m['to'], 'pause.to'),
      );

  TrackingEvent _readEvent(Map<String, dynamic> m) => TrackingEvent(
        id: _string(m['id'], 'event.id'),
        commitmentId: _string(m['commitmentId'], 'event.commitmentId'),
        accountingDate: _date(m['accountingDate'], 'event.accountingDate'),
        recordedAtUtc: _instant(m['recordedAtUtc'], 'event.recordedAtUtc'),
        kind: _enum(m['kind'], TrackingKind.values, 'event.kind'),
        count: m['count'] as int? ?? 1,
        minutes: m['minutes'] as int?,
        note: m['note'] as String?,
      );

  // ------------------------------------------------------------------ helpers

  String _string(dynamic v, String field) => v is String && v.isNotEmpty
      ? v
      : throw BackupFormatException('$field must be a non-empty string.');

  int _int(dynamic v, String field) =>
      v is int ? v : throw BackupFormatException('$field must be an integer.');

  CivilDate _date(dynamic v, String field) {
    if (v is! String) {
      throw BackupFormatException('$field must be a yyyy-MM-dd string.');
    }
    try {
      return CivilDate.parse(v);
    } on FormatException {
      throw BackupFormatException('$field is not a valid date: "$v".');
    }
  }

  DateTime _instant(dynamic v, String field) {
    if (v is! String) {
      throw BackupFormatException('$field must be an ISO-8601 timestamp.');
    }
    try {
      return DateTime.parse(v).toUtc();
    } on FormatException {
      throw BackupFormatException('$field is not a valid timestamp: "$v".');
    }
  }

  T _enum<T extends Enum>(dynamic v, List<T> values, String field) {
    for (final value in values) {
      if (value.name == v) return value;
    }
    throw BackupFormatException('$field has unknown value "$v".');
  }
}
