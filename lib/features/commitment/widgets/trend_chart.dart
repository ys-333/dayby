import 'package:flutter/material.dart';
import 'package:riyaz/app/theme/riyaz_theme.dart';
import 'package:riyaz/app/theme/tokens.dart';
import 'package:riyaz/app/theme/type_roles.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';

/// Rolling-consistency line, with a scale you can read a value off.
///
/// Hand-drawn rather than a charting dependency: this is one polyline with a
/// gap rule, and a chart library would be several hundred kilobytes to draw it.
///
/// Null points are **gaps, not zeroes**. A window with nothing eligible means
/// there was nothing to judge; dropping the line to the floor there would
/// invent a collapse that never happened.
///
/// **The axis is fixed at 0–100%, never fitted to the data.** Fitting is the
/// obvious way to make a flat series look interesting, and it is exactly wrong
/// here: it turns a five-point wobble into a cliff, and a tracker that draws
/// ordinary variation as a collapse is the guilt machine this app is trying not
/// to be. A line that sits near the middle and stays there is telling the
/// truth, and the axis labels are what let the reader see that rather than
/// guess at it.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.points, this.height = 120, super.key});

  final List<TrendPoint> points;
  final double height;

  /// Width of the axis gutter at 1.0x text. Fits "100%" at the app's smallest
  /// type — and **only** at 1.0x, which is why it is scaled rather than used
  /// raw. A fixed 36dp gutter wraps "100%" onto three lines at 1.8x, and three
  /// labels three lines tall overflowed the chart box by 114px.
  static const double _gutter = 36;

  /// Roughly one tick's line box at 1.0x. The chart grows if three of them
  /// stop fitting, so the axis can never be the thing that breaks the layout.
  static const double _tickLine = 18;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final known = [
      for (final p in points)
        if (p.consistency != null) p.consistency!,
    ];

    if (known.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history for a trend yet.',
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      );
    }

    final mean = known.reduce((a, b) => a + b) / known.length;
    final latest = _latest;
    final tick = theme.textTheme.labelSmall?.copyWith(color: muted);

    // `polish_test.dart` renders every screen at 1.8x, and CLAUDE.md's rule
    // about line height applies to a chart's furniture as much as to its type:
    // nothing here may be a fixed pixel box that the user's text size can
    // overrun.
    final scaler = MediaQuery.textScalerOf(context);
    final gutter = scaler.scale(_gutter);
    final chartHeight =
        height > scaler.scale(_tickLine) * 3.2
            ? height
            : scaler.scale(_tickLine) * 3.2;

    return Semantics(
      label: 'Rolling seven day consistency over the last ${points.length} '
          'days. Now ${latest == null ? 'unknown' : '${_pct(latest)} percent'}, '
          'averaging ${_pct(mean)} percent.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutter,
                height: chartHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('100%', style: tick, maxLines: 1),
                    Text('50%', style: tick, maxLines: 1),
                    Text('0%', style: tick, maxLines: 1),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: chartHeight,
                  child: CustomPaint(
                    painter: _TrendPainter(
                      points: points,
                      mean: mean,
                      // Straight from the palette, not from `scheme.primary`
                      // and `scheme.outlineVariant`. Those resolve to the same
                      // colours today — `theme_contract_test.dart` pins that —
                      // but they are UI roles: primary is the colour of a
                      // button, and asking it for a data line means the chart
                      // re-tints itself the day the button does. A plotted
                      // series and the rules under it are graphics, and they
                      // take graphic values.
                      line: context.palette.sage,
                      grid: context.palette.line,
                      meanInk: context.palette.ink3,
                      ground: context.palette.ground,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.titleGap * 3),
          Padding(
            padding: EdgeInsets.only(left: gutter),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text('Last ${points.length} days', style: tick),
                ),
                const SizedBox(width: Insets.rowTrailingGap),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'now · ', style: tick),
                        TextSpan(
                          text: latest == null ? '—' : '${_pct(latest)}%',
                          style: theme.textTheme.footnote?.copyWith(
                            color: context.statusColors.done,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The most recent window that had anything to judge.
  ///
  /// Not simply `points.last`: the final days can legitimately be a gap — a
  /// stretch of skips or a pause — and reporting "now: —" when a real value
  /// sits one day back tells the user less than the truth.
  double? get _latest {
    for (var i = points.length - 1; i >= 0; i--) {
      final value = points[i].consistency;
      if (value != null) return value;
    }
    return null;
  }

  static int _pct(double value) => (value * 100).round();
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.mean,
    required this.line,
    required this.grid,
    required this.meanInk,
    required this.ground,
  });

  final List<TrendPoint> points;
  final double mean;
  final Color line;
  final Color grid;
  final Color meanInk;

  /// Painted behind the end dot so it reads as a marker on the line rather
  /// than a bulge in it.
  final Color ground;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - fraction);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // The mean, dashed so it cannot be mistaken for the series itself.
    final meanY = size.height * (1 - mean);
    final meanPaint = Paint()
      ..color = meanInk
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawLine(
        Offset(x, meanY),
        Offset((x + 4).clamp(0, size.width), meanY),
        meanPaint,
      );
    }

    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final dx = points.length > 1 ? size.width / (points.length - 1) : 0.0;
    var path = Path();
    var drawing = false;
    Offset? last;

    for (var i = 0; i < points.length; i++) {
      final value = points[i].consistency;
      if (value == null) {
        // Break the stroke rather than bridging across missing data.
        if (drawing) {
          canvas.drawPath(path, linePaint);
          path = Path();
          drawing = false;
        }
        continue;
      }
      final offset = Offset(dx * i, size.height * (1 - value));
      last = offset;
      if (drawing) {
        path.lineTo(offset.dx, offset.dy);
      } else {
        path.moveTo(offset.dx, offset.dy);
        drawing = true;
      }
    }
    if (drawing) canvas.drawPath(path, linePaint);

    // Where the line has got to. Without it the eye has to hunt for the right
    // edge, and on a series that ends in a gap the right edge is not the
    // answer anyway.
    if (last != null) {
      canvas.drawCircle(last, 5, Paint()..color = ground);
      canvas.drawCircle(last, 3.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.mean != mean;
}
