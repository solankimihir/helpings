// Generates the Google Play listing images from the real app.
//
//   flutter test tool/store_screenshots
//
// Writes android/fastlane/metadata/android/en-US/images/phoneScreenshots/*.png
// (1080×1920) and featureGraphic.png (1024×500). Each screenshot is the app
// rendered at phone size with seeded sample data, placed in a phone frame
// under a headline. Kept out of test/ so the normal suite doesn't run it.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helpings/data/format.dart';
import 'package:helpings/data/models.dart';
import 'package:helpings/data/repository.dart';
import 'package:helpings/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../../test/helpers.dart';

const _out = '../../android/fastlane/metadata/android/en-US/images';

// The phone the app is rendered on, in logical pixels.
const _phone = Size(400, 893);
const _phoneDpr = 3.0;
const _statusBar = 28.0;
const _gestureBar = 20.0;

Future<void> _loadFonts() async {
  // flutter test sets FLUTTER_ROOT; Material's icon and Roboto fonts ship
  // with the SDK.
  final material =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> font(String family, List<String> paths) async {
    final l = FontLoader(family);
    for (final p in paths) {
      l.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
    }
    await l.load();
  }

  await font('Lexend', ['assets/fonts/Lexend.ttf']);
  await font('DMSerifDisplay', ['assets/fonts/DMSerifDisplay-Regular.ttf']);
  await font('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await font('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold']) '$material/Roboto-$w.ttf',
  ]);
}

// ---- Sample data ------------------------------------------------------------

Future<void> _seed(Repository r) async {
  final items = {for (final i in await r.items()) i.name: i};
  var n = 0;
  MealEntry line(String name, double qty, double? cal) {
    final item = items[name]!;
    return MealEntry(
      id: 'e${n++}',
      itemId: item.id,
      nameSnapshot: name,
      qty: qty,
      unit: item.defaultUnit,
      calories: cal,
    );
  }

  Future<void> meal(
    String type,
    int daysAgo,
    String time,
    List<MealEntry> lines,
  ) => r.saveMeal(
    Meal(
      id: 'm${n++}',
      typeId: type,
      date: shiftKey(-daysAgo),
      time: time,
      entries: lines,
    ),
  );

  // Today, as on the Home screenshot.
  await meal('breakfast', 0, '08:30', [
    line('Idli', 2, 120),
    line('Sambar', 1, null),
    line('Tea', 1, 90),
  ]);
  await meal('lunch', 0, '13:15', [
    line('Roti', 2, 200),
    line('Dal', 1, 180),
    line('Bhindi', 1, 120),
  ]);
  await meal('snack', 0, '17:40', [line('Tea', 1, 90)]);

  // The two weeks before: varied, so Trends and History look lived-in.
  for (var d = 1; d <= 14; d++) {
    await meal(
      'breakfast',
      d,
      '08:${10 + d % 4 * 10}',
      d.isEven
          ? [line('Poha', 1, 250), line('Tea', 1, 90)]
          : [line('Idli', 3, 180), line('Sambar', 1, 140), line('Tea', 1, 90)],
    );
    await meal('lunch', d, '13:${d % 3 * 15 + 5}', [
      line('Roti', d % 3 == 0 ? 3 : 2, d % 3 == 0 ? 300 : 200),
      line('Dal', 1, 180),
      if (d % 2 == 0) line('Rice', 1, 200) else line('Bhindi', 1, 120),
    ]);
    if (d % 3 != 1) {
      await meal('snack', d, '17:30', [
        line('Tea', 1, 90),
        if (d % 4 == 0) line('Bread Pakora', 1, 280),
        if (d % 4 == 2) line('Vada Pav', 1, 300),
      ]);
    }
    if (d % 5 != 2) {
      await meal('dinner', d, '20:${d % 4 * 10 + 5}', [
        line('Roti', 2, 200),
        line('Dal', 1, 180),
        if (d.isOdd) line('Curd', 1, 90),
      ]);
    }
  }

  // Combos.
  for (final (name, lines) in [
    (
      'Usual breakfast',
      [line('Idli', 2, 120), line('Sambar', 1, null), line('Tea', 1, 90)],
    ),
    (
      'Roti-dal thali',
      [line('Roti', 2, 200), line('Dal', 1, 180), line('Rice', 1, 200)],
    ),
    ('Evening chai', [line('Tea', 1, 90), line('Bread Pakora', 1, 280)]),
  ]) {
    await r.saveCombo(Combo(id: 'c${n++}', name: name, items: lines));
  }

  // Meal types: a custom one, and reminders.
  final types = {for (final t in await r.mealTypes()) t.id: t};
  for (final (id, remind) in [
    ('breakfast', 9 * 60 + 30),
    ('lunch', 13 * 60 + 30),
    ('dinner', 20 * 60 + 30),
  ]) {
    await r.saveMealType(types[id]!.copyWith(remindMinute: () => remind));
  }
  await r.saveMealType(
    const MealType(
      id: 'preworkout',
      name: 'Pre-workout',
      startMinute: 6 * 60 + 30,
      remindMinute: 6 * 60 + 45,
    ),
  );
  await r.reorderMealTypes([
    'preworkout',
    'breakfast',
    'lunch',
    'snack',
    'dinner',
    'other',
  ]);

  // Settings: reminders and daily backup on, already backed up today.
  await r.setSetting('reminders_on', '1');
  await r.setSetting('auto_backup_folder', 'sample');
  await r.setSetting('auto_backup_folder_name', 'Helpings backups');
  await r.setSetting('auto_backup_last_day', todayKey());
  await r.setSetting(
    'last_backup_at',
    DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
  );
}

// ---- Capture ----------------------------------------------------------------

/// Pumps the app on a phone-sized screen, runs [show] to reach the scene,
/// and returns what the phone shows.
Future<ui.Image> _capture(
  WidgetTester tester, {
  required Future<void> Function() show,
  bool dark = false,
}) async {
  tester.view.physicalSize = _phone * _phoneDpr;
  tester.view.devicePixelRatio = _phoneDpr;
  tester.view.padding = const FakeViewPadding(
    top: _statusBar * _phoneDpr,
    bottom: _gestureBar * _phoneDpr,
  );
  tester.platformDispatcher.platformBrightnessTestValue = dark
      ? Brightness.dark
      : Brightness.light;
  // pumpApp supplies fakes for reminders and the home-screen widget.
  await pumpApp(tester, seed: _seed);
  await show();
  await tester.pumpAndSettle();
  final image = await tester.runAsync(
    () => captureImage(tester.element(find.byType(MaterialApp))),
  );
  // Start the next scene from a clean slate.
  await tester.pumpWidget(const SizedBox());
  tester.platformDispatcher.clearPlatformBrightnessTestValue();
  return image!;
}

// ---- Composition ------------------------------------------------------------

const _light = AppColors.light;

TextStyle _serif(double size, Color color) => TextStyle(
  fontFamily: 'DMSerifDisplay',
  fontSize: size,
  height: 1.0,
  color: color,
);

TextStyle _sans(double size, Color color, [FontWeight w = FontWeight.w400]) =>
    TextStyle(
      fontFamily: 'Lexend',
      fontSize: size,
      color: color,
      fontWeight: w,
    );

/// The phone frame around a captured screen, [width] wide.
class _Phone extends StatelessWidget {
  const _Phone({required this.screen, required this.width, this.dark = false});
  final ui.Image screen;
  final double width;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    const bezel = 14.0;
    final inner = width - bezel * 2;
    final scale = inner / _phone.width;
    final ink = dark ? const Color(0xFFE9EDE9) : _light.ink;
    return Container(
      width: width,
      padding: const EdgeInsets.all(bezel),
      decoration: BoxDecoration(
        color: const Color(0xFF17201C),
        borderRadius: BorderRadius.circular(width * .105),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(width * .085),
        child: SizedBox(
          width: inner,
          height: _phone.height * scale,
          child: Stack(
            children: [
              Positioned.fill(
                child: RawImage(image: screen, fit: BoxFit.fill),
              ),
              // Status bar.
              Positioned(
                left: 26 * scale,
                right: 22 * scale,
                top: 8 * scale,
                child: Row(
                  children: [
                    Text('9:41', style: _sans(13 * scale, ink)),
                    const Spacer(),
                    Icon(Icons.wifi_rounded, size: 15 * scale, color: ink),
                    SizedBox(width: 4 * scale),
                    Icon(
                      Icons.battery_full_rounded,
                      size: 15 * scale,
                      color: ink,
                    ),
                  ],
                ),
              ),
              // Gesture bar.
              Positioned(
                bottom: 7 * scale,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 100 * scale,
                    height: 4 * scale,
                    decoration: BoxDecoration(
                      color: ink.withValues(alpha: .7),
                      borderRadius: BorderRadius.circular(4 * scale),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 1080×1920 listing screenshot: two-line headline, subtitle, phone.
class _Shot extends StatelessWidget {
  const _Shot({
    required this.line1,
    required this.line2,
    required this.subtitle,
    required this.screen,
    this.dark = false,
  });
  final String line1;
  final String line2;
  final String subtitle;
  final ui.Image screen;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1080,
      height: 1920,
      color: _light.bg,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Soft green rise behind the phone.
          Positioned(
            left: -540,
            right: -540,
            top: 1240,
            height: 2200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _light.greenTint.withValues(alpha: .75),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 60,
            right: 60,
            top: 118,
            child: Column(
              children: [
                Text(line1, style: _serif(104, _light.ink)),
                const SizedBox(height: 4),
                Text(line2, style: _serif(104, _light.primary)),
                const SizedBox(height: 26),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: _sans(34, _light.ink.withValues(alpha: .62)),
                ),
              ],
            ),
          ),
          Positioned(
            top: 452,
            left: 0,
            right: 0,
            child: Center(
              child: _Phone(screen: screen, width: 670, dark: dark),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 1024×500 feature graphic: icon, name, tagline, and Home on a phone.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.screen, required this.icon});
  final ui.Image screen;
  final ui.Image icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1024,
      height: 500,
      color: _light.bg,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 560,
            top: -260,
            width: 1000,
            height: 1000,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _light.greenTint.withValues(alpha: .75),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: 70,
            top: 110,
            child: Container(
              width: 120,
              height: 120,
              // The icon's cream matches the background, so the tile needs a
              // soft all-round shadow and a hairline edge to stand out.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _light.ink.withValues(alpha: .06)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .09),
                    blurRadius: 30,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: RawImage(image: icon, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            left: 70,
            top: 262,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Helpings', style: _serif(104, _light.ink)),
                const SizedBox(height: 10),
                Text(
                  'A simple, exact meal tracker',
                  style: _sans(31, _light.ink.withValues(alpha: .65)),
                ),
              ],
            ),
          ),
          Positioned(
            left: 660,
            top: 60,
            child: _Phone(screen: screen, width: 330),
          ),
        ],
      ),
    );
  }
}

/// Lays out [child] at its exact pixel size and checks it against [path].
Future<void> _write(
  WidgetTester tester,
  Widget child,
  Size size,
  String path,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.resetPadding();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('out'),
            child: SizedBox.fromSize(size: size, child: child),
          ),
        ),
      ),
    ),
  );
  final image = await tester.runAsync(
    () => captureImage(tester.element(find.byKey(const ValueKey('out')))),
  );
  await tester.runAsync(() => _writeRgbPng(image!, path));
  image!.dispose();
}

/// Writes [image] as a 24-bit PNG (no alpha), which Google Play requires
/// for screenshots and the feature graphic. Every pixel here is opaque, so
/// dropping the alpha channel loses nothing.
Future<void> _writeRgbPng(ui.Image image, String path) async {
  final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
      .buffer
      .asUint8List();
  final w = image.width, h = image.height;
  // Each row: filter byte 0 (none), then RGB.
  final raw = Uint8List(h * (1 + w * 3));
  var o = 0;
  for (var y = 0; y < h; y++) {
    raw[o++] = 0;
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
    }
  }
  final header = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 2); // colour type 2: RGB
  final out = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibEncoder(level: 9).convert(raw)))
    ..add(_chunk('IEND', Uint8List(0)));
  // flutter test runs from the project root; [path] is relative to this
  // file's folder.
  final target = File('tool/store_screenshots/$path');
  await target.parent.create(recursive: true);
  await target.writeAsBytes(out.takeBytes());
}

List<int> _chunk(String type, List<int> data) {
  final typeBytes = type.codeUnits;
  final len = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32([...typeBytes, ...data]));
  return [
    ...len.buffer.asUint8List(),
    ...typeBytes,
    ...data,
    ...crc.buffer.asUint8List(),
  ];
}

final _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

// ---- Scenes -----------------------------------------------------------------

void main() {
  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('store screenshots', (tester) async {
    addTearDown(tester.view.reset);
    await tester.runAsync(_loadFonts);

    // 1. Home.
    final home = await _capture(tester, show: () async {});
    await _write(
      tester,
      _Shot(
        line1: 'Log a meal in',
        line2: 'ten seconds',
        subtitle: 'Today’s calories and meals at a glance',
        screen: home,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/1_home.png',
    );

    // 2. Add Meal: combos and "same as yesterday".
    final add = await _capture(
      tester,
      show: () async {
        await tap(tester, find.text('+ Add Meal'));
        await tap(
          tester,
          find.descendant(
            of: find.byType(Wrap).first,
            matching: find.text('Lunch'),
          ),
        );
      },
    );
    await _write(
      tester,
      _Shot(
        line1: 'Your usual meals,',
        line2: 'one tap away',
        subtitle: 'Save combos, or repeat yesterday’s meal',
        screen: add,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/2_add.png',
    );

    // 3. Trends, in dark mode.
    final trends = await _capture(
      tester,
      dark: true,
      show: () async {
        await tap(tester, find.text('History'));
        await tap(tester, find.text('Trends'));
        // Early in the week, show the full week before.
        if (DateTime.now().weekday <= DateTime.wednesday) {
          await tap(tester, find.bySemanticsLabel('Previous week'));
        }
        final bars = find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('bar-'),
        );
        await tap(tester, bars.at(bars.evaluate().length ~/ 2));
      },
    );
    await _write(
      tester,
      _Shot(
        line1: 'See your week',
        line2: 'at a glance',
        subtitle: 'Daily calories, averages and favourite foods',
        screen: trends,
        dark: true,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/3_trends.png',
    );

    // 4. History.
    final history = await _capture(
      tester,
      show: () => tap(tester, find.text('History')),
    );
    await _write(
      tester,
      _Shot(
        line1: 'Look back on',
        line2: 'any day',
        subtitle: 'Meals grouped by day, with daily totals',
        screen: history,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/4_history.png',
    );

    // 5. Meal types and reminders.
    final types = await _capture(
      tester,
      show: () async {
        await tap(tester, find.text('Settings'));
        await tap(tester, find.text('Meal types'));
      },
    );
    await _write(
      tester,
      _Shot(
        line1: 'Your meals,',
        line2: 'your way',
        subtitle: 'Custom meal types, with gentle reminders',
        screen: types,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/5_meal_types.png',
    );

    // 6. Backup.
    final backup = await _capture(
      tester,
      show: () async {
        await tap(tester, find.text('Settings'));
        // Bring the Backup card to just under the title.
        final list = find.byType(Scrollable).last;
        await tester.scrollUntilVisible(
          find.text('Save copy'),
          200,
          scrollable: list,
        );
        final top = tester.getTopLeft(list).dy;
        final card = tester.getTopLeft(find.text('Save copy')).dy;
        await tester.drag(list, Offset(0, -(card - top - 36)));
        await tester.pumpAndSettle();
      },
    );
    await _write(
      tester,
      _Shot(
        line1: 'Your data',
        line2: 'stays yours',
        subtitle: 'Daily backups, restore and CSV export',
        screen: backup,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/6_backup.png',
    );

    // 7. Food list.
    final items = await _capture(
      tester,
      show: () => tap(tester, find.text('Meal Items')),
    );
    await _write(
      tester,
      _Shot(
        line1: 'Exact calories,',
        line2: 'never guessed',
        subtitle: 'Your own foods, with default calories and units',
        screen: items,
      ),
      const Size(1080, 1920),
      '$_out/phoneScreenshots/7_items.png',
    );

    // Feature graphic.
    final icon = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        File('assets/icon/icon.png').readAsBytesSync(),
      );
      return (await codec.getNextFrame()).image;
    });
    await _write(
      tester,
      _FeatureGraphic(screen: home, icon: icon!),
      const Size(1024, 500),
      '$_out/featureGraphic.png',
    );
  });
}
