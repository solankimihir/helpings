import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/measures.dart';

void main() {
  test('sugar converts between mg/dL and mmol/L', () {
    expect(SugarUnit.mgdl.format(104), '104');
    expect(SugarUnit.mmol.format(108.1), '6');
    expect(SugarUnit.mmol.format(99), '5.5');
    final stored = SugarUnit.mmol.fromDisplay(5.5);
    expect(SugarUnit.mmol.format(stored), '5.5');
    expect(SugarUnit.mgdl.format(stored), '99');
  });

  test('weight converts between kg and lb', () {
    expect(WeightUnit.kg.format(72.45), '72.5');
    expect(WeightUnit.kg.format(72), '72');
    expect(WeightUnit.lb.format(WeightUnit.lb.fromDisplay(160)), '160');
    expect(WeightUnit.kg.formatChange(-1.24), '−1.2');
    expect(WeightUnit.kg.formatChange(0.6), '+0.6');
    expect(WeightUnit.kg.formatChange(0.01), '0');
  });

  test('water converts between ml and fl oz, with presets', () {
    expect(WaterUnit.ml.format(1250), '1,250');
    expect(WaterUnit.ml.format(250), '250');
    expect(WaterUnit.floz.format(WaterUnit.floz.fromDisplay(8)), '8');
    expect(WaterUnit.ml.presets, [250, 500]);
    expect(
      [for (final p in WaterUnit.floz.presets) WaterUnit.floz.format(p)],
      ['8', '16'],
    );
  });

  test('unknown stored units fall back to the default', () {
    expect(SugarUnit.parse(null), SugarUnit.mgdl);
    expect(WeightUnit.parse('stone'), WeightUnit.kg);
    expect(WaterUnit.parse('floz'), WaterUnit.floz);
  });

  group('niceRange', () {
    test('needn\'t start at zero', () {
      final (lo, hi, step) = niceRange(71.2, 73.8);
      expect(lo, lessThanOrEqualTo(71.2));
      expect(hi, greaterThanOrEqualTo(73.8));
      expect(lo, greaterThan(60));
      expect((hi - lo) / step, lessThanOrEqualTo(5));
    });

    test('sugar readings get clean steps', () {
      expect(niceRange(92, 141), (80.0, 160.0, 20.0));
    });

    test('a single value gets headroom', () {
      final (lo, hi, _) = niceRange(100, 100);
      expect(lo, lessThan(100));
      expect(hi, greaterThan(100));
    });
  });
}
