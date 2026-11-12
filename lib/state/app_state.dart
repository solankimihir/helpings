import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/models.dart';
import '../data/repository.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Overridden in tests with an in-memory database.
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = FutureProvider<Repository>(
  (ref) async => Repository(await ref.watch(databaseProvider.future)),
);

/// Snapshot of everything the UI renders. Small enough to hold in memory.
@immutable
class AppData {
  AppData({required this.items, required this.meals, required this.defaultUnit})
    : _byId = {for (final i in items) i.id: i};

  final List<FoodItem> items;

  /// Oldest first.
  final List<Meal> meals;
  final FoodUnit defaultUnit;
  final Map<String, FoodItem> _byId;

  FoodItem? itemById(String? id) => id == null ? null : _byId[id];

  /// Current name of the food if it still exists, else the logged name.
  String displayName(MealEntry e) => itemById(e.itemId)?.name ?? e.nameSnapshot;

  Meal? mealById(String id) {
    for (final m in meals) {
      if (m.id == id) return m;
    }
    return null;
  }
}

const _kDefaultUnit = 'default_unit';

class AppDataNotifier extends AsyncNotifier<AppData> {
  Future<Repository> get _repo => ref.read(repositoryProvider.future);

  @override
  Future<AppData> build() async {
    final repo = await ref.watch(repositoryProvider.future);
    return _load(repo);
  }

  Future<AppData> _load(Repository repo) async {
    final results = await Future.wait([
      repo.items(),
      repo.meals(),
      repo.setting(_kDefaultUnit),
    ]);
    return AppData(
      items: results[0] as List<FoodItem>,
      meals: results[1] as List<Meal>,
      defaultUnit: FoodUnit.tryParse(results[2] as String?) ?? FoodUnit.piece,
    );
  }

  Future<void> _mutate(Future<void> Function(Repository r) op) async {
    final repo = await _repo;
    await op(repo);
    state = AsyncData(await _load(repo));
  }

  Future<void> saveMeal(Meal meal) => _mutate((r) => r.saveMeal(meal));

  Future<void> deleteMeal(String id) => _mutate((r) => r.deleteMeal(id));

  Future<void> deleteAllMeals() => _mutate((r) => r.deleteAllMeals());

  /// Throws [DuplicateNameException]. Returns the saved item.
  Future<FoodItem> saveItem(FoodItem item) async {
    await _mutate((r) => r.saveItem(item));
    return item;
  }

  Future<void> setItemActive(String id, bool active) =>
      _mutate((r) => r.setItemActive(id, active));

  Future<void> deleteItem(String id) => _mutate((r) => r.deleteItem(id));

  Future<int> itemUsageCount(String id) async =>
      (await _repo).itemUsageCount(id);

  Future<int> restoreDefaultItems() async {
    var added = 0;
    await _mutate((r) async => added = await r.restoreDefaultItems());
    return added;
  }

  Future<void> setDefaultUnit(FoodUnit u) =>
      _mutate((r) => r.setSetting(_kDefaultUnit, u.name));
}

final appDataProvider = AsyncNotifierProvider<AppDataNotifier, AppData>(
  AppDataNotifier.new,
);
