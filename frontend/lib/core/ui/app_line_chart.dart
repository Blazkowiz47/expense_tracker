import 'dart:math' as math;

import 'package:flutter/material.dart';

class AppChartPoint {
  const AppChartPoint({required this.label, required this.value});

  final String label;
  final double value;
}

class AppLineChart extends StatelessWidget {
  const AppLineChart({
    required this.points,
    this.color,
    this.gridColor,
    this.labelColor,
    this.height = 142,
    this.padding = 8,
    this.bottomLabelHeight = 22,
    this.fillOpacity = 0.22,
    super.key,
  });

  final List<AppChartPoint> points;
  final Color? color;
  final Color? gridColor;
  final Color? labelColor;
  final double height;
  final double padding;
  final double bottomLabelHeight;
  final double fillOpacity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _AppLineChartPainter(
          points: points,
          color: color ?? colors.primary,
          gridColor: gridColor ?? colors.outlineVariant,
          labelColor: labelColor ?? colors.onSurfaceVariant,
          padding: padding,
          bottomLabelHeight: bottomLabelHeight,
          fillOpacity: fillOpacity,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _AppLineChartPainter extends CustomPainter {
  const _AppLineChartPainter({
    required this.points,
    required this.color,
    required this.gridColor,
    required this.labelColor,
    required this.padding,
    required this.bottomLabelHeight,
    required this.fillOpacity,
  });

  final List<AppChartPoint> points;
  final Color color;
  final Color gridColor;
  final Color labelColor;
  final double padding;
  final double bottomLabelHeight;
  final double fillOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final chartHeight = math.max(0.0, size.height - bottomLabelHeight);
    final maxValue = math.max(
      1,
      points
              .map((point) => math.max(0.0, point.value))
              .fold<double>(0, math.max) *
          1.15,
    );
    final stepX = points.length == 1
        ? 0.0
        : (size.width - padding * 2) / (points.length - 1);
    final offsets = points
        .asMap()
        .entries
        .map((entry) {
          final x = padding + stepX * entry.key;
          final value = math.max(0.0, entry.value.value);
          final y =
              chartHeight -
              padding -
              (value / maxValue) * (chartHeight - padding * 2);
          return Offset(x, y);
        })
        .toList(growable: false);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final fraction in const [0.25, 0.5, 0.75]) {
      final y = padding + (chartHeight - padding * 2) * fraction;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
    }

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final offset in offsets.skip(1)) {
      path.lineTo(offset.dx, offset.dy);
    }

    final fillPath = Path.from(path)
      ..lineTo(offsets.last.dx, chartHeight - padding)
      ..lineTo(offsets.first.dx, chartHeight - padding)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: fillOpacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, chartHeight));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final peakValue = points
        .map((point) => math.max(0.0, point.value))
        .fold<double>(0, math.max);
    for (var index = 0; index < offsets.length; index += 1) {
      final point = points[index];
      final offset = offsets[index];
      final isPeak = point.value == peakValue && peakValue > 0;
      final radius = isPeak ? 4.0 : 2.5;

      canvas.drawCircle(
        offset,
        radius,
        Paint()
          ..color = isPeak ? color : Colors.white
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        offset,
        radius,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: point.label,
          style: TextStyle(color: labelColor, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(offset.dx - textPainter.width / 2, chartHeight + 8),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AppLineChartPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor ||
        oldDelegate.padding != padding ||
        oldDelegate.bottomLabelHeight != bottomLabelHeight ||
        oldDelegate.fillOpacity != fillOpacity;
  }
}
