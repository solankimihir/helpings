import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../data/day_curve.dart';
import '../../data/format.dart';
import '../../theme/app_theme.dart';

/// Calories eaten through the day as a running total: [day] in colour over
/// [base] in grey. Tap or drag across it to read both at that time.
///
/// Give it a key that changes with the day and baseline so a reading taken
/// on one doesn't carry over to the next.
class DayCurveChart extends StatefulWidget {
  const DayCurveChart({
    super.key,
    required this.day,
    required this.base,
    required this.start,
    required this.end,
    required this.now,
    required this.baseName,
    required this.basePhrase,
  });

  final DayCurve day;
  final DayCurve? base;

  /// X axis, minutes after midnight.
  final int start;
  final int end;

  /// Minutes after midnight when [day] is today: its line stops here.
  /// Null for a past day.
  final int? now;

  /// "yesterday", "day before", "last Sun", "7-day avg".
  final String baseName;

  /// Follows "By 2:30 PM": "yesterday", "last Sunday", "on average".
  final String basePhrase;

  static const plotHeight = 170.0;

  @override
  State<DayCurveChart> createState() => _DayCurveChartState();
}

class _DayCurveChartState extends State<DayCurveChart> {
  /// Minute being read, or null.
  int? _inspect;

  int _minuteAt(double dx, double width) {
    final f = ((dx - _Layout.left) / (width - _Layout.left - _Layout.right))
        .clamp(0.0, 1.0);
    final m = widget.start + f * (widget.end - widget.start);
    return (m / 5).round() * 5;
  }

  void _tap(double dx, double width) {
    final m = _minuteAt(dx, width);
    final perMinute =
        (width - _Layout.left - _Layout.right) / (widget.end - widget.start);
    setState(() {
      // A second tap near the guide puts it away.
      _inspect = _inspect != null && (m - _inspect!).abs() * perMinute < 16
          ? null
          : m;
    });
  }

  void _drag(double dx, double width) =>
      setState(() => _inspect = _minuteAt(dx, width));

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget;
    final base = w.base;
    final isToday = w.now != null;
    final dayTotal = w.day.total;

    String label() {
      final buf = StringBuffer(
        isToday
            ? 'Calories through today: ${fmtN(dayTotal)} kcal so far'
            : 'Calories through the day: ${fmtN(dayTotal)} kcal',
      );
      if (base != null) {
        buf.write('; ${w.baseName} ${fmtN(base.total)} kcal for the whole day');
      }
      return '$buf.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Pace(
          day: w.day,
          base: base,
          now: w.now,
          at: _inspect,
          baseName: w.baseName,
          basePhrase: w.basePhrase,
        ),
        const SizedBox(height: 10),
        Semantics(
          label: label(),
          excludeSemantics: true,
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition.dx, box.maxWidth),
              onHorizontalDragStart: (d) =>
                  _drag(d.localPosition.dx, box.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _drag(d.localPosition.dx, box.maxWidth),
              child: SizedBox(
                key: const ValueKey('day-curve-plot'),
                height: DayCurveChart.plotHeight,
                width: double.infinity,
                child: CustomPaint(
                  painter: _CurvePainter(
                    day: w.day,
                    base: base,
                    start: w.start,
                    end: w.end,
                    now: w.now,
                    inspect: _inspect,
                    ink: c.ink,
                    primary: c.primary,
                    surface: c.surface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "By 2:30 PM yesterday: 900 kcal · today 1,140 (+240)" and friends.
class _Pace extends StatelessWidget {
  const _Pace({
    required this.day,
    required this.base,
    required this.now,
    required this.at,
    required this.baseName,
    required this.basePhrase,
  });

  final DayCurve day;
  final DayCurve? base;
  final int? now;
  final int? at;
  final String baseName;
  final String basePhrase;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final plain = sans(12.5, color: c.inkA(.62), height: 1.35);
    final bold = sans(
      12.5,
      weight: FontWeight.w600,
      color: c.ink,
      height: 1.35,
    );
    final isToday = now != null;
    final dayWord = isToday ? 'today' : 'this day';

    TextSpan num(double v) => TextSpan(text: fmtN(v), style: bold);
    TextSpan diff(double a, double b) {
      final d = (a - b).round();
      final color = d > 0
          ? c.amberText
          : d < 0
          ? c.greenText
          : c.inkA(.5);
      final text = d > 0
          ? '+${fmtN(d.toDouble())}'
          : d < 0
          ? '−${fmtN(-d.toDouble())}'
          : '±0';
      return TextSpan(
        text: ' ($text)',
        style: sans(12.5, weight: FontWeight.w600, color: color, height: 1.35),
      );
    }

    final List<InlineSpan> spans;
    final b = base;
    if (at != null) {
      final m = at!;
      final future = isToday && m > now!;
      final tv = day.valueAt(m);
      spans = [
        TextSpan(text: 'At ${fmtTime(timeKey(m ~/ 60 % 24, m % 60))}: '),
        TextSpan(text: '$dayWord '),
        future ? TextSpan(text: '—', style: bold) : num(tv),
        if (b != null) ...[
          TextSpan(text: ' · $baseName '),
          num(b.valueAt(m)),
          if (!future) diff(tv, b.valueAt(m)),
        ],
      ];
    } else if (b == null) {
      spans = [
        if (!day.isEmpty) ...[
          num(day.total),
          TextSpan(text: isToday ? ' kcal so far · ' : ' kcal · '),
        ],
        const TextSpan(text: 'Nothing to compare yet'),
      ];
    } else if (isToday) {
      final n = now!;
      final tv = day.valueAt(n), bv = b.valueAt(n);
      spans = [
        TextSpan(text: 'By ${fmtTime(timeKey(n ~/ 60, n % 60))} $basePhrase: '),
        num(bv),
        const TextSpan(text: ' kcal · today '),
        num(tv),
        diff(tv, bv),
      ];
    } else {
      spans = [
        const TextSpan(text: 'Whole day: '),
        num(day.total),
        TextSpan(text: ' kcal · $baseName '),
        num(b.total),
        diff(day.total, b.total),
      ];
    }
    return Text.rich(
      TextSpan(style: plain, children: spans),
      key: const ValueKey('day-curve-pace'),
    );
  }
}

abstract final class _Layout {
  static const left = 34.0;
  static const right = 8.0;
  static const top = 16.0;
  static const bottom = 20.0;
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.day,
    required this.base,
    required this.start,
    required this.end,
    required this.now,
    required this.inspect,
    required this.ink,
    required this.primary,
    required this.surface,
  });

  final DayCurve day;
  final DayCurve? base;
  final int start;
  final int end;
  final int? now;
  final int? inspect;
  final Color ink;
  final Color primary;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final b = base;
    final (top, step) = niceScale(
      math.max(day.total, b == null ? 0.0 : b.valueAt(end)),
    );
    final plotW = size.width - _Layout.left - _Layout.right;
    final plotH = size.height - _Layout.top - _Layout.bottom;
    double x(num m) => _Layout.left + (m - start) / (end - start) * plotW;
    double y(double v) => _Layout.top + (1 - v / top) * plotH;
    final baseY = y(0);

    void text(
      String s,
      Offset at, {
      double size = 10.5,
      Color? color,
      FontWeight weight = FontWeight.w400,
      double align = .5, // 0 left, .5 centre, 1 right
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: sans(
            size,
            weight: weight,
            color: color ?? ink.withValues(alpha: .4),
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width * align, tp.height / 2));
    }

    // Gridlines and Y labels.
    final grid = Paint()
      ..color = ink.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var v = 0.0; v <= top + .5; v += step) {
      canvas.drawLine(
        Offset(_Layout.left, y(v)),
        Offset(size.width - _Layout.right, y(v)),
        grid,
      );
      text(fmtN(v), Offset(0, y(v)), align: 0);
    }

    // X labels, skipped where the inspect label goes.
    final span = (end - start) ~/ 60;
    final every = span <= 9 ? 2 : 3;
    final labelY = size.height - _Layout.bottom / 2 + 2;
    for (var h = (start + 59) ~/ 60; h * 60 <= end; h++) {
      if (h % every != 0) continue;
      final hx = x(h * 60);
      if (inspect != null && (hx - x(inspect!)).abs() < 34) continue;
      final hh = h % 24;
      text(
        '${hh % 12 == 0 ? 12 : hh % 12}${hh >= 12 ? 'p' : 'a'}',
        Offset(hx, labelY),
      );
    }

    Path line(DayCurve c, int until) {
      final p = Path()..moveTo(x(start), y(c.valueAt(start)));
      if (c.stepped) {
        var v = c.valueAt(start);
        for (final pt in c.points) {
          if (pt.minute <= start) continue;
          if (pt.minute > until) break;
          p.lineTo(x(pt.minute), y(v));
          v = pt.cumulative;
          p.lineTo(x(pt.minute), y(v));
        }
        p.lineTo(x(until), y(v));
      } else {
        for (final pt in c.points) {
          if (pt.minute <= start) continue;
          if (pt.minute >= until) break;
          p.lineTo(x(pt.minute), y(pt.cumulative));
        }
        p.lineTo(x(until), y(c.valueAt(until)));
      }
      return p;
    }

    Path area(Path l, int until) => Path.from(l)
      ..lineTo(x(until), baseY)
      ..lineTo(x(start), baseY)
      ..close();

    // Baseline in grey, across the whole range.
    if (b != null) {
      final l = line(b, end);
      canvas.drawPath(
        area(l, end),
        Paint()..color = ink.withValues(alpha: .07),
      );
      canvas.drawPath(
        l,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.75
          ..strokeJoin = StrokeJoin.round
          ..color = ink.withValues(alpha: .42),
      );
      if (b.stepped) {
        final dot = Paint()..color = ink.withValues(alpha: .42);
        for (final pt in b.points) {
          if (pt.minute < start || pt.minute > end) continue;
          canvas.drawCircle(Offset(x(pt.minute), y(pt.cumulative)), 2.4, dot);
        }
      }
    }

    // The day in colour, stopping at now on today.
    final until = now == null ? end : now!.clamp(start, end);
    final l = line(day, until);
    canvas.drawPath(
      area(l, until),
      Paint()..color = primary.withValues(alpha: .14),
    );
    canvas.drawPath(
      l,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = primary,
    );
    for (final pt in day.points) {
      if (pt.minute < start || pt.minute > until) continue;
      final o = Offset(x(pt.minute), y(pt.cumulative));
      canvas.drawCircle(
        o,
        3.8,
        Paint()..color = pt.incomplete ? surface : primary,
      );
      canvas.drawCircle(
        o,
        3.8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = primary,
      );
    }

    // Now marker.
    if (now != null && now! >= start && now! <= end) {
      final nx = x(now!);
      final dash = Paint()
        ..color = ink.withValues(alpha: .35)
        ..strokeWidth = 1;
      for (var yy = _Layout.top - 4; yy < baseY; yy += 6) {
        canvas.drawLine(
          Offset(nx, yy),
          Offset(nx, math.min(yy + 3, baseY)),
          dash,
        );
      }
      text(
        'now',
        Offset(nx, _Layout.top - 10),
        size: 9.5,
        weight: FontWeight.w600,
        color: ink.withValues(alpha: .5),
      );
    }

    // Inspect guide.
    if (inspect != null) {
      final m = inspect!;
      final gx = x(m);
      canvas.drawLine(
        Offset(gx, _Layout.top),
        Offset(gx, baseY),
        Paint()
          ..color = ink.withValues(alpha: .55)
          ..strokeWidth = 1,
      );
      if (b != null) {
        final o = Offset(gx, y(b.valueAt(m)));
        canvas.drawCircle(o, 4, Paint()..color = surface);
        canvas.drawCircle(
          o,
          4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ink.withValues(alpha: .6),
        );
      }
      if (now == null || m <= now!) {
        final o = Offset(gx, y(day.valueAt(m)));
        canvas.drawCircle(o, 4.5, Paint()..color = primary);
        canvas.drawCircle(
          o,
          4.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = surface,
        );
      }
      final lx = gx.clamp(_Layout.left + 24, size.width - _Layout.right - 24);
      text(
        fmtTime(timeKey(m ~/ 60 % 24, m % 60)),
        Offset(lx, labelY),
        weight: FontWeight.w700,
        color: ink,
      );
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.day != day ||
      old.base != base ||
      old.start != start ||
      old.end != end ||
      old.now != now ||
      old.inspect != inspect ||
      old.ink != ink ||
      old.primary != primary ||
      old.surface != surface;
}
