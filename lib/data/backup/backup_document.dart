import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/model/pause_period.dart';
import 'package:riyaz/domain/model/schedule.dart';
import 'package:riyaz/domain/model/tracking_event.dart';

/// A complete, self-describing snapshot of everything canonical.
///
/// Rollups are deliberately absent: they are derived, they rebuild themselves,
/// and including them would let a backup carry a stale contradiction of its own
/// source data.
class BackupDocument {
  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.timezoneName,
    required this.dayBoundaryHour,
    required this.weekStartsOn,
    required this.commitments,
    required this.schedules,
    required this.pauses,
    required this.events,
  });

  /// Bumped only when the on-disk shape changes incompatibly. Readers refuse
  /// anything newer than they understand rather than guessing.
  static const int currentVersion = 1;

  static const String formatTag = 'riyaz.backup';

  final int version;
  final DateTime exportedAt;

  /// Interpretation settings travel with the data. Without the timezone and
  /// day boundary, every stored civil date is ambiguous — a backup that omits
  /// them cannot be restored faithfully onto a differently configured device.
  final String timezoneName;
  final int dayBoundaryHour;
  final int weekStartsOn;

  final List<Commitment> commitments;
  final List<CommitmentSchedule> schedules;
  final List<PausePeriod> pauses;
  final List<TrackingEvent> events;

  int get recordCount =>
      commitments.length + schedules.length + pauses.length + events.length;
}

/// What a file contains, shown before anything is written.
class BackupPreview {
  const BackupPreview({
    required this.document,
    required this.warnings,
  });

  final BackupDocument document;

  /// Non-fatal observations — orphans that will be dropped, and so on. A file
  /// with warnings is still importable; the user just gets to see them first.
  final List<String> warnings;
}

/// A file that cannot be trusted. Import never proceeds past one of these.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
