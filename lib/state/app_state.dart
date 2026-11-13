import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:uuid/uuid.dart';

import '../data/backup.dart';
import '../data/backup_folder.dart';
import '../data/database.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Overridden in tests with an in-memory database.
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open(
    beforeUpgrade: (u) =>
        backupBeforeUpgrade(ref.read(backupFolderProvider), u),
  );
  ref.onDispose(db.close);
  return db;
});

final repositoryProvider = FutureProvider<Repository>(
  (ref) async => Repository(await ref.watch(databaseProvider.future)),
);

/// Snapshot of everything the UI renders. Small enough to hold in memory.
@immutable
class AppData {
  AppData({
    required this.items,
    required this.meals,
    required this.defaultUnit,
    this.units = FoodUnit.builtIns,
    this.mealTypes = const [],
    this.combos = const [],
    this.themeMode = ThemeMode.system,
    this.lastBackupAt,
    this.autoBackup,
    this.remindersOn = false,
  }) : _byId = {for (final i in items) i.id: i},
       _typeById = {for (final t in mealTypes) t.id: t};

  final List<FoodItem> items;

  /// Oldest first.
  final List<Meal> meals;

  /// Pre-filled for new foods. Always a visible unit when there is one.
  final FoodUnit defaultUnit;

  /// Every unit, hidden ones included, in display order.
  final List<FoodUnit> units;

  /// Units offered in pickers.
  List<FoodUnit> get visibleUnits => units.where((u) => u.active).toList();

  /// Units to offer for a field currently set to [current]: the visible
  /// ones, plus [current] if it's hidden so the field can still show it.
  List<FoodUnit> unitsFor(FoodUnit? current) {
    final visible = visibleUnits;
    if (current == null || visible.contains(current)) return visible;
    return [...visible, current];
  }

  /// Every meal type, hidden ones included, in display order.
  final List<MealType> mealTypes;
  final Map<String, MealType> _typeById;

  MealType? typeById(String id) => _typeById[id];

  /// Display name of a meal's type.
  String typeName(Meal m) => _typeById[m.typeId]?.name ?? 'Meal';

  /// Saved combos, in display order.
  final List<Combo> combos;

  /// Types offered for new meals.
  List<MealType> get visibleTypes => mealTypes.where((t) => t.active).toList();

  /// Light, dark, or follow the device.
  final ThemeMode themeMode;

  /// When the user last saved a backup file, if ever.
  final DateTime? lastBackupAt;

  /// Null when automatic backups are off.
  final AutoBackupStatus? autoBackup;

  /// Meal reminder notifications are enabled on this device.
  final bool remindersOn;
  final Map<String, FoodItem> _byId;

  FoodItem? itemById(String? id) => id == null ? null : _byId[id];

  /// Current name of the food if it still exists, else the logged name.
  String displayName(MealEntry e) => itemById(e.itemId)?.name ?? e.nameSnapshot;

  /// [combo]'s lines with calories from each food's current default,
  /// scaled by quantity. Null where the food is gone, has no default, or
  /// the line is in a different unit.
  List<MealEntry> comboLines(Combo combo) => [
    for (final e in combo.items) withItemCalories(e),
  ];

  /// [e] with calories from its food's current default, as in [comboLines].
  MealEntry withItemCalories(MealEntry e) {
    final item = itemById(e.itemId);
    return MealEntry(
      id: e.id,
      itemId: e.itemId,
      nameSnapshot: e.nameSnapshot,
      qty: e.qty,
      unit: e.unit,
      calories: item == null ? null : itemCalories(item, e.qty, e.unit),
    );
  }

  Meal? mealById(String id) {
    for (final m in meals) {
      if (m.id == id) return m;
    }
    return null;
  }
}

/// Saves [u]'s copy of the database before it's upgraded: to the daily
/// backup folder if one is set, otherwise (or if that fails) to the app's
/// own folder. Returns where it went, or null if nowhere could take it.
Future<String?> backupBeforeUpgrade(
  BackupFolder folder,
  PendingUpgrade u, [
  DateTime? now,
]) async {
  final name = preUpgradeFileName(now ?? DateTime.now(), u.from);
  final token = u.settings[_kAutoFolder];
  if (token != null) {
    try {
      await folder.write(token, name, u.bytes);
      return '${u.settings[_kAutoFolderName] ?? 'backup folder'}/$name';
    } catch (e) {
      debugPrint('Pre-upgrade copy to the backup folder failed: $e');
    }
  }
  final dir = await folder.appFolder();
  if (dir == null) return null;
  final file = File('$dir/$name');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(u.bytes, flush: true);
  return file.path;
}

@immutable
class AutoBackupStatus {
  const AutoBackupStatus({
    required this.folderToken,
    required this.folderName,
    this.lastDay,
    this.error,
  });
  final String folderToken;
  final String folderName;

  /// [dayKey] of the last successful automatic backup.
  final String? lastDay;

  /// Why the most recent attempt failed; null if it succeeded.
  final String? error;
}

const _kDefaultUnit = 'default_unit';
const _kThemeMode = 'theme_mode';
const _kLastBackup = 'last_backup_at';
const _kAutoFolder = 'auto_backup_folder';
const _kAutoFolderName = 'auto_backup_folder_name';
const _kAutoLastDay = 'auto_backup_last_day';
const _kAutoError = 'auto_backup_error';
const _kRemindersOn = 'reminders_on';

/// Settings that describe this device rather than the user's data, so a
/// restore from another phone (or an old file) must not overwrite them.
const deviceSettings = {
  _kLastBackup,
  _kAutoFolder,
  _kAutoFolderName,
  _kAutoLastDay,
  _kAutoError,
  _kRemindersOn,
};

ThemeMode _parseThemeMode(String? v) => ThemeMode.values.firstWhere(
  (m) => m.name == v,
  orElse: () => ThemeMode.system,
);

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
      repo.settings(),
      repo.mealTypes(),
      repo.combos(),
      repo.units(),
    ]);
    final units = results[5] as List<FoodUnit>;
    final visible = units.where((u) => u.active);
    final settings = results[2] as Map<String, String?>;
    final folder = settings[_kAutoFolder];
    return AppData(
      items: results[0] as List<FoodItem>,
      meals: results[1] as List<Meal>,
      mealTypes: results[3] as List<MealType>,
      combos: results[4] as List<Combo>,
      units: units,
      defaultUnit:
          visible.where((u) => u.id == settings[_kDefaultUnit]).firstOrNull ??
          visible.firstOrNull ??
          FoodUnit.piece,
      themeMode: _parseThemeMode(settings[_kThemeMode]),
      lastBackupAt: DateTime.tryParse(settings[_kLastBackup] ?? ''),
      remindersOn: settings[_kRemindersOn] == '1',
      autoBackup: folder == null
          ? null
          : AutoBackupStatus(
              folderToken: folder,
              folderName: settings[_kAutoFolderName] ?? 'Backup folder',
              lastDay: settings[_kAutoLastDay],
              error: settings[_kAutoError],
            ),
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

  /// Logged lines a change from [before] to [after] could update.
  Future<PastLines> pastLines(FoodItem before, FoodItem after) async =>
      (await _repo).pastLines(before, after);

  /// Sets [ids] to [item]'s default calories. Returns how many changed.
  Future<int> applyPastLines(FoodItem item, Iterable<String> ids) async {
    var n = 0;
    await _mutate((r) async => n = await r.applyPastLines(item, ids));
    return n;
  }

  /// Lines of [itemId] in [unit], logged and in combos.
  Future<UnitLines> unitLines(String itemId, FoodUnit? unit) async =>
      (await _repo).unitLines(itemId, unit);

  /// Moves [lines] to [unit]. Returns how many changed.
  Future<int> setLineUnits(
    String itemId,
    UnitLines lines,
    FoodUnit unit,
  ) async {
    var n = 0;
    await _mutate((r) async => n = await r.setLineUnits(itemId, lines, unit));
    return n;
  }

  Future<LinesSnapshot> snapshotLines(String itemId) async =>
      (await _repo).snapshotLines(itemId);

  Future<void> restoreLines(LinesSnapshot snap) =>
      _mutate((r) => r.restoreLines(snap));

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

  // ---- Combos -------------------------------------------------------------

  /// Throws [DuplicateNameException]. Returns the saved combo.
  Future<Combo> saveCombo(Combo combo) async {
    await _mutate((r) => r.saveCombo(combo));
    return combo;
  }

  Future<void> reorderCombos(List<String> ids) =>
      _mutate((r) => r.reorderCombos(ids));

  Future<void> deleteCombo(String id) => _mutate((r) => r.deleteCombo(id));

  // ---- Meal types ---------------------------------------------------------

  /// Throws [DuplicateNameException]. Returns the saved type.
  Future<MealType> saveMealType(MealType type) async {
    if (!type.active) _checkNotLastVisible(type.id);
    await _mutate((r) => r.saveMealType(type));
    return type;
  }

  Future<void> setMealTypeActive(String id, bool active) async {
    final t = state.requireValue.typeById(id);
    if (t != null) await saveMealType(t.copyWith(active: active));
  }

  Future<void> reorderMealTypes(List<String> ids) =>
      _mutate((r) => r.reorderMealTypes(ids));

  Future<int> mealTypeUsageCount(String id) async =>
      (await _repo).mealTypeUsageCount(id);

  /// Moves the type's meals to [moveTo] (required if any use it), then
  /// deletes it. The last remaining visible type can't be deleted.
  Future<void> deleteMealType(String id, {String? moveTo}) {
    _checkNotLastVisible(id);
    return _mutate((r) => r.deleteMealType(id, moveTo: moveTo));
  }

  void _checkNotLastVisible(String id) {
    final others = state.requireValue.visibleTypes.where((t) => t.id != id);
    if (others.isEmpty) throw const LastMealTypeException();
  }

  Future<void> setRemindersOn(bool on) =>
      _mutate((r) => r.setSetting(_kRemindersOn, on ? '1' : null));

  Future<void> setDefaultUnit(FoodUnit u) =>
      _mutate((r) => r.setSetting(_kDefaultUnit, u.id));

  // ---- Units --------------------------------------------------------------

  /// Throws [DuplicateNameException] or [LastUnitException]. Returns the
  /// saved unit.
  Future<FoodUnit> saveUnit(FoodUnit unit) async {
    if (!unit.active) _checkNotLastVisibleUnit(unit.id);
    await _mutate((r) => r.saveUnit(unit));
    return unit;
  }

  Future<void> reorderUnits(List<String> ids) =>
      _mutate((r) => r.reorderUnits(ids));

  Future<int> unitUsageCount(String id) async =>
      (await _repo).unitUsageCount(id);

  /// Deletes an unused custom unit. Throws [StateError] otherwise.
  Future<void> deleteUnit(String id) {
    _checkNotLastVisibleUnit(id);
    return _mutate((r) => r.deleteUnit(id));
  }

  void _checkNotLastVisibleUnit(String id) {
    final others = state.requireValue.visibleUnits.where((u) => u.id != id);
    if (others.isEmpty) throw const LastUnitException();
  }

  Future<void> setThemeMode(ThemeMode m) =>
      _mutate((r) => r.setSetting(_kThemeMode, m.name));

  /// Saves a copy of the database wherever the user picks. Returns false if
  /// they cancelled the save dialog; throws if the copy could not be made.
  Future<bool> backup([DateTime? now]) async {
    final repo = await _repo;
    final t = now ?? DateTime.now();
    final bytes = await repo.snapshot();
    final saved = await ref.read(backupSaverProvider)(backupFileName(t), bytes);
    if (saved) {
      await _mutate((r) => r.setSetting(_kLastBackup, t.toIso8601String()));
    }
    return saved;
  }

  BackupFolder get _folder => ref.read(backupFolderProvider);

  Future<void> _setSettings(Repository r, Map<String, String?> values) async {
    for (final e in values.entries) {
      await r.setSetting(e.key, e.value);
    }
  }

  /// Lets the user pick the automatic backup folder, then backs up straight
  /// away so they can see it worked. Returns false if they cancelled.
  Future<bool> chooseAutoBackupFolder([DateTime? now]) async {
    final picked = await _folder.pick();
    if (picked == null) return false;
    final old = state.value?.autoBackup?.folderToken;
    if (old != null && old != picked.token) {
      await _folder.release(old).catchError((_) {});
    }
    await _mutate(
      (r) => _setSettings(r, {
        _kAutoFolder: picked.token,
        _kAutoFolderName: picked.name,
        _kAutoLastDay: null,
        _kAutoError: null,
      }),
    );
    await runAutoBackupIfDue(now);
    return true;
  }

  Future<void> disableAutoBackup() async {
    final token = state.value?.autoBackup?.folderToken;
    if (token != null) await _folder.release(token).catchError((_) {});
    await _mutate(
      (r) => _setSettings(r, {
        _kAutoFolder: null,
        _kAutoFolderName: null,
        _kAutoLastDay: null,
        _kAutoError: null,
      }),
    );
  }

  bool _autoRunning = false;

  /// Writes today's automatic backup if one hasn't been made yet, then
  /// deletes automatic backups beyond the newest [autoBackupKeep]. Never
  /// throws: a failure is recorded on [AutoBackupStatus.error] and retried
  /// on the next open.
  Future<void> runAutoBackupIfDue([DateTime? now]) async {
    final status = state.value?.autoBackup;
    final today = dayKey(now ?? DateTime.now());
    if (status == null || status.lastDay == today || _autoRunning) return;
    _autoRunning = true;
    String? error;
    try {
      final repo = await _repo;
      final token = status.folderToken;
      await _folder.write(
        token,
        autoBackupFileName(now ?? DateTime.now()),
        await repo.snapshot(),
      );
      for (final old in autoBackupsToPrune(await _folder.list(token))) {
        await _folder.delete(token, old);
      }
    } on FolderAccessException catch (e) {
      error = e.message;
    } catch (e) {
      error = "Couldn't save today's backup.";
      debugPrint('Automatic backup failed: $e');
    } finally {
      _autoRunning = false;
    }
    await _mutate(
      (r) => _setSettings(r, {
        if (error == null) _kAutoLastDay: today,
        _kAutoError: error,
      }),
    );
  }

  /// Replaces all data with the backup in [bytes]. When automatic backups
  /// are on, the current data is first saved to the backup folder, and the
  /// restore is abandoned if that fails. Throws [BackupFormatException] with
  /// a user-facing message.
  Future<void> restore(Uint8List bytes, [DateTime? now]) async {
    final repo = await _repo;
    final token = state.value?.autoBackup?.folderToken;
    if (token != null) {
      try {
        await _folder.write(
          token,
          preRestoreFileName(now ?? DateTime.now()),
          await repo.snapshot(),
        );
      } catch (e) {
        debugPrint('Pre-restore copy failed: $e');
        throw const BackupFormatException(
          "Couldn't save a copy of your current data to the backup folder, "
          'so nothing was restored.',
        );
      }
    }
    await _mutate((r) => r.restore(bytes, keepSettings: deviceSettings));
  }
}

final appDataProvider = AsyncNotifierProvider<AppDataNotifier, AppData>(
  AppDataNotifier.new,
);

/// Hiding or deleting would leave no type to log a meal with.
class LastMealTypeException implements Exception {
  const LastMealTypeException();
  @override
  String toString() => 'Keep at least one meal type visible.';
}

/// Hiding or deleting would leave no unit to pick.
class LastUnitException implements Exception {
  const LastUnitException();
  @override
  String toString() => 'Keep at least one unit visible.';
}
