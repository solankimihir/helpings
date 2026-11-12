import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A folder the user picked once, which the app may keep writing to.
///
/// On Android the [token] is a Storage Access Framework tree URI with a
/// persisted permission; on iOS it is a base64 security-scoped bookmark.
/// Either way it is opaque to Dart: store it, hand it back.
class PickedFolder {
  const PickedFolder({required this.token, required this.name});
  final String token;

  /// What the user sees, e.g. "Helpings backups".
  final String name;
}

/// The app lost access to the folder (deleted, moved, or permission revoked).
class FolderAccessException implements Exception {
  const FolderAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class BackupFolder {
  /// Shows the system folder picker. Null if the user cancelled.
  Future<PickedFolder?> pick();

  /// Current display name, or throws [FolderAccessException].
  Future<String> name(String token);

  /// Creates or overwrites [fileName] in the folder.
  Future<void> write(String token, String fileName, Uint8List bytes);

  /// File names directly inside the folder.
  Future<List<String>> list(String token);

  Future<void> delete(String token, String fileName);

  /// Gives up the app's access to the folder. Best effort.
  Future<void> release(String token);
}

/// Talks to `BackupFolderChannel` in MainActivity.kt / AppDelegate.swift.
class NativeBackupFolder implements BackupFolder {
  static const _ch = MethodChannel('helpings/backup_folder');

  Future<T> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return (await _ch.invokeMethod<T>(method, args)) as T;
    } on PlatformException catch (e) {
      if (e.code == 'no_access') {
        throw FolderAccessException(
          e.message ?? "Helpings can't reach the backup folder any more.",
        );
      }
      rethrow;
    }
  }

  @override
  Future<PickedFolder?> pick() async {
    final r = await _call<Map<Object?, Object?>?>('pick');
    if (r == null) return null;
    return PickedFolder(
      token: r['token']! as String,
      name: r['name']! as String,
    );
  }

  @override
  Future<String> name(String token) => _call<String>('name', {'token': token});

  @override
  Future<void> write(String token, String fileName, Uint8List bytes) =>
      _call<void>('write', {'token': token, 'name': fileName, 'bytes': bytes});

  @override
  Future<List<String>> list(String token) async =>
      (await _call<List<Object?>>('list', {'token': token})).cast<String>();

  @override
  Future<void> delete(String token, String fileName) =>
      _call<void>('delete', {'token': token, 'name': fileName});

  @override
  Future<void> release(String token) =>
      _call<void>('release', {'token': token});
}

/// Overridden in tests with an in-memory fake.
final backupFolderProvider = Provider<BackupFolder>(
  (ref) => NativeBackupFolder(),
);
