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
    required this.icon,
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

  final String icon;

  Map<String, dynamic> toJson() => {
        'id': commitmentId,
        'label': label,
        'glyph': glyph,
        'detail': detail,
        'icon': icon,
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
  });

  factory WidgetPayload.fromView(TodayView view, String dateLabel) {
    final rows = [
      for (final item in view.items)
        WidgetRow(
          commitmentId: item.commitment.id,
          label: item.commitment.name,
          glyph: glyphFor(item.status),
          detail: item.isCountable ? '${item.completed}/${item.target}' : '',
          icon: item.commitment.icon ?? '',
        ),
    ];

    return WidgetPayload(
      dateLabel: dateLabel,
      // An empty day shows a dash, not "0%" — nothing expected is not failure.
      progressLabel: view.total == 0 ? '—' : '${view.completed}/${view.total}',
      rows: rows,
      isEmpty: view.isEmpty,
    );
  }

  final String dateLabel;
  final String progressLabel;
  final List<WidgetRow> rows;
  final bool isEmpty;

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
        'rows': [for (final r in rows) r.toJson()],
      });
}
