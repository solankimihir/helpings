import 'package:flutter/foundation.dart';

enum MealType {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack'),
  other('Other');

  const MealType(this.label);
  final String label;

  static MealType fromName(String name) =>
      MealType.values.firstWhere((t) => t.name == name, orElse: () => other);

  /// Guess from the clock, as the design does.
  static MealType forHour(int h) => h < 11
      ? breakfast
      : h < 15
      ? lunch
      : h < 18
      ? snack
      : dinner;
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
    required this.type,
    required this.date,
    required this.time,
    this.notes = '',
    this.entries = const [],
  });

  final String id;
  final MealType type;

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
    'type': type.name,
    'date': date,
    'time': time,
    'notes': notes,
  };

  factory Meal.fromRow(Map<String, Object?> r, List<MealEntry> entries) => Meal(
    id: r['id'] as String,
    type: MealType.fromName(r['type'] as String),
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
