import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../state/app_state.dart';
import 'csv_export.dart';
import 'format.dart';
import 'models.dart';

/// Columns of the food list CSV, as exported and as the AI prompts ask for.
const foodCsvHeader = ['ID', 'Food', 'Unit', 'Calories per unit', 'Notes'];

/// Every food, hidden ones included, one row each in name order. Notes are
/// left blank for the AI to fill in. RFC 4180 quoting, CRLF line endings.
String foodsToCsv(AppData data) {
  final items = [...data.items]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final rows = <List<String>>[
    foodCsvHeader,
    for (final i in items)
      [i.id, i.name, i.defaultUnit?.name ?? '', fmtQty(i.defaultCalories), ''],
  ];
  return '${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

/// e.g. `helpings-foods-2026-11-14.csv`
String foodCsvFileName(DateTime t) => 'helpings-foods-${dayKey(t)}.csv';

String _unitList(AppData data) {
  final names = data.visibleUnits.map((u) => u.name).toList();
  return names.isEmpty ? 'Piece, Gram, Spoon, Cup' : names.join(', ');
}

const _oneAtATime =
    'Ask me one question at a time, never several in one message, and wait '
    'for my answer before asking the next. Work out first how many questions '
    'you will ask, and number each one with the total, like "Question 1 of '
    '12", then "Question 2 of 12". If my answers mean you need more or fewer '
    'questions, update the total ("Question 5 of 14") and carry on. Keep each '
    'question short, and suggest typical answers I can pick from where that '
    'helps.';

const _outputRules = '''
Rules for the CSV:
- Keep exactly these columns: ID,Food,Unit,Calories per unit,Notes
- "Calories per unit" is kcal for exactly ONE of the row's Unit: for Gram it is per 1 gram (not per 100 g), for Piece it is per one piece.
- Write a single plain number in "Calories per unit", such as 120 or 2.4. No ranges, no "kcal", no words. If you aren't reasonably sure, leave it blank.
- Put your assumption for each food in Notes, briefly (for example "1 roti ≈ 35 g wheat flour, no ghee").
- Reply with the complete CSV in one ```csv code block, so I can copy it in one go.''';

/// The prompt (with the food list inline) for an AI chat to fill in
/// calories after asking the questions that change them.
String buildFillPrompt(AppData data) =>
    '''
I log my meals in an app called Helpings. Below is my food list as CSV. Please help me fill in the calories.

Before filling in anything, ask me short questions about whatever would change the calories: how big one unit is for me (one roti, one bowl, one cup), how the food is usually made (oil, ghee, butter, sugar, milk), recipe or brand, and whether it's home-cooked or from a restaurant. Only ask what actually changes the numbers.

$_oneAtATime

Then fill in "Calories per unit" for the foods where it is blank. Leave foods that already have calories as they are unless I ask you to check them too.

$_outputRules
- Keep every row, and keep the ID and Food of every row exactly as they are. Don't add or remove foods.
- You may change a food's Unit if that gives a more accurate number (for example Gram instead of Cup); the calories must then be for one of the new unit. Prefer my units: ${_unitList(data)}. A new unit name (such as Bowl or Glass) is fine if none of those fit.

My food list:

```csv
${foodsToCsv(data).trimRight()}
```
''';

/// The prompt for an AI chat to interview the user about what they eat and
/// suggest a starter food list in the import format.
String buildStarterPrompt(AppData data) {
  final have = ([...data.items.map((i) => i.name)]..sort()).join(', ');
  return '''
I log my meals in an app called Helpings, and I'd like a starter list of the foods I usually eat, with calories, that I can import into it.

First interview me. $_oneAtATime

Cover:
- where I live (country, and region or city if it matters for the food);
- which cuisines I usually eat;
- whether I'm vegetarian, eggetarian, non-vegetarian, vegan, Jain, or have other restrictions or allergies;
- how often I eat home-cooked food versus eating out or ordering in, and which restaurants, chains or cafeterias;
- what a typical breakfast, lunch, dinner and snack looks like for me;
- what I drink (tea or coffee with milk and sugar, juices, soft drinks, alcohol);
- packaged foods and brands I use regularly;
- how food is usually cooked at home (oil, ghee, butter, and roughly how much);
- whether I have a goal (such as losing weight) only if it changes which foods belong on the list.

Then suggest the 30 to 60 foods I'm most likely to log, named the way I'd say them (for example "Roti", "Masala Dosa", "Chicken Biryani"). Show them to me as a table first and adjust the list if I ask. When I'm happy, give me the final CSV.

$_outputRules
- Leave the ID column blank on every row.
- Give each food the unit I'd naturally count it in. Prefer my units: ${_unitList(data)}. A new unit name (such as Bowl, Glass or Slice) is fine if none of those fit.
${have.isEmpty ? '' : '- Skip foods I already have: $have.\n'}
The CSV must start with this header line:
${foodCsvHeader.join(',')}
''';
}

// ---- Import ----------------------------------------------------------------

/// What an imported row would do.
enum ImportKind {
  /// A food that isn't on the list yet.
  newFood,

  /// An existing food with no calories that now gets some.
  newCalories,

  /// An existing food whose calories or unit would change.
  changed,

  /// Same as now, or left blank.
  unchanged,

  /// Can't be imported; see [ImportRow.reason].
  skipped,
}

/// One data row of a pasted food list, matched against the current list.
@immutable
class ImportRow {
  const ImportRow({
    required this.line,
    required this.name,
    required this.kind,
    this.item,
    this.calories,
    this.unit,
    this.newUnit = false,
    this.notes = '',
    this.reason,
  });

  /// 1-based row number in the CSV, counting the header.
  final int line;

  /// The food's current name for an existing food, else as written.
  final String name;
  final ImportKind kind;

  /// The existing food, for [ImportKind.newCalories], [ImportKind.changed]
  /// and [ImportKind.unchanged].
  final FoodItem? item;

  /// Calories per one [unit] after import.
  final double? calories;

  /// Unit after import.
  final FoodUnit? unit;

  /// [unit] doesn't exist yet and would be created.
  final bool newUnit;

  /// The AI's assumption, shown to the user, not stored.
  final String notes;

  /// Why a [ImportKind.skipped] row can't be imported.
  final String? reason;

  /// Ticked when the review screen opens: additions yes, overwrites no.
  bool get selectedByDefault =>
      kind == ImportKind.newFood || kind == ImportKind.newCalories;

  bool get importable =>
      kind == ImportKind.newFood ||
      kind == ImportKind.newCalories ||
      kind == ImportKind.changed;
}

@immutable
class FoodImport {
  const FoodImport(this.rows);
  final List<ImportRow> rows;

  Iterable<ImportRow> of(ImportKind k) => rows.where((r) => r.kind == k);

  bool get hasChanges => rows.any((r) => r.importable);
}

/// The pasted text isn't a food list at all.
class FoodCsvException implements Exception {
  const FoodCsvException(this.message);
  final String message;
  @override
  String toString() => message;
}

const _uuid = Uuid();

/// Reads a food list pasted from an AI chat (or a CSV file) and matches it
/// against [data]. Tolerates chat text around the CSV, ``` fences, a BOM,
/// any line endings, extra or reordered columns, and "120 kcal". Throws
/// [FoodCsvException] when no food list can be found.
///
/// Existing foods are matched by ID, then by name (ignoring case); only
/// their calories and unit can change, never the name. A row with no
/// matching food becomes a new food, unless it carries an ID that looks
/// like one of Helpings' own (then it was probably deleted, so it's
/// skipped). Unit names are matched ignoring case and plurals; others
/// become new units.
FoodImport parseFoodCsv(String text, AppData data) {
  final table = parseCsv(_extractCsv(text));
  final headerAt = table.indexWhere(_isHeader);
  if (headerAt < 0) {
    throw const FoodCsvException(
      'Couldn’t find a food list in that text. Copy the AI’s whole reply, '
      'including the line that starts with “ID,Food”.',
    );
  }
  final header = [for (final h in table[headerAt]) _norm(h)];
  int col(bool Function(String) test) => header.indexWhere(test);
  final idCol = col((h) => h == 'id');
  final foodCol = col(
    (h) => const {'food', 'name', 'food item', 'item'}.contains(h),
  );
  final unitCol = col((h) => h == 'unit' || h == 'units');
  final calCol = col((h) => h.startsWith('calories') || h.startsWith('kcal'));
  final notesCol = col(
    (h) => h.startsWith('note') || h.startsWith('assumption'),
  );

  final byId = {for (final i in data.items) i.id: i};
  final byName = {for (final i in data.items) _norm(i.name): i};
  final units = _UnitMatcher(data.units);
  final seenItems = <String>{};
  final seenNew = <String>{};
  final rows = <ImportRow>[];

  for (var r = headerAt + 1; r < table.length; r++) {
    final cells = table[r];
    String cell(int c) => c >= 0 && c < cells.length ? cells[c].trim() : '';
    // Blank lines, and chat sentences after the table: too few cells to
    // reach the food and calories columns.
    if (cells.length <= (foodCol > calCol ? foodCol : calCol) ||
        cells.every((c) => c.trim().isEmpty)) {
      continue;
    }
    final line = r - headerAt + 1;
    final id = cell(idCol);
    final rawName = cell(foodCol).replaceAll(RegExp(r'\s+'), ' ');
    final notes = cell(notesCol);
    final rawCal = cell(calCol);
    final rawUnit = cell(unitCol);

    ImportRow skip(String name, String reason) => ImportRow(
      line: line,
      name: name,
      kind: ImportKind.skipped,
      notes: notes,
      reason: reason,
    );

    final item = byId[id] ?? byName[_norm(rawName)];
    if (item == null && rawName.isEmpty) {
      rows.add(skip('Row $line', 'No food name'));
      continue;
    }
    final name = item?.name ?? rawName;
    if (item == null && _uuidLike.hasMatch(id)) {
      rows.add(skip(name, 'Not in your list any more'));
      continue;
    }
    if (item != null ? !seenItems.add(item.id) : !seenNew.add(_norm(name))) {
      rows.add(skip(name, 'Listed twice; the first one is used'));
      continue;
    }

    final cal = _parseCalories(rawCal);
    if (cal == _invalid) {
      rows.add(skip(name, '“$rawCal” isn’t a single number of calories'));
      continue;
    }
    final (unit, isNewUnit) = rawUnit.isEmpty
        ? (item?.defaultUnit, false)
        : units.match(rawUnit);

    if (item == null) {
      rows.add(
        ImportRow(
          line: line,
          name: name,
          kind: ImportKind.newFood,
          calories: cal,
          unit: unit,
          newUnit: isNewUnit,
          notes: notes,
        ),
      );
      continue;
    }

    // Calories belong to a unit, so a unit without calories is ignored.
    final kind = cal == null
        ? ImportKind.unchanged
        : item.defaultCalories == null
        ? ImportKind.newCalories
        : (cal - item.defaultCalories!).abs() < 0.001 &&
              unit == item.defaultUnit
        ? ImportKind.unchanged
        : ImportKind.changed;
    final applies = kind != ImportKind.unchanged;
    rows.add(
      ImportRow(
        line: line,
        name: name,
        kind: kind,
        item: item,
        calories: applies ? cal : item.defaultCalories,
        unit: applies ? unit : item.defaultUnit,
        newUnit: applies && isNewUnit,
        notes: notes,
      ),
    );
  }
  return FoodImport(rows);
}

final _uuidLike = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

String _norm(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

bool _isHeader(List<String> row) {
  final h = row.map(_norm).toList();
  return h.any((c) => c.startsWith('calories') || c.startsWith('kcal')) &&
      h.any((c) => const {'food', 'name', 'food item', 'item'}.contains(c));
}

/// The CSV inside [text]: the first ``` fenced block that contains a
/// header, else everything from the header line on.
String _extractCsv(String text) {
  var t = text.replaceAll('﻿', '').replaceAll('\r\n', '\n');
  t = t.replaceAll('\r', '\n');
  final fence = RegExp(r'```[^\n]*\n([\s\S]*?)```');
  for (final m in fence.allMatches(t)) {
    final body = m.group(1)!;
    if (parseCsv(body).any(_isHeader)) return body;
  }
  // An unclosed fence (a reply cut short): drop the opening line.
  return t.replaceAll(RegExp(r'^```.*$', multiLine: true), '');
}

/// Sentinel for a value that isn't a number.
const double _invalid = -1;

/// Null for blank, [_invalid] for anything but one non-negative number.
double? _parseCalories(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  s = s.replaceFirst(RegExp(r'\s*(kcal|calories|cal)\.?$'), '').trim();
  if (RegExp(r'^\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(s)) {
    s = s.replaceAll(',', '');
  }
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(s)) return _invalid;
  return double.parse(s);
}

/// Finds existing units by name, and makes (once per name) the ones that
/// don't exist.
class _UnitMatcher {
  _UnitMatcher(List<FoodUnit> units) {
    for (final u in units) {
      _known[_norm(u.name)] ??= u;
    }
    for (final u in FoodUnit.builtIns) {
      _known[_norm(u.name)] ??= u;
    }
  }

  final _known = <String, FoodUnit>{};
  final _made = <String, FoodUnit>{};

  static const _aliases = {
    'g': 'gram',
    'gm': 'gram',
    'gms': 'gram',
    'grams': 'gram',
    'pc': 'piece',
    'pcs': 'piece',
    'pieces': 'piece',
  };

  /// The unit and whether it is new.
  (FoodUnit, bool) match(String raw) {
    final n = _norm(raw);
    final singular =
        n.endsWith('es') && _known.containsKey(n.substring(0, n.length - 2))
        ? n.substring(0, n.length - 2)
        : n.endsWith('s')
        ? n.substring(0, n.length - 1)
        : n;
    for (final key in [n, _aliases[n], singular]) {
      final u = key == null ? null : _known[key];
      if (u != null) return (u, false);
    }
    final made = _made.putIfAbsent(
      n,
      () => FoodUnit(id: _uuid.v4(), name: _titleCase(raw)),
    );
    return (made, true);
  }

  static String _titleCase(String s) => s
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// RFC 4180 rows from [text]: quoted fields may hold commas, quotes ("")
/// and newlines. Accepts LF or CRLF.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var i = 0;
  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"' && field.toString().trim().isEmpty) {
      field.clear();
      quoted = true;
    } else if (ch == ',') {
      endField();
    } else if (ch == '\n') {
      endRow();
    } else if (ch != '\r') {
      field.write(ch);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
