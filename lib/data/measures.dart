import 'dart:math' as math;

/// Display units for the health trackers. Values are always stored in one
/// canonical unit (mg/dL, kg, ml) and converted only for display and entry.

const _mgdlPerMmol = 18.016;
const _lbPerKg = 2.20462;
const _mlPerFloz = 29.5735;

/// Strips a trailing `.0` and rounds to [digits] decimals.
String _fmt(double v, int digits) {
  final s = v.toStringAsFixed(digits);
  if (!s.contains('.')) return s;
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

enum SugarUnit {
  mgdl('mg/dL', 0),
  mmol('mmol/L', 1);

  const SugarUnit(this.label, this.digits);
  final String label;

  /// Decimals shown.
  final int digits;

  /// [mgdl] in this unit.
  double toDisplay(double mgdl) => this == mmol ? mgdl / _mgdlPerMmol : mgdl;

  /// A value typed in this unit, as mg/dL.
  double fromDisplay(double v) => this == mmol ? v * _mgdlPerMmol : v;

  /// "112" / "6.2" — no unit.
  String format(double mgdl) => _fmt(toDisplay(mgdl), digits);

  static SugarUnit parse(String? v) =>
      values.firstWhere((u) => u.name == v, orElse: () => mgdl);
}

enum WeightUnit {
  kg('kg'),
  lb('lb');

  const WeightUnit(this.label);
  final String label;

  double toDisplay(double kg) => this == lb ? kg * _lbPerKg : kg;
  double fromDisplay(double v) => this == lb ? v / _lbPerKg : v;

  /// "72.4" — no unit.
  String format(double kg) => _fmt(toDisplay(kg), 1);

  /// "+0.6" / "−1.2" / "0" for a change of [deltaKg].
  String formatChange(double deltaKg) {
    final d = toDisplay(deltaKg);
    final s = _fmt(d.abs(), 1);
    if (s == '0') return '0';
    return '${d > 0 ? '+' : '−'}$s';
  }

  static WeightUnit parse(String? v) =>
      values.firstWhere((u) => u.name == v, orElse: () => kg);
}

enum WaterUnit {
  ml('ml'),
  floz('fl oz');

  const WaterUnit(this.label);
  final String label;

  double toDisplay(double ml) => this == floz ? ml / _mlPerFloz : ml;
  double fromDisplay(double v) => this == floz ? v * _mlPerFloz : v;

  /// "750" / "25.4" — no unit; thousands get a separator in ml.
  String format(double ml) {
    if (this == floz) return _fmt(toDisplay(ml), 1);
    final n = ml.round();
    return n >= 1000
        ? '${n ~/ 1000},${(n % 1000).toString().padLeft(3, '0')}'
        : '$n';
  }

  /// Quick-add amounts, in ml.
  List<double> get presets =>
      this == floz ? [8 * _mlPerFloz, 16 * _mlPerFloz] : const [250, 500];

  static WaterUnit parse(String? v) =>
      values.firstWhere((u) => u.name == v, orElse: () => ml);
}

/// A y-axis range around [lo]..[hi] that needn't start at zero: clean
/// bottom, top and step with 2–5 steps. A flat series gets some headroom.
(double, double, double) niceRange(double lo, double hi) {
  if (lo > hi) (lo, hi) = (hi, lo);
  var span = hi - lo;
  if (span <= 0) {
    final pad = math.max(1.0, hi.abs() * .05);
    lo -= pad;
    hi += pad;
    span = hi - lo;
  }
  final mag = math.pow(10, (math.log(span) / math.ln10).floor()).toDouble();
  for (final f in const [.1, .2, .25, .5, 1.0, 2.0, 2.5, 5.0, 10.0]) {
    final step = mag * f;
    final bottom = (lo / step).floor() * step;
    final top = (hi / step).ceil() * step;
    final steps = ((top - bottom) / step).round();
    if (steps <= 5) {
      return (bottom, top == bottom ? bottom + step : top, step);
    }
  }
  return (lo, hi, span);
}
