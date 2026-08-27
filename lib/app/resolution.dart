import 'package:riyaz/data/repository/tracking_repository.dart';
import 'package:riyaz/domain/accounting/accounting_engine.dart';
import 'package:riyaz/domain/accounting/resolved_occurrence.dart';
import 'package:riyaz/domain/model/commitment.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/domain/time/clock.dart';

/// Every commitment's occurrences over a date range, already resolved.
///
/// The shared input to history, analytics and insights. Computing it once and
/// passing it around keeps those three screens from disagreeing about the same
/// week, which is the failure mode the centralised-formula rule exists to stop.
class ResolvedHistory {
  const ResolvedHistory({
    required this.range,
    required this.commitments,
    required this.byCommitment,
  });

  static const ResolvedHistory empty = ResolvedHistory(
    range: CivilDateRange(CivilDate(1970, 1, 1), CivilDate(1970, 1, 1)),
    commitments: [],
    byCommitment: {},
  );

  final CivilDateRange range;
  final List<Commitment> commitments;
  final Map<String, List<ResolvedOccurrence>> byCommitment;

  List<ResolvedOccurrence> get all =>
      [for (final list in byCommitment.values) ...list];

  List<ResolvedOccurrence> forCommitment(String id) =>
      byCommitment[id] ?? const [];

  Commitment? commitment(String id) {
    for (final c in commitments) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Occurrences whose span ends on [date] — what that calendar cell judges.
  List<ResolvedOccurrence> endingOn(CivilDate date) =>
      [for (final r in all) if (r.occurrence.span.end == date) r];

  bool get isEmpty => commitments.isEmpty;
}

/// Composes storage with the engines. Lives outside the domain because it
/// needs a repository; the domain stays argument-driven and pure.
class ResolutionService {
  const ResolutionService({
    required this.repository,
    required this.accounting,
    required this.clock,
  });

  final TrackingRepository repository;
  final AccountingEngine accounting;
  final Clock clock;

  Stream<ResolvedHistory> watch(
    CivilDateRange range, {
    bool includeArchived = true,
  }) =>
      repository.watch(range).map(
            (snapshot) => _resolve(snapshot, range, includeArchived),
          );

  Future<ResolvedHistory> read(
    CivilDateRange range, {
    bool includeArchived = true,
  }) async =>
      _resolve(await repository.read(range), range, includeArchived);

  ResolvedHistory _resolve(
    TrackingSnapshot snapshot,
    CivilDateRange range,
    bool includeArchived,
  ) {
    final byCommitment = <String, List<ResolvedOccurrence>>{};
    final commitments = <Commitment>[];

    for (final commitment in snapshot.commitments) {
      if (!includeArchived && commitment.state == CommitmentState.archived) {
        continue;
      }
      commitments.add(commitment);

      // A commitment cannot be expected before it existed. Without this, a
      // year view would score every day since the epoch as missed.
      final from = range.start > commitment.startedOn
          ? range.start
          : commitment.startedOn;
      if (from > range.end) {
        byCommitment[commitment.id] = const [];
        continue;
      }

      byCommitment[commitment.id] = accounting.resolveRange(
        commitmentId: commitment.id,
        schedules: snapshot.schedulesFor(commitment.id),
        pauses: snapshot.pausesFor(commitment.id),
        events: snapshot.events,
        range: CivilDateRange(from, range.end),
        clock: clock,
      );
    }

    return ResolvedHistory(
      range: range,
      commitments: commitments,
      byCommitment: byCommitment,
    );
  }
}
