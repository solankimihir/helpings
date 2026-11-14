import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/ui/widgets/line_editor.dart';

DraftLine line({String qty = '1', String cal = '100'}) =>
    DraftLine(itemId: 'x', name: 'Roti', qty: qty, unit: null, cal: cal);

void main() {
  test('calories follow the quantity', () {
    final r = line();
    r.qty.text = '3';
    expect(r.cal.text, '300');
    r.qty.text = '';
    expect(r.cal.text, '100');
    r.qty.text = '1.5';
    expect(r.cal.text, '150');
  });

  test('scales from a logged line\'s own per-unit rate', () {
    final r = line(qty: '2', cal: '250');
    r.qty.text = '4';
    expect(r.cal.text, '500');
  });

  test('hand-typed calories set a new rate', () {
    final r = line();
    r.cal.text = '120';
    r.caloriesEdited();
    r.qty.text = '2';
    expect(r.cal.text, '240');
  });

  test('no calories, nothing to scale; zero quantity keeps the rate', () {
    final r = line(cal: '');
    r.qty.text = '3';
    expect(r.cal.text, '');

    final z = line();
    z.qty.text = '0';
    expect(z.cal.text, '0');
    z.qty.text = '2';
    expect(z.cal.text, '200');
  });

  test('rounds to one decimal', () {
    final r = line(cal: '1.1');
    r.qty.text = '3';
    expect(r.cal.text, '3.3');
  });
}
