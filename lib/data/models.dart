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
    this.remindMinute,
  });

  final String id;
  final String name;

  /// Order in chips and lists, ascending.
  final int position;

  /// Hidden types stay on old meals but aren't offered for new ones.
  final bool active;

  /// "Usually starts at", minutes after midnight. Null: never auto-picked.
  final int? startMinute;

  /// Daily reminder time, minutes after midnight. Null: no reminder.
  final int? remindMinute;

  MealType copyWith({
    String? name,
    int? position,
    bool? active,
    int? Function()? startMinute,
    int? Function()? remindMinute,
  }) => MealType(
    id: id,
    name: name ?? this.name,
    position: position ?? this.position,
    active: active ?? this.active,
    startMinute: startMinute != null ? startMinute() : this.startMinute,
    remindMinute: remindMinute != null ? remindMinute() : this.remindMinute,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'position': position,
    'active': active ? 1 : 0,
    'start_minute': startMinute,
    'remind_minute': remindMinute,
  };

  factory MealType.fromRow(Map<String, Object?> r) => MealType(
    id: r['id'] as String,
    name: r['name'] as String,
    position: r['position'] as int,
    active: (r['active'] as int) == 1,
    startMinute: r['start_minute'] as int?,
    remindMinute: r['remind_minute'] as int?,
  );

  @override
  bool operator ==(Object other) =>
      other is MealType &&
      other.id == id &&
      other.name == name &&
      other.position == position &&
      other.active == active &&
      other.startMinute == startMinute &&
      other.remindMinute == remindMinute;

  @override
  int get hashCode =>
      Object.hash(id, name, position, active, startMinute, remindMinute);
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

/// A unit of quantity ("Piece", "Cup", or the user's own, like "Scoop").
/// Stored in the `units` table; lines and foods keep only its [id].
///
/// Two units are equal when their ids are, so a renamed unit still matches
/// what was logged with it.
@immutable
class FoodUnit {
  const FoodUnit({
    required this.id,
    required this.name,
    this.position = 0,
    this.active = true,
  });

  static const piece = FoodUnit(id: 'piece', name: 'Piece');
  static const gram = FoodUnit(id: 'gram', name: 'Gram', position: 1);
  static const spoon = FoodUnit(id: 'spoon', name: 'Spoon', position: 2);
  static const cup = FoodUnit(id: 'cup', name: 'Cup', position: 3);

  /// Seeded on every install; ids match what earlier versions stored.
  /// They can be hidden but not renamed or deleted.
  static const builtIns = [piece, gram, spoon, cup];

  final String id;

  /// Singular, as shown in pickers: "Scoop".
  final String name;

  /// Order in pickers, ascending.
  final int position;

  /// Hidden units stay on past meals and foods but aren't offered.
  final bool active;

  String get label => name;

  bool get isBuiltIn => builtIns.any((u) => u.id == id);

  /// The unit [id] refers to: from [units] when listed there, else a
  /// built-in, else a stand-in named after the id. Null for a null id.
  static FoodUnit? resolve(
    String? id, [
    Map<String, FoodUnit> units = const {},
  ]) {
    if (id == null) return null;
    final known = units[id];
    if (known != null) return known;
    for (final u in builtIns) {
      if (u.id == id) return u;
    }
    return FoodUnit(id: id, name: id);
  }

  FoodUnit copyWith({String? name, int? position, bool? active}) => FoodUnit(
    id: id,
    name: name ?? this.name,
    position: position ?? this.position,
    active: active ?? this.active,
  );

  Map<String, Object?> toRow() => {
    'id': id,
    'name': name,
    'position': position,
    'active': active ? 1 : 0,
  };

  factory FoodUnit.fromRow(Map<String, Object?> r) => FoodUnit(
    id: r['id'] as String,
    name: r['name'] as String,
    position: r['position'] as int,
    active: (r['active'] as int) == 1,
  );

  @override
  bool operator ==(Object other) => other is FoodUnit && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FoodUnit($id)';
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
    'default_unit': defaultUnit?.id,
    'active': active ? 1 : 0,
  };

  factory FoodItem.fromRow(
    Map<String, Object?> r, [
    Map<String, FoodUnit> units = const {},
  ]) => FoodItem(
    id: r['id'] as String,
    name: r['name'] as String,
    defaultCalories: (r['default_calories'] as num?)?.toDouble(),
    defaultUnit: FoodUnit.resolve(r['default_unit'] as String?, units),
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
    'unit': unit?.id,
    'calories': calories,
    'position': position,
  };

  factory MealEntry.fromRow(
    Map<String, Object?> r, [
    Map<String, FoodUnit> units = const {},
  ]) => MealEntry(
    id: r['id'] as String,
    itemId: r['item_id'] as String?,
    nameSnapshot: r['name_snapshot'] as String,
    qty: (r['qty'] as num?)?.toDouble(),
    unit: FoodUnit.resolve(r['unit'] as String?, units),
    calories: (r['calories'] as num?)?.toDouble(),
  );
}

/// Calories for [qty] [unit] of a food whose default is [cal] per
/// [defUnit]. A missing quantity counts as 1, and a missing unit on either
/// side counts as matching. Null when there's no default or the units differ.
double? scaledCalories({
  double? cal,
  FoodUnit? defUnit,
  double? qty,
  FoodUnit? unit,
}) {
  if (cal == null) return null;
  if (defUnit != null && unit != null && defUnit != unit) return null;
  return cal * (qty ?? 1);
}

/// [scaledCalories] for a line of [item] at its current default.
double? itemCalories(FoodItem item, double? qty, FoodUnit? unit) =>
    scaledCalories(
      cal: item.defaultCalories,
      defUnit: item.defaultUnit,
      qty: qty,
      unit: unit,
    );

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

/// A saved set of lines ("Usual breakfast: 2 Roti + Tea") added to a meal in
/// one tap. Lines are copies, like [MealEntry]: editing a food item later
/// doesn't change the combo.
@immutable
class Combo {
  const Combo({
    required this.id,
    required this.name,
    this.position = 0,
    this.items = const [],
  });

  final String id;
  final String name;
  final int position;
  final List<MealEntry> items;

  Combo copyWith({String? name, List<MealEntry>? items}) => Combo(
    id: id,
    name: name ?? this.name,
    position: position,
    items: items ?? this.items,
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
