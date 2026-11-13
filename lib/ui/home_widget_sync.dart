import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/home_widget_data.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'meal_sheet.dart';
import 'shell.dart';

/// Keeps the home-screen widget showing today's totals, and opens Add Meal
/// when its "+ Add meal" button is tapped.
class HomeWidgetSync extends ConsumerStatefulWidget {
  const HomeWidgetSync({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync>
    with WidgetsBindingObserver {
  late final HomeWidgetBridge _bridge = ref.read(homeWidgetBridgeProvider);
  StreamSubscription<Uri?>? _clicks;
  WidgetPayload? _published;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clicks = _bridge.clicks.listen(_handle);
    _start();
  }

  Future<void> _start() async {
    try {
      await _publish(await ref.read(appDataProvider.future));
      _handle(await _bridge.launchUri());
    } catch (e) {
      debugPrint('Home widget setup failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clicks?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back after midnight: today's totals start again from zero.
    final data = ref.read(appDataProvider).value;
    if (state == AppLifecycleState.resumed && data != null) _publish(data);
  }

  Future<void> _publish(AppData data) async {
    final p = WidgetPayload.of(data, DateTime.now());
    if (p == _published) return;
    _published = p;
    try {
      await _bridge.publish(p);
    } catch (e) {
      debugPrint('Updating the home widget failed: $e');
    }
  }

  void _handle(Uri? uri) {
    if (uri == null || !mounted) return;
    ref.read(currentTabProvider.notifier).select(AppTab.home);
    ref.read(homeDayProvider.notifier).show(0);
    if (uri.host == widgetAddMealUri.host) showMealSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appDataProvider, (_, next) {
      final data = next.value;
      if (data != null) _publish(data);
    });
    return widget.child;
  }
}
