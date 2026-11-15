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
    // Every widget's own layouts, plus the list rows the Meals widget
    // inflates in code (widget_*.xml).
    final layouts = <String>{};
    for (final info
        in Directory('android/app/src/main/res/xml')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_widget_info.xml'))) {
      layouts.addAll(
        RegExp(r'@layout/(\w+)')
            .allMatches(info.readAsStringSync())
            .map((m) => m.group(1)!),
      );
    }
    expect(layouts, containsAll(['helpings_widget', 'helpings_meals_widget']));
    layouts.addAll(
      Directory('android/app/src/main/res/layout')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('widget_') && n.endsWith('.xml'))
          .map((n) => n.substring(0, n.length - 4)),
    );
    expect(layouts, containsAll(['widget_meal_header', 'widget_meal_item']));

    for (final name in layouts) {
      final xml = File('android/app/src/main/res/layout/$name.xml')
          .readAsStringSync()
          .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final tags = RegExp(r'<([A-Za-z][\w.]*)')
          .allMatches(xml)
          .map((m) => m.group(1)!)
          .toSet();
      expect(
        tags.difference(_remoteViewsClasses),
        isEmpty,
        reason: '$name.xml uses views a widget can’t show',
      );
    }
  });
}
