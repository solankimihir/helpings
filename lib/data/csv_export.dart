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
  return '${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

const healthCsvHeader = [
  'Date',
  'Time',
  'Type',
  'Value',
  'Unit',
  'Context',
  'Note',
];

/// Every health entry, oldest first, in canonical units (mg/dL, ml, kg) so
/// a file reads the same whatever the display settings.
String healthToCsv(AppData data) {
  final rows = <(String, List<String>)>[
    for (final s in data.sugar)
      (
        s.sortKey,
        [
          s.date,
          s.time,
          'Blood sugar',
          fmtNum(s.mgdl),
          'mg/dL',
          s.context.label,
          s.note,
        ],
      ),
    for (final w in data.water)
      (w.sortKey, [w.date, w.time, 'Water', fmtNum(w.ml), 'ml', '', '']),
    for (final w in data.weight)
      (w.sortKey, [w.date, w.time, 'Weight', fmtNum(w.kg), 'kg', '', w.note]),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final all = [healthCsvHeader, for (final r in rows) r.$2];
  return '${all.map((r) => r.map(csvCell).join(',')).join('\r\n')}\r\n';
}

/// Up to two decimals, without trailing zeros.
String fmtNum(double v) =>
    v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// One RFC 4180 field: quoted only when it has to be.
String csvCell(String v) =>
    v.contains(RegExp(r'[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// UTF-8 with a byte-order mark, so Excel reads non-ASCII names correctly.
Uint8List csvBytes(String csv) =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

/// e.g. `helpings-meals-2026-11-13.csv`
String csvFileName(DateTime t) => 'helpings-meals-${dayKey(t)}.csv';

/// e.g. `helpings-health-2026-11-13.csv`
String healthCsvFileName(DateTime t) => 'helpings-health-${dayKey(t)}.csv';

/// Opens the system "Save as" dialog. Returns false if cancelled.
/// Overridden in tests.
final csvSaverProvider =
    Provider<Future<bool> Function(String fileName, Uint8List bytes)>(
      (ref) =>
          (fileName, bytes) async =>
              await FilePicker.saveFile(
                dialogTitle: 'Export CSV',
                fileName: fileName,
                bytes: bytes,
                mimeType: 'text/csv',
              ) !=
              null,
    );
