import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/version.dart';

void main() {
  test('appVersion and appBuild match pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.trim(), 'version: $appVersion+$appBuild');
  });
}
