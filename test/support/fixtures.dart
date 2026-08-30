import 'package:riyaz/domain/model/frequency.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';
import 'package:riyaz/domain/time/accounting_calendar.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:timezone/timezone.dart' as tz;

const commitmentId = 'c1';

AccountingCalendar calendarFor(
  String zone, {
  int boundaryHour = 4,
  int weekStartsOn = DateTime.monday,
}) =>
    AccountingCalendar(
      zone: tz.getLocation(zone),
      dayBoundaryHour: boundaryHour,
      weekStartsOn: weekStartsOn,
    );

CommitmentSchedule schedule({
  required Frequency frequency,
  required CivilDate from,
  CivilDate? to,
  String id = 's1',
  int? targetMinutes,
}) =>
    CommitmentSchedule(
      id: id,
      commitmentId: commitmentId,
      effectiveFrom: from,
      effectiveTo: to,
      frequency: frequency,
      targetMinutes: targetMinutes,
    );

PausePeriod pause(CivilDate from, CivilDate to, {String id = 'p1'}) =>
    PausePeriod(id: id, commitmentId: commitmentId, from: from, to: to);

/// A tracking event. [recordedAtUtc] is irrelevant to accounting (the
/// accountingDate is authoritative), so it defaults to a fixed instant.
TrackingEvent event(
  CivilDate date, {
  TrackingKind kind = TrackingKind.done,
  int count = 1,
  int? minutes,
  String id = 'e',
}) =>
    TrackingEvent(
      id: '$id-${date.iso}-${kind.name}-$count',
      commitmentId: commitmentId,
      accountingDate: date,
      recordedAtUtc: DateTime.utc(2026, 1, 1),
      kind: kind,
      count: count,
      minutes: minutes,
    );
