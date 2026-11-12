import 'package:material_ui/material_ui.dart';

import 'theme/app_theme.dart';

class HelpingsApp extends StatelessWidget {
  const HelpingsApp({super.key, this.home});

  /// Overridable for tests.
  final Widget? home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helpings',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: home ?? const Scaffold(body: Center(child: Text('Helpings'))),
    );
  }
}
