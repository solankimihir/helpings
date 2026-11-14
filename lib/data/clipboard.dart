import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Copy and paste text. Overridden in tests.
abstract class ClipboardIO {
  Future<void> copy(String text);

  /// The clipboard's text, or null if it holds none.
  Future<String?> paste();
}

class SystemClipboard implements ClipboardIO {
  const SystemClipboard();

  @override
  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> paste() async =>
      (await Clipboard.getData(Clipboard.kTextPlain))?.text;
}

final clipboardProvider = Provider<ClipboardIO>(
  (ref) => const SystemClipboard(),
);

/// Lets the user choose a CSV (or text) file and returns its text. Null if
/// they cancelled. Overridden in tests.
final foodCsvPickerProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final f = await FilePicker.pickFile(dialogTitle: 'Choose a food list');
    if (f == null) return null;
    return utf8.decode(await f.readAsBytes(), allowMalformed: true);
  },
);
