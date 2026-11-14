import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/food_csv.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/state/app_state.dart';

const _rotiId = '11111111-1111-4111-8111-111111111111';
const _dalId = '22222222-2222-4222-8222-222222222222';
const _scoop = FoodUnit(id: 'scoop', name: 'Scoop', position: 4);

AppData _data() => AppData(
  items: const [
    FoodItem(
      id: _rotiId,
      name: 'Roti',
      defaultCalories: 100,
      defaultUnit: FoodUnit.piece,
    ),
    FoodItem(id: _dalId, name: 'Dal, tadka', defaultUnit: FoodUnit.cup),
  ],
  meals: const [],
  defaultUnit: FoodUnit.piece,
  units: const [...FoodUnit.builtIns, _scoop],
);

const _header = 'ID,Food,Unit,Calories per unit,Notes';

void main() {
  group('export', () {
    test('every food, quoted where needed, calories as plain numbers', () {
      expect(foodsToCsv(_data()).split('\r\n'), [
        _header,
        '$_dalId,"Dal, tadka",Cup,,',
        '$_rotiId,Roti,Piece,100,',
        '',
      ]);
      expect(
        foodCsvFileName(DateTime(2026, 11, 4)),
        'helpings-foods-2026-11-04.csv',
      );
    });

    test('fill prompt asks questions first and carries the list and units', () {
      final p = buildFillPrompt(_data());
      expect(p, contains('ask me short questions'));
      expect(p, contains('one question at a time'));
      expect(p, contains('Question 1 of'));
      expect(p, contains('Piece, Gram, Spoon, Cup, Scoop'));
      expect(p, contains('```csv\n$_header\r\n'));
      expect(p, contains('"Dal, tadka"'));
    });

    test('starter prompt interviews, skips existing foods, blank IDs', () {
      final p = buildStarterPrompt(_data());
      for (final topic in [
        'where I live',
        'cuisines',
        'vegetarian',
        'home-cooked',
        'Leave the ID column blank',
        'one question at a time',
        'Question 2 of 12',
      ]) {
        expect(p, contains(topic));
      }
      expect(p, contains('Skip foods I already have: Dal, tadka, Roti.'));
      expect(p, contains(_header));
    });
  });

  group('parse', () {
    FoodImport parse(String s) => parseFoodCsv(s, _data());

    test('finds the CSV inside a chat reply with a fence', () {
      final imp = parse('''
Thanks! Here is your list:

```csv
$_header
$_dalId,"Dal, tadka",Cup,180,"Toor dal, 1 tsp ghee"
$_rotiId,Roti,Piece,100,
```

Let me know if you want changes, or more foods.
''');
      expect(imp.rows, hasLength(2));
      final dal = imp.rows.first;
      expect(dal.kind, ImportKind.newCalories);
      expect(dal.calories, 180);
      expect(dal.unit, FoodUnit.cup);
      expect(dal.notes, 'Toor dal, 1 tsp ghee');
      expect(dal.selectedByDefault, isTrue);
      expect(imp.rows.last.kind, ImportKind.unchanged);
    });

    test('without a fence: BOM, LF, trailing chat sentence ignored', () {
      final imp = parse(
        '﻿Sure.\n$_header\n$_rotiId,Roti,Piece,120 kcal,\n'
        'Hope this helps, enjoy!\n',
      );
      expect(imp.rows, hasLength(1));
      expect(imp.rows.single.kind, ImportKind.changed);
      expect(imp.rows.single.calories, 120);
      expect(imp.rows.single.selectedByDefault, isFalse);
    });

    test('columns in any order, extra columns ignored', () {
      final imp = parse(
        'Notes,Calories per unit,Protein,Food\nhomemade,1,200,Ghee rice\n',
      );
      expect(imp.rows.single.name, 'Ghee rice');
      expect(imp.rows.single.calories, 1);
    });

    test('matches by name when the ID is missing; never renames', () {
      final imp = parse('$_header\n,roti,Piece,110,\n');
      final r = imp.rows.single;
      expect(r.item?.id, _rotiId);
      expect(r.name, 'Roti');
      expect(r.kind, ImportKind.changed);
    });

    test('new foods; Helpings-style unknown ID skipped; other IDs ignored', () {
      final imp = parse(
        '$_header\n'
        ',Masala Dosa,Piece,350,\n'
        '99999999-9999-4999-8999-999999999999,Old food,Piece,10,\n'
        '7,Filter Coffee,Cup,110,\n',
      );
      expect(imp.rows.map((r) => (r.name, r.kind)), [
        ('Masala Dosa', ImportKind.newFood),
        ('Old food', ImportKind.skipped),
        ('Filter Coffee', ImportKind.newFood),
      ]);
    });

    test('rejects ranges and words; blank calories leave a food alone', () {
      final imp = parse(
        '$_header\n'
        '$_rotiId,Roti,Piece,90-110,\n'
        '$_dalId,"Dal, tadka",Gram,,\n'
        ',Poha,Cup,about 250,\n'
        ',Big thali,Plate,"1,200",\n',
      );
      expect(imp.rows.map((r) => r.kind), [
        ImportKind.skipped,
        ImportKind.unchanged,
        ImportKind.skipped,
        ImportKind.newFood,
      ]);
      expect(imp.rows.first.reason, contains('90-110'));
      // A unit on its own doesn't change anything: calories belong to it.
      expect(imp.rows[1].unit, FoodUnit.cup);
      expect(imp.rows.last.calories, 1200);
    });

    test('units: case, plurals and g match; new ones made once', () {
      final imp = parse(
        '$_header\n'
        ',Paneer,g,2.6,\n'
        ',Whey,scoops,120,\n'
        ',Khichdi,bowl,300,\n'
        ',Kadhi,Bowl,150,\n'
        ',Peanuts,GRAMS,5.7,\n',
      );
      final units = imp.rows.map((r) => r.unit).toList();
      expect(units[0], FoodUnit.gram);
      expect(units[1], _scoop);
      expect(units[2]!.name, 'Bowl');
      expect(units[3], units[2]);
      expect(imp.rows.map((r) => r.newUnit), [false, false, true, true, false]);
      expect(units[4], FoodUnit.gram);
    });

    test('a food listed twice: the first one counts', () {
      final imp = parse(
        '$_header\n$_rotiId,Roti,Piece,110,\n,ROTI,Piece,120,\n'
        ',Upma,Cup,200,\n,upma,Cup,210,\n',
      );
      expect(imp.rows.map((r) => r.kind), [
        ImportKind.changed,
        ImportKind.skipped,
        ImportKind.newFood,
        ImportKind.skipped,
      ]);
    });

    test('text without a food list is an error', () {
      expect(
        () => parse('Sure, what do you usually eat for breakfast?'),
        throwsA(isA<FoodCsvException>()),
      );
    });

    test('csv fields keep quotes, commas and newlines', () {
      expect(parseCsv('a,"b ""x"", y"\n"multi\nline",c\r\n'), [
        ['a', 'b "x", y'],
        ['multi\nline', 'c'],
      ]);
    });
  });
}
