import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'meal_sheet.dart';
import 'widgets/common.dart';
import 'widgets/tab_icons.dart';

enum AppTab {
  home('Home', TabGlyph.home),
  history('History', TabGlyph.history),
  items('Meal Items', TabGlyph.items),
  settings('Settings', TabGlyph.settings);

  const AppTab(this.label, this.glyph);
  final String label;
  final TabGlyph glyph;
}

final currentTabProvider = NotifierProvider<CurrentTab, AppTab>(CurrentTab.new);

class CurrentTab extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.home;
  void select(AppTab t) => state = t;
}

/// Bottom space screens reserve so content clears the tab bar + Add button.
double shellBottomInset(BuildContext context) =>
    130 + MediaQuery.paddingOf(context).bottom;

class Shell extends ConsumerWidget {
  const Shell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(currentTabProvider);
    final data = ref.watch(appDataProvider);
    final c = context.c;

    final body = switch (data) {
      AsyncData() => IndexedStack(
        index: tab.index,
        children: const [
          HomeScreen(),
          _Placeholder('History'),
          _Placeholder('Meal Items'),
          _Placeholder('Settings'),
        ],
      ),
      AsyncError(:final error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not open your meal log.\n$error',
            textAlign: TextAlign.center,
            style: sans(14, color: c.inkA(.6)),
          ),
        ),
      ),
      _ => const SizedBox.shrink(),
    };

    final showQuickAdd = tab == AppTab.home || tab == AppTab.history;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showQuickAdd && data.hasValue)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: _AddMealButton(onTap: () => showMealSheet(context)),
                  ),
                _TabBar(
                  current: tab,
                  onSelect: (t) =>
                      ref.read(currentTabProvider.notifier).select(t),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddMealButton extends StatelessWidget {
  const _AddMealButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: .35),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Tap(
        onTap: onTap,
        color: c.primary,
        padding: const EdgeInsets.all(16),
        semanticLabel: 'Add meal',
        child: SizedBox(
          width: double.infinity,
          child: Text(
            '+ Add Meal',
            textAlign: TextAlign.center,
            style: sans(
              16,
              weight: FontWeight.w700,
              color: c.onPrimary,
              letterSpacing: -.16,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});
  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: c.bg.withValues(alpha: .92),
            border: Border(top: BorderSide(color: c.inkA(.08))),
          ),
          padding: EdgeInsets.fromLTRB(6, 8, 6, bottom > 0 ? bottom : 12),
          child: Row(
            children: [
              for (final t in AppTab.values)
                Expanded(
                  child: Semantics(
                    selected: t == current,
                    button: true,
                    label: t.label,
                    excludeSemantics: true,
                    child: Tap(
                      onTap: () => onSelect(t),
                      radius: 14,
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 2,
                      ),
                      child: Builder(
                        builder: (context) {
                          final col = t == current ? c.tabActive : c.inkA(.42);
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Center(
                                  child: TabIcon(t.glyph, color: col),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                t.label,
                                style: sans(
                                  10.5,
                                  weight: FontWeight.w500,
                                  color: col,
                                  letterSpacing: .1,
                                ),
                              ),
                            ],
                          );
                        },
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

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
      child: Text(title, style: serif(32, color: context.c.ink)),
    ),
  );
}
