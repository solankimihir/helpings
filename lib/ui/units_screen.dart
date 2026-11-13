import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> openUnits(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const UnitsScreen()));

/// Settings → Units: add your own (Scoop, Bowl…), hide, drag to reorder.
class UnitsScreen extends ConsumerWidget {
  const UnitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final units = data.units;
    final c = context.c;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  DecoratedBox(
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
                  const Spacer(),
                  Pill(
                    label: '+ Add',
                    style: PillStyle.primary,
                    onTap: () => showUnitSheet(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 2),
              child: Text('Units', style: serif(32, color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
              child: Text(
                'Tap to edit. Drag to change the order in unit pickers.',
                style: sans(13, color: c.inkA(.5)),
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                buildDefaultDragHandles: false,
                itemCount: units.length,
                onReorderItem: (from, to) {
                  final ids = [for (final u in units) u.id];
                  ids.insert(to, ids.removeAt(from));
                  ref.read(appDataProvider.notifier).reorderUnits(ids);
                },
                itemBuilder: (context, i) => Padding(
                  key: ValueKey(units[i].id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _UnitRow(
                    unit: units[i],
                    index: i,
                    isDefault: units[i] == data.defaultUnit,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.unit,
    required this.index,
    required this.isDefault,
  });
  final FoodUnit unit;
  final int index;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final details = [
      if (unit.isBuiltIn) 'built in',
      if (isDefault) 'default for new foods',
      if (!unit.active) 'hidden',
    ].join(' · ');
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
      onTap: () => showUnitSheet(context, editing: unit),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unit.name,
                  style: sans(
                    15.5,
                    weight: FontWeight.w600,
                    color: unit.active ? c.ink : c.inkA(.5),
                  ),
                ),
                if (details.isNotEmpty)
                  Text(details, style: sans(12.5, color: c.inkA(.45))),
              ],
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
                semanticLabel: 'Reorder ${unit.name}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Add or edit a unit. Resolves to the saved unit, or null if cancelled or
/// deleted.
Future<FoodUnit?> showUnitSheet(BuildContext context, {FoodUnit? editing}) {
  return showModalBottomSheet<FoodUnit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => UnitSheet(editing: editing),
  );
}

class UnitSheet extends ConsumerStatefulWidget {
  const UnitSheet({super.key, this.editing});
  final FoodUnit? editing;

  @override
  ConsumerState<UnitSheet> createState() => _UnitSheetState();
}

class _UnitSheetState extends ConsumerState<UnitSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late bool _active = widget.editing?.active ?? true;
  String _error = '';
  bool _saving = false;

  bool get _builtIn => widget.editing?.isBuiltIn ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the unit a name.');
      return;
    }
    final base = widget.editing;
    final unit = base == null
        ? FoodUnit(id: newId(), name: name)
        : base.copyWith(name: _builtIn ? base.name : name, active: _active);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(appDataProvider.notifier).saveUnit(unit);
      if (mounted) Navigator.pop(context, saved);
    } on DuplicateNameException catch (e) {
      _fail(e.toString());
    } on LastUnitException catch (e) {
      _fail(e.toString());
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  Future<void> _delete() async {
    final unit = widget.editing!;
    final notifier = ref.read(appDataProvider.notifier);
    final data = ref.read(appDataProvider).requireValue;
    if (data.visibleUnits.every((u) => u.id == unit.id)) {
      setState(() => _error = const LastUnitException().toString());
      return;
    }
    final uses = await notifier.unitUsageCount(unit.id);
    if (!mounted) return;
    if (uses > 0) {
      setState(
        () => _error =
            '${plural(uses, 'food or meal line', 'foods and meal lines')} '
            'use “${unit.name}”, so it can’t be deleted. Turn off '
            '“Show in unit pickers” to hide it instead.',
      );
      return;
    }
    final ok = await confirm(
      context,
      title: 'Delete “${unit.name}”?',
      message: 'Nothing uses it.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await notifier.deleteUnit(unit.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final editing = widget.editing;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListenableBuilder(
              listenable: _name,
              builder: (context, _) => SheetHeader(
                title: editing == null ? 'Add Unit' : 'Edit Unit',
                onCancel: () => Navigator.pop(context),
                onSave: _save,
                canSave: _name.text.trim().isNotEmpty,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Name'),
                  if (_builtIn)
                    Text(
                      editing!.name,
                      style: sans(16, weight: FontWeight.w500, color: c.ink),
                    )
                  else
                    AppTextField(
                      controller: _name,
                      hint: 'e.g. Scoop',
                      fontSize: 16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      autofocus: editing == null,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) {
                        if (_error.isNotEmpty) setState(() => _error = '');
                      },
                      onSubmitted: (_) => _save(),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _builtIn
                        ? 'Built-in units can be hidden but not renamed.'
                        : 'One of something, like “Scoop” or “Bowl”. '
                              'Renaming changes it everywhere it’s used.',
                    style: sans(12.5, color: c.inkA(.45), height: 1.5),
                  ),
                  if (editing != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show in unit pickers',
                                style: sans(
                                  15,
                                  weight: FontWeight.w500,
                                  color: c.ink,
                                ),
                              ),
                              Text(
                                'Hidden units stay on past meals and foods.',
                                style: sans(12.5, color: c.inkA(.45)),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ],
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoBanner.error(_error),
                  ],
                  if (editing != null && !_builtIn) ...[
                    const SizedBox(height: 18),
                    Center(
                      child: Pill(
                        label: 'Delete unit',
                        style: PillStyle.ghost,
                        color: c.danger,
                        fontSize: 14.5,
                        onTap: _delete,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
