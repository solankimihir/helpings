import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands [bytes] to the user to keep. Returns false if they cancelled.
typedef BackupSaver = Future<bool> Function(String fileName, Uint8List bytes);

/// Opens the system "Save as" dialog (Storage Access Framework on Android,
/// the Files export sheet on iOS). Overridden in tests.
final backupSaverProvider = Provider<BackupSaver>(
  (ref) =>
      (fileName, bytes) async =>
          await FilePicker.saveFile(
            dialogTitle: 'Save Helpings backup',
            fileName: fileName,
            bytes: bytes,
          ) !=
          null,
);

/// e.g. `helpings-backup-2026-11-12-1405.db`
String backupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'helpings-backup-${t.year}-${two(t.month)}-${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}.db';
}

/// Lets the user choose a backup file to restore. Null if they cancelled.
/// Overridden in tests.
final backupPickerProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => () async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choose a Helpings backup',
    );
    return f?.readAsBytes();
  },
);

/// How many daily automatic backups to keep in the backup folder.
const autoBackupKeep = 30;

final _autoName = RegExp(r'^helpings-auto-\d{4}-\d{2}-\d{2}\.db$');

/// e.g. `helpings-auto-2026-11-13.db` — one per day, so a second run on the
/// same day overwrites rather than piling up.
String autoBackupFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'helpings-auto-${t.year}-${two(t.month)}-${two(t.day)}.db';
}

/// Written to the backup folder just before a restore replaces the data.
String preRestoreFileName(DateTime t) =>
    backupFileName(t)
        .replaceFirst('helpings-backup-', 'helpings-before-restore-');

/// Automatic backups in [names] beyond the newest [keep]. Files that don't
/// match the automatic naming pattern (manual copies, anything else the user
/// put there) are never selected.
List<String> autoBackupsToPrune(
  Iterable<String> names, {
  int keep = autoBackupKeep,
}) {
  final auto = names.where(_autoName.hasMatch).toList()
    ..sort((a, b) => b.compareTo(a)); // ISO dates sort lexically, newest first
  return auto.skip(keep).toList();
}
