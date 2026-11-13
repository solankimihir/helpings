import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_state.dart';
import 'format.dart';

const csvHeader = [
  'Date',
  'Time',
  'Meal type',
  'Item',
  'Quantity',
  'Unit',
  'Calories',
  'Notes',
];

/// Every meal as spreadsheet rows, oldest first: one row per logged line,
/// or one row with a blank item for a meal with no lines. Uses the current
/// meal type names and food names, RFC 4180 quoting and CRLF line endings.
String mealsToCsv(AppData data) {
  final rows = <List<String>>[csvHeader];
  for (final m in data.meals) {
    final type = data.typeName(m);
    if (m.entries.isEmpty) {
      rows.add([m.date, m.time, type, '', '', '', '', m.notes]);
      continue;
    }
    for (final e in m.entries) {
      rows.add([
        m.date,
        m.time,
        type,
        data.displayName(e),
        fmtQty(e.qty),
        e.unit?.label ?? '',
        fmtQty(e.calories),
        m.notes,
      ]);
    }
  }
  return '${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n';
}

String _cell(String v) =>
    v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// UTF-8 with a byte-order mark, so Excel reads non-ASCII names correctly.
Uint8List csvBytes(String csv) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

/// e.g. `helpings-meals-2026-11-13.csv`
String csvFileName(DateTime t) => 'helpings-meals-${dayKey(t)}.csv';

/// Opens the system "Save as" dialog. Returns false if cancelled.
/// Overridden in tests.
final csvSaverProvider =
    Provider<Future<bool> Function(String fileName, Uint8List bytes)>(
      (ref) =>
          (fileName, bytes) async =>
              await FilePicker.saveFile(
                dialogTitle: 'Export meals',
                fileName: fileName,
                bytes: bytes,
                mimeType: 'text/csv',
              ) !=
              null,
    );
