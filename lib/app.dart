import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'ui/auto_backup_runner.dart';
import 'ui/shell.dart';

class HelpingsApp extends ConsumerWidget {
  const HelpingsApp({super.key, this.home});

  /// Overridable for tests.
  final Widget? home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Follow the device until the saved preference has loaded.
    final themeMode = ref.watch(
      appDataProvider.select((d) => d.value?.themeMode ?? ThemeMode.system),
    );
    return MaterialApp(
      title: 'Helpings',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      home: AutoBackupRunner(child: home ?? const Shell()),
    );
  }
}
