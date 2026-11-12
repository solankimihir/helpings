import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> openCombos(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CombosScreen()));

/// Settings → Combos: rename, reorder, delete. Combos are created from the
/// Add Meal sheet ("Save as combo").
class CombosScreen extends ConsumerWidget {
  const CombosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final combos = data.combos;
    final c = context.c;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: softShadow(context),
                ),
                child: Tap(
                  onTap: () => Navigator.of(context).maybePop(),
                  color: c.surface,
                  semanticLabel: 'Back',
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 24,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
              child: Text('Combos', style: serif(32, color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text(
                'Tap to rename. Drag to change the order.',
                style: sans(13, color: c.inkA(.5)),
              ),
            ),
            Expanded(
              child: combos.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: DashedBox(
                        radius: 22,
                        fill: c.surface,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 30,
                        ),
                        child: Text(
                          'No combos yet. In Add Meal, add the items you '
                          'often eat together, then tap “☆ Save as combo”.',
                          textAlign: TextAlign.center,
                          style: sans(13.5, color: c.inkA(.5), height: 1.45),
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                      buildDefaultDragHandles: false,
                      itemCount: combos.length,
                      onReorderItem: (from, to) {
                        final ids = [for (final x in combos) x.id];
                        ids.insert(to, ids.removeAt(from));
                        ref.read(appDataProvider.notifier).reorderCombos(ids);
                      },
                      itemBuilder: (context, i) => Padding(
                        key: ValueKey(combos[i].id),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ComboRow(combo: combos[i], index: i),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComboRow extends ConsumerWidget {
  const _ComboRow({required this.combo, required this.index});
  final Combo combo;
  final int index;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptText(
      context,
      title: 'Rename combo',
      action: 'Save',
      initial: combo.name,
    );
    if (name == null || name == combo.name) return;
    try {
      await ref
          .read(appDataProvider.notifier)
          .saveCombo(combo.copyWith(name: name));
    } on DuplicateNameException catch (e) {
      if (context.mounted) toast(context, 'A combo named $e');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete “${combo.name}”?',
      message: 'Meals you already logged with it are kept.',
      action: 'Delete',
    );
    if (ok) await ref.read(appDataProvider.notifier).deleteCombo(combo.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final summary = [
      for (final e in combo.items) lineText(e.nameSnapshot, e.qty, e.unit),
    ].join(' · ');
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
      onTap: () => _rename(context, ref),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  combo.name,
                  style: sans(15.5, weight: FontWeight.w600, color: c.ink),
                ),
                Text(
                  '$summary · ${calLabel(MealTotals.of(combo.items))}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: c.inkA(.45)),
                ),
              ],
            ),
          ),
          Tap(
            onTap: () => _delete(context, ref),
            semanticLabel: 'Delete ${combo.name}',
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.delete_outline_rounded,
              size: 20,
              color: c.inkA(.4),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                Icons.drag_handle_rounded,
                size: 22,
                color: c.inkA(.35),
                semanticLabel: 'Reorder ${combo.name}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
