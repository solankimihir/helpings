import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Starter food list, pre-filled on first launch.
const defaultItems = <(String, double?, FoodUnit)>[
  ('Roti', 100, FoodUnit.piece),
  ('Dal', 180, FoodUnit.cup),
  ('Bhindi', 120, FoodUnit.cup),
  ('Rice', 200, FoodUnit.cup),
  ('Idli', 60, FoodUnit.piece),
  ('Sambar', null, FoodUnit.cup),
  ('Tea', 90, FoodUnit.cup),
  ('Poha', 250, FoodUnit.cup),
  ('Vada Pav', 300, FoodUnit.piece),
  ('Curd', 90, FoodUnit.cup),
  ('Bread Pakora', 280, FoodUnit.piece),
];

/// Inserts every default item whose name isn't already taken
/// (case-insensitive). Existing items are left untouched. Returns how many
/// were added.
Future<int> insertDefaultItems(DatabaseExecutor db) async {
  const uuid = Uuid();
  final now = DateTime.now().millisecondsSinceEpoch;
  var added = 0;
  for (final (name, cal, unit) in defaultItems) {
    final id = await db.insert('food_items', {
      'id': uuid.v4(),
      'name': name,
      'default_calories': cal,
      'default_unit': unit.name,
      'active': 1,
      'created_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id != 0) added++;
  }
  return added;
}
