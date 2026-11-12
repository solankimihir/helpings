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
  AppData({
    required this.items,
    required this.meals,
    required this.defaultUnit,
    this.themeMode = ThemeMode.system,
    this.lastBackupAt,
    this.autoBackup,
  }) : _byId = {for (final i in items) i.id: i};

  final List<FoodItem> items;

  /// Oldest first.
  final List<Meal> meals;
  final FoodUnit defaultUnit;

  /// Light, dark, or follow the device.
  final ThemeMode themeMode;

  /// When the user last saved a backup file, if ever.
  final DateTime? lastBackupAt;

  /// Null when automatic backups are off.
  final AutoBackupStatus? autoBackup;
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

/// Settings that describe this device rather than the user's data, so a
/// restore from another phone (or an old file) must not overwrite them.
const deviceSettings = {
  _kLastBackup,
  _kAutoFolder,
  _kAutoFolderName,
  _kAutoLastDay,
  _kAutoError,
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
    ]);
    final settings = results[2] as Map<String, String?>;
    final folder = settings[_kAutoFolder];
    return AppData(
      items: results[0] as List<FoodItem>,
      meals: results[1] as List<Meal>,
      defaultUnit: FoodUnit.tryParse(settings[_kDefaultUnit]) ?? FoodUnit.piece,
      themeMode: _parseThemeMode(settings[_kThemeMode]),
      lastBackupAt: DateTime.tryParse(settings[_kLastBackup] ?? ''),
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
