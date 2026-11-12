import 'package:material_ui/material_ui.dart';

enum TabGlyph { home, history, items, settings }

/// Line icons drawn from the design's 20×20 SVGs.
class TabIcon extends StatelessWidget {
  const TabIcon(this.glyph, {super.key, required this.color, this.size = 20});
  final TabGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _TabIconPainter(glyph, color),
  );
}

class _TabIconPainter extends CustomPainter {
  _TabIconPainter(this.glyph, this.color);
  final TabGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case TabGlyph.home:
        canvas.drawPath(
          Path()
            ..moveTo(3, 8.4)
            ..lineTo(10, 3)
            ..lineTo(17, 8.4)
            ..lineTo(17, 16)
            ..arcToPoint(const Offset(16, 17), radius: const Radius.circular(1))
            ..lineTo(4, 17)
            ..arcToPoint(const Offset(3, 16), radius: const Radius.circular(1))
            ..close(),
          p,
        );
      case TabGlyph.history:
        canvas.drawCircle(const Offset(10, 10), 7.2, p);
        canvas.drawPath(
          Path()
            ..moveTo(10, 6)
            ..lineTo(10, 10.3)
            ..lineTo(13, 12),
          p,
        );
      case TabGlyph.items:
        canvas.drawLine(const Offset(4, 6), const Offset(16, 6), p);
        canvas.drawLine(const Offset(4, 10), const Offset(16, 10), p);
        canvas.drawLine(const Offset(4, 14), const Offset(12, 14), p);
      case TabGlyph.settings:
        p.strokeCap = StrokeCap.butt;
        canvas.drawCircle(const Offset(10, 10), 3.1, p);
        final ring = Path()
          ..addOval(Rect.fromCircle(center: const Offset(10, 10), radius: 7.2));
        for (final m in ring.computeMetrics()) {
          var d = 0.0;
          while (d < m.length) {
            canvas.drawPath(m.extractPath(d, d + 2.4), p);
            d += 5.6;
          }
        }
    }
  }

  @override
  bool shouldRepaint(_TabIconPainter old) =>
      old.glyph != glyph || old.color != color;
}
