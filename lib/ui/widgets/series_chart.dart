import 'dart:ui' as ui;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/format.dart';
import '../../data/measures.dart';
import '../../theme/app_theme.dart';

final _shortDate = DateFormat('MMM d', 'en_US');

/// One reading on a [SeriesChart].
@immutable
class SeriesPoint {
  const SeriesPoint({
    required this.date,
    required this.time,
    required this.value,
  });

  /// `YYYY-MM-DD` / `HH:mm`.
  final String date;
  final String time;

  /// In display units.
  final double value;
}

/// Readings over the days [first]..[last] as dots, joined when [line] is
/// set. The y-axis fits the data rather than starting at zero. Tap a dot to
/// read it.
class SeriesChart extends StatefulWidget {
  const SeriesChart({
    super.key,
    required this.points,
    required this.first,
    required this.last,
    required this.color,
    required this.format,
    required this.unit,
    this.line = false,
    this.height = 150,
  });

  final List<SeriesPoint> points;

  /// Day keys at the left and right edges, inclusive.
  final String first;
  final String last;
  final Color color;

  /// A value in display units, for labels.
  final String Function(double v) format;
  final String unit;
  final bool line;
  final double height;

  @override
  State<SeriesChart> createState() => _SeriesChartState();
}

abstract final class _Layout {
  static const left = 34.0;
  static const right = 8.0;
  static const top = 18.0;
  static const bottom = 20.0;
}

class _SeriesChartState extends State<SeriesChart> {
  int? _inspect;

  /// Days from [SeriesChart.first], with the time of day as a fraction.
  double _dayX(SeriesPoint p) {
    final (h, m) = parseTime(p.time);
    return daysAgo(widget.first, parseKey(p.date)) + (h * 60 + m) / 1440;
  }

  double get _span =>
      (daysAgo(widget.first, parseKey(widget.last)) + 1).toDouble();

  void _tap(Offset at, double width) {
    final plotW = width - _Layout.left - _Layout.right;
    int? best;
    var bestD = 24.0;
    for (final (i, p) in widget.points.indexed) {
      final px = _Layout.left + _dayX(p) / _span * plotW;
      final d = (px - at.dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setState(() => _inspect = best == _inspect ? null : best);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget;
    final values = [for (final p in w.points) p.value];
    final (lo, hi, step) = values.isEmpty
        ? (0.0, 1.0, 1.0)
        : niceRange(
            values.reduce((a, b) => a < b ? a : b),
            values.reduce((a, b) => a > b ? a : b),
          );
    final xs = [for (final p in w.points) _dayX(p) / _span];
    return LayoutBuilder(
      builder: (context, box) => Semantics(
        label:
            '${w.points.length} readings from '
            '${_shortDate.format(parseKey(w.first))} to '
            '${_shortDate.format(parseKey(w.last))}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _tap(d.localPosition, box.maxWidth),
          child: CustomPaint(
            size: Size(box.maxWidth, w.height),
            painter: _SeriesPainter(
              xs: xs,
              values: values,
              lo: lo,
              hi: hi,
              step: step,
              line: w.line,
              color: w.color,
              ink: c.ink,
              surface: c.surface,
              format: w.format,
              firstLabel: _shortDate.format(parseKey(w.first)),
              lastLabel: _shortDate.format(parseKey(w.last)),
              inspect: _inspect == null || _inspect! >= w.points.length
                  ? null
                  : (
                      _inspect!,
                      '${w.format(w.points[_inspect!].value)} ${w.unit} · '
                          '${_shortDate.format(parseKey(w.points[_inspect!].date))} '
                          '${fmtTime(w.points[_inspect!].time)}',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesPainter extends CustomPainter {
  _SeriesPainter({
    required this.xs,
    required this.values,
    required this.lo,
    required this.hi,
    required this.step,
    required this.line,
    required this.color,
    required this.ink,
    required this.surface,
    required this.format,
    required this.firstLabel,
    required this.lastLabel,
    required this.inspect,
  });

  /// 0..1 across the plot.
  final List<double> xs;
  final List<double> values;
  final double lo, hi, step;
  final bool line;
  final Color color, ink, surface;
  final String Function(double) format;
  final String firstLabel, lastLabel;
  final (int, String)? inspect;

  @override
  void paint(Canvas canvas, Size size) {
    final plotW = size.width - _Layout.left - _Layout.right;
    final plotH = size.height - _Layout.top - _Layout.bottom;
    double x(double f) => _Layout.left + f * plotW;
    double y(double v) => _Layout.top + (1 - (v - lo) / (hi - lo)) * plotH;

    void text(
      String s,
      Offset at, {
      double align = .5,
      Color? color,
      FontWeight weight = FontWeight.w400,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: sans(
            10.5,
            weight: weight,
            color: color ?? ink.withValues(alpha: .4),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width * align, tp.height / 2));
    }

    final grid = Paint()
      ..color = ink.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var v = lo; v <= hi + step / 1000; v += step) {
      canvas.drawLine(
        Offset(_Layout.left, y(v)),
        Offset(size.width - _Layout.right, y(v)),
        grid,
      );
      text(format(v), Offset(0, y(v)), align: 0);
    }
    final labelY = size.height - _Layout.bottom / 2 + 2;
    text(firstLabel, Offset(_Layout.left, labelY), align: 0);
    text(lastLabel, Offset(size.width - _Layout.right, labelY), align: 1);

    if (line && xs.length > 1) {
      final path = Path()..moveTo(x(xs.first), y(values.first));
      for (var i = 1; i < xs.length; i++) {
        path.lineTo(x(xs[i]), y(values[i]));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final dot = Paint()..color = color;
    final ring = Paint()..color = surface;
    for (var i = 0; i < xs.length; i++) {
      final at = Offset(x(xs[i]), y(values[i]));
      final picked = inspect?.$1 == i;
      if (line || picked) canvas.drawCircle(at, picked ? 5.5 : 4, ring);
      canvas.drawCircle(at, picked ? 4.2 : (line ? 2.6 : 3.2), dot);
    }

    if (inspect case (final i, final label)) {
      final gx = x(xs[i]);
      canvas.drawLine(
        Offset(gx, _Layout.top),
        Offset(gx, size.height - _Layout.bottom),
        Paint()
          ..color = ink.withValues(alpha: .2)
          ..strokeWidth = 1,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: sans(11, weight: FontWeight.w600, color: ink),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      final lx = (gx - tp.width / 2).clamp(
        _Layout.left,
        size.width - _Layout.right - tp.width,
      );
      tp.paint(canvas, Offset(lx, _Layout.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(_SeriesPainter old) =>
      old.xs != xs ||
      old.values != values ||
      old.inspect != inspect ||
      old.color != color ||
      old.ink != ink;
}

/// A short run of daily totals as bars, with an optional dashed [goal]
/// line. The last bar is the day being looked at.
class DailyBars extends StatelessWidget {
  const DailyBars({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    this.goal,
    this.height = 64,
  });

  final List<double> values;
  final List<String> labels;
  final Color color;
  final double? goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      children: [
        CustomPaint(
          size: Size(double.infinity, height),
          painter: _BarsPainter(
            values: values,
            goal: goal,
            color: color,
            ink: c.ink,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (final (i, l) in labels.indexed)
              Expanded(
                child: Text(
                  l,
                  textAlign: TextAlign.center,
                  style: sans(
                    10.5,
                    weight: i == labels.length - 1
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: c.inkA(i == labels.length - 1 ? .7 : .4),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.values,
    required this.goal,
    required this.color,
    required this.ink,
  });

  final List<double> values;
  final double? goal;
  final Color color, ink;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    var top = goal ?? 0;
    for (final v in values) {
      if (v > top) top = v;
    }
    if (top <= 0) top = 1;
    top *= 1.08;
    final slot = size.width / values.length;
    final barW = slot * .52;
    for (var i = 0; i < values.length; i++) {
      final h = values[i] / top * size.height;
      final cx = slot * (i + .5);
      final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - barW / 2, 0, barW, size.height),
        const Radius.circular(5),
      );
      canvas.drawRRect(track, Paint()..color = ink.withValues(alpha: .05));
      if (h > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(cx - barW / 2, size.height - h, barW, h),
            const Radius.circular(5),
          ),
          Paint()
            ..color = color.withValues(alpha: i == values.length - 1 ? 1 : .55),
        );
      }
    }
    if (goal case final g? when g > 0) {
      final gy = size.height - g / top * size.height;
      final p = Paint()
        ..color = ink.withValues(alpha: .35)
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, gy), Offset(x + 3.5, gy), p);
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.values != values ||
      old.goal != goal ||
      old.color != color ||
      old.ink != ink;
}
