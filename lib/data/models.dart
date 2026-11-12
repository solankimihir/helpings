import 'package:flutter/foundation.dart';

/// A kind of meal ("Breakfast", "Pre-workout"…). Fully user-editable; the
/// built-ins are just seeded rows whose ids ('breakfast', 'lunch', …) match
/// what v1 stored in `meals.type`.
@immutable
class MealType {
  const MealType({
    required this.id,
    required this.name,
    this.position = 0,
    this.active = true,
    this.startMinute,
  });

  final String id;
  final String name;

  /// Order in chips and lists, ascending.
  final int position;

  /// Hidden types stay on old meals but aren't offered for new ones.
  final bool active;

  /// "Usually starts at", minutes after midnight. Null: never auto-picked.
  final int? startMinute;

  MealType copyWith({
    String? name,
    int? position,
    bool? active,
    int? Function()? startMinute,
  }) => MealType(
    id: id,
    name: name ?? this.name,
    position: position ?? this.position,
    active: active ?? this.active,
    startMinute: startMinute != null ? startMinute() : this.startMinute,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'position': position,
    'active': active ? 1 : 0,
    'start_minute': startMinute,
  };

  factory MealType.fromRow(Map<String, Object?> r) => MealType(
    id: r['id'] as String,
    name: r['name'] as String,
    position: r['position'] as int,
    active: (r['active'] as int) == 1,
    startMinute: r['start_minute'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is MealType &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.active == active &&
      other.startMinute == startMinute;

  @override
  int get hashCode => Object.hash(id, name, position, active, startMinute);
}

/// Picks the type for a new meal at [now]: the visible type whose start time
/// passed most recently today, wrapping to last night's (e.g. Dinner at 2am)
/// before the first start. With no start times at all, the first visible
/// type. Null only if there are no visible types.
MealType? guessMealType(Iterable<MealType> types, DateTime now) {
  final visible = types.where((t) => t.active).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  final timed = visible.where((t) => t.startMinute != null).toList()
    ..sort((a, b) => a.startMinute!.compareTo(b.startMinute!));
  if (timed.isEmpty) return visible.isEmpty ? null : visible.first;
  final minute = now.hour * 60 + now.minute;
  return timed.lastWhere(
    (t) => t.startMinute! <= minute,
    orElse: () => timed.last,
  );
}

enum FoodUnit {
  piece('Piece'),
  gram('Gram'),
  spoon('Spoon'),
  cup('Cup');

  const FoodUnit(this.label);
  final String label;

  static FoodUnit? tryParse(String? name) {
    if (name == null) return null;
    for (final u in values) {
      if (u.name == name) return u;
    }
    return null;
  }
}

/// A food in the master list ("Meal Items" tab).
@immutable
class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    this.defaultCalories,
    this.defaultUnit,
    this.active = true,
  });

  final String id;
  final String name;
  final double? defaultCalories;
  final FoodUnit? defaultUnit;
  final bool active;

  FoodItem copyWith({
    String? name,
    double? Function()? defaultCalories,
    FoodUnit? Function()? defaultUnit,
    bool? active,
  }) => FoodItem(
    id: id,
    name: name ?? this.name,
    defaultCalories: defaultCalories != null
        ? defaultCalories()
        : this.defaultCalories,
    defaultUnit: defaultUnit != null ? defaultUnit() : this.defaultUnit,
    active: active ?? this.active,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'default_calories': defaultCalories,
    'default_unit': defaultUnit?.name,
    'active': active ? 1 : 0,
  };

  factory FoodItem.fromRow(Map<String, Object?> r) => FoodItem(
    id: r['id'] as String,
    name: r['name'] as String,
    defaultCalories: (r['default_calories'] as num?)?.toDouble(),
    defaultUnit: FoodUnit.tryParse(r['default_unit'] as String?),
    active: (r['active'] as int) == 1,
  );

  @override
  bool operator ==(Object other) =>
      other is FoodItem &&
      other.id == id &&
      other.name == name &&
      other.defaultCalories == defaultCalories &&
      other.defaultUnit == defaultUnit &&
      other.active == active;

  @override
  int get hashCode =>
      Object.hash(id, name, defaultCalories, defaultUnit, active);
}

/// One line inside a meal. Quantity, unit and calories are copied at log time
/// so later edits to the food item never rewrite history. [itemId] becomes
/// null if the food item is deleted; [nameSnapshot] keeps the line readable.
@immutable
class MealEntry {
  const MealEntry({
    required this.id,
    required this.nameSnapshot,
    this.itemId,
    this.qty,
    this.unit,
    this.calories,
  });

  final String id;
  final String? itemId;
  final String nameSnapshot;
  final double? qty;
  final FoodUnit? unit;
  final double? calories;

  Map<String, Object?> toRow(String mealId, int position) => {
    'id': id,
    'meal_id': mealId,
    'item_id': itemId,
    'name_snapshot': nameSnapshot,
    'qty': qty,
    'unit': unit?.name,
    'calories': calories,
    'position': position,
  };

  factory MealEntry.fromRow(Map<String, Object?> r) => MealEntry(
    id: r['id'] as String,
    itemId: r['item_id'] as String?,
    nameSnapshot: r['name_snapshot'] as String,
    qty: (r['qty'] as num?)?.toDouble(),
    unit: FoodUnit.tryParse(r['unit'] as String?),
    calories: (r['calories'] as num?)?.toDouble(),
  );
}

@immutable
class Meal {
  const Meal({
    required this.id,
    required this.typeId,
    required this.date,
    required this.time,
    this.notes = '',
    this.entries = const [],
  });

  final String id;

  /// [MealType.id]; stored in the `type` column.
  final String typeId;

  /// Local calendar day, `YYYY-MM-DD`.
  final String date;

  /// 24h local time, `HH:mm`.
  final String time;
  final String notes;
  final List<MealEntry> entries;

  String get sortKey => '$date $time';

  MealTotals get totals => MealTotals.of(entries);

  Map<String, Object?> toRow() => {
    'id': id,
    'type': typeId,
    'date': date,
    'time': time,
    'notes': notes,
  };

  factory Meal.fromRow(Map<String, Object?> r, List<MealEntry> entries) => Meal(
    id: r['id'] as String,
    typeId: r['type'] as String,
    date: r['date'] as String,
    time: r['time'] as String,
    notes: (r['notes'] as String?) ?? '',
    entries: entries,
  );
}

/// Calories are never estimated: a total is only "complete" when every line
/// has a value.
@immutable
class MealTotals {
  const MealTotals(this.sum, this.missing, this.count);

  final double sum;
  final int missing;
  final int count;

  bool get complete => missing == 0 && count > 0;

  factory MealTotals.of(Iterable<MealEntry> entries) {
    var sum = 0.0, missing = 0, count = 0;
    for (final e in entries) {
      count++;
      if (e.calories == null) {
        missing++;
      } else {
        sum += e.calories!;
      }
    }
    return MealTotals(sum, missing, count);
  }

  MealTotals operator +(MealTotals o) =>
      MealTotals(sum + o.sum, missing + o.missing, count + o.count);

  static const zero = MealTotals(0, 0, 0);
}
