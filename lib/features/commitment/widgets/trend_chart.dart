import 'package:flutter/material.dart';
import 'package:riyaz/domain/analytics/analytics_engine.dart';

/// Rolling-consistency line.
///
/// Hand-drawn rather than a charting dependency: this is one polyline with a
/// gap rule, and a chart library would be several hundred kilobytes to draw it.
///
/// Null points are **gaps, not zeroes**. A window with nothing eligible means
/// there was nothing to judge; dropping the line to the floor there would
/// invent a collapse that never happened.
class TrendChart extends StatelessWidget {
  const TrendChart({required this.points, this.height = 120, super.key});

  final List<TrendPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final known = points.where((p) => p.consistency != null).length;

    if (known < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history for a trend yet.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Semantics(
      label:
          'Rolling seven day consistency over the last ${points.length} days',
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _TrendPainter(
            points: points,
            line: scheme.primary,
            grid: scheme.outlineVariant,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.points,
    required this.line,
    required this.grid,
  });

  final List<TrendPoint> points;
  final Color line;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    for (final fraction in [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - fraction);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
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
      if (drawing) {
        path.lineTo(offset.dx, offset.dy);
      } else {
        path.moveTo(offset.dx, offset.dy);
        drawing = true;
      }
    }
    if (drawing) canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.points != points;
}
