import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// View classes a home-screen widget (RemoteViews) may inflate. Anything
/// else fails at runtime with "Can't load widget" — e.g. `Space`.
/// https://developer.android.com/develop/ui/views/appwidgets/build#layouts
const _remoteViewsClasses = {
  'FrameLayout',
  'LinearLayout',
  'RelativeLayout',
  'GridLayout',
  'AnalogClock',
  'Button',
  'Chronometer',
  'ImageButton',
  'ImageView',
  'ProgressBar',
  'TextView',
  'TextClock',
  'ViewFlipper',
  'ListView',
  'GridView',
  'StackView',
  'AdapterViewFlipper',
  'CheckBox',
  'RadioButton',
  'RadioGroup',
  'Switch',
};

void main() {
  test('widget layouts only use views RemoteViews can inflate', () {
    final info = File(
      'android/app/src/main/res/xml/helpings_widget_info.xml',
    ).readAsStringSync();
    final layouts = RegExp(
      r'@layout/(\w+)',
    ).allMatches(info).map((m) => m.group(1)!).toSet();
    expect(layouts, isNotEmpty);

    for (final name in layouts) {
      final xml = File(
        'android/app/src/main/res/layout/$name.xml',
      ).readAsStringSync().replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final tags = RegExp(
        r'<([A-Za-z][\w.]*)',
      ).allMatches(xml).map((m) => m.group(1)!).toSet();
      expect(
        tags.difference(_remoteViewsClasses),
        isEmpty,
        reason: '$name.xml uses views a widget can’t show',
      );
    }
  });
}
