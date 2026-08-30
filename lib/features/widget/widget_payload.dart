import 'dart:convert';

import 'package:riyaz/domain/accounting/occurrence_status.dart';
import 'package:riyaz/features/home/today_view.dart';

/// One row as the home-screen widget will draw it.
class WidgetRow {
  const WidgetRow({
    required this.commitmentId,
    required this.label,
    required this.glyph,
    required this.detail,
  });

  final String commitmentId;
  final String label;

  /// A text glyph rather than a colour or an image.
  ///
  /// The widget is drawn by the Android launcher in a theme this app does not
  /// control, at a size it does not choose. A glyph survives all of that;
  /// a colour-coded dot would be illegible on half the launchers out there,
  /// and would break the same no-colour-alone rule the app follows everywhere.
  final String glyph;

  /// Progress for countable rows: "2/4". Empty for simple ones.
  final String detail;

  /// **No icon field, deliberately.**
  ///
  /// There used to be one, carrying whatever string `Commitment.icon` held,
  /// and it worked for exactly as long as that string was an emoji. Once the
  /// icon vocabulary became glyph *keys* the widget started prepending the key
  /// itself — every row would have read "run Running  ✓". Nothing failed,
  /// because the widget had never once been drawn.
  ///
  /// It is not coming back as a key either. The widget is `RemoteViews`
  /// inflated in the launcher's process, which has no access to the Material
  /// icon font Flutter bundles as an app asset, so there is nothing there that
  /// can turn "run" into a runner. A name and a status glyph is the honest
  /// content for this surface.
  Map<String, dynamic> toJson() => {
        'id': commitmentId,
        'label': label,
        'glyph': glyph,
        'detail': detail,
      };
}

/// The snapshot handed to the native widget.
///
/// Deliberately pre-rendered: every string the widget shows is decided here, in
/// Dart, where the accounting rules live. The native side does no arithmetic
/// and knows nothing about skips, pauses or period targets — if it did, there
/// would be two implementations of the scoring rules and they would drift.
class WidgetPayload {
  const WidgetPayload({
    required this.dateLabel,
    required this.progressLabel,
    required this.rows,
    required this.isEmpty,
    required this.emptyLabel,
  });

  /// **Daily commitments only.** Week and month targets are not on the widget.
  ///
  /// They used to be, both in the list and in the count, and it made the
  /// widget quietly lie. With eighteen commitments it read `12/18` on a day
  /// the app read `6 of 8` — because ten of those eighteen were weekly targets
  /// that were not due today and could not be missed today. A glance said six
  /// things outstanding when two were. That is precisely the misconception the
  /// daily/period split exists to prevent, leaking onto the home screen.
  ///
  /// Filtering rather than reordering, because five text rows cannot express
  /// two categories. The app has a section header, a different row shape and a
  /// "never late" label to keep them apart; the widget has a line of text. Put
  /// both kinds in one flat list and "Gym  2/3" is indistinguishable from a
  /// daily row that wants doing now. The widget answers one question — *what
  /// is left today* — and a weekly target is not an answer to it.
  factory WidgetPayload.fromView(TodayView view, String dateLabel) {
    final daily = view.daily;
    final rows = [
      for (final item in daily)
        WidgetRow(
          commitmentId: item.commitment.id,
          label: item.commitment.name,
          glyph: glyphFor(item.status),
          detail: item.isCountable ? '${item.completed}/${item.target}' : '',
        ),
    ];

    return WidgetPayload(
      dateLabel: dateLabel,
      // The same figure the Today screen's section header shows, so a glance
      // at the home screen and a glance at the app never disagree. A dash when
      // nothing is expected: nothing due is not nothing achieved.
      progressLabel: view.dailyExpected == 0
          ? '—'
          : '${view.dailyDone}/${view.dailyExpected}',
      rows: rows,
      isEmpty: rows.isEmpty,
      // Two different silences, and conflating them would be a small lie in
      // each direction. Someone whose targets are all weekly has plenty
      // tracked and nothing due; someone with no commitments has neither.
      emptyLabel: view.isEmpty
          ? 'Nothing to track yet'
          : 'Nothing due today',
    );
  }

  final String dateLabel;
  final String progressLabel;
  final List<WidgetRow> rows;

  /// No daily rows to draw — which is not the same as no commitments.
  final bool isEmpty;

  /// What to say instead of a list. Decided here, like every other string the
  /// widget shows, because the reason for the silence is an accounting
  /// question and the native side does no accounting.
  final String emptyLabel;

  /// The same glyph vocabulary the in-app indicator uses, so the widget and
  /// the app never disagree about what a state looks like.
  static String glyphFor(OccurrenceStatus status) => switch (status) {
        OccurrenceStatus.done => '✓',
        OccurrenceStatus.partial => '◐',
        OccurrenceStatus.missed => '✗',
        OccurrenceStatus.skipped => '—',
        OccurrenceStatus.paused => '⏸',
        OccurrenceStatus.notScheduled => '·',
        OccurrenceStatus.pending => '○',
      };

  String encode() => jsonEncode({
        'dateLabel': dateLabel,
        'progressLabel': progressLabel,
        'isEmpty': isEmpty,
        'emptyLabel': emptyLabel,
        'rows': [for (final r in rows) r.toJson()],
      });
}
