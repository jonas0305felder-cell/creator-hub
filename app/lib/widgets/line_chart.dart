import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_texts.dart';
import 'common.dart';

/// Ein Messpunkt des Liniendiagramms.
class ChartPoint {
  const ChartPoint(this.date, this.value);
  final DateTime date;
  final num value;
}

/// Schlichtes Liniendiagramm mit Achsenbeschriftung.
///
/// Bei weniger als zwei Punkten erscheint ein Hinweis statt einer Linie.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.points, required this.color, this.height = 180, this.semanticLabel});

  final List<ChartPoint> points;
  final Color color;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(T.statsNotEnoughPoints, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _LineChartPainter(
            points: points,
            color: color,
            gridColor: theme.colorScheme.outlineVariant,
            labelStyle: theme.textTheme.labelSmall!.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.points, required this.color, required this.gridColor, required this.labelStyle});

  final List<ChartPoint> points;
  final Color color;
  final Color gridColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 44.0, bottom = 20.0, top = 8.0, right = 8.0;
    final chart = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final values = points.map((p) => p.value.toDouble()).toList();
    var minV = values.reduce(math.min);
    var maxV = values.reduce(math.max);
    // Achse bei 0 beginnen, wenn die Werte nah an 0 liegen; sonst etwas Luft.
    if (minV >= 0 && minV < maxV * 0.6) minV = 0;
    if (maxV == minV) {
      maxV += 1;
      minV = math.max(0, minV - 1);
    }
    final range = maxV - minV;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = chart.bottom - chart.height * i / 2;
      canvas.drawLine(Offset(chart.left, y), Offset(chart.right, y), grid);
      _text(canvas, formatCompact((minV + range * i / 2).round()), Offset(0, y - 7), left - 6, TextAlign.right);
    }

    Offset at(int i) =>
        Offset(chart.left + chart.width * i / (points.length - 1), chart.bottom - chart.height * (values[i] - minV) / range);
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final area = Path.from(path)
      ..lineTo(chart.right, chart.bottom)
      ..lineTo(chart.left, chart.bottom)
      ..close();
    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (points.length <= 31) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(at(i), 2.5, Paint()..color = color);
      }
    }

    // Datum am Anfang und Ende der Achse.
    _text(canvas, formatDayShort(points.first.date), Offset(chart.left, chart.bottom + 4), 80, TextAlign.left);
    _text(canvas, formatDayShort(points.last.date), Offset(chart.right - 80, chart.bottom + 4), 80, TextAlign.right);
  }

  void _text(Canvas canvas, String text, Offset offset, double width, TextAlign align) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: width, maxWidth: width);
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_LineChartPainter old) => old.points != points || old.color != color;
}
