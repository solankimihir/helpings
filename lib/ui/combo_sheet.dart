import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'item_sheet.dart';
import 'widgets/common.dart';
import 'widgets/line_editor.dart';

/// Create a combo, or edit [editing]'s name and items. Resolves to the saved
/// combo, or null if cancelled or deleted.
Future<Combo?> showComboSheet(BuildContext context, {Combo? editing}) {
  return showModalBottomSheet<Combo>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // Sits above the keyboard, like the meal sheet, so fields scroll into
    // view rather than hiding behind it.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: FractionallySizedBox(
        heightFactor: .92,
        child: ComboSheet(editing: editing),
      ),
    ),
  );
}

class ComboSheet extends ConsumerStatefulWidget {
  const ComboSheet({super.key, this.editing});
  final Combo? editing;

  @override
  ConsumerState<ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends ConsumerState<ComboSheet> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  final _search = TextEditingController();
  final _rows = <DraftLine>[];
  final _pickKey = GlobalKey();
  String _error = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final data = ref.read(appDataProvider).requireValue;
    for (final e in widget.editing?.items ?? const <MealEntry>[]) {
      _rows.add(draftFromEntry(e, data));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _add(FoodItem item, FoodUnit fallbackUnit) {
    setState(() {
      _error = '';
      _search.clear();
      _rows.add(draftFromItem(item, fallbackUnit));
    });
    _revealPicker();
  }

  /// Keeps the search box in view as added items push it down.
  void _revealPicker() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _pickKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _remove(DraftLine r) {
    setState(() => _rows.remove(r));
    r.dispose();
  }

  Future<void> _createFromSearch(FoodUnit fallbackUnit) async {
    final created = await showItemSheet(
      context,
      presetName: _search.text.trim(),
    );
    if (created != null && mounted) _add(created, fallbackUnit);
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the combo a name.');
      return;
    }
    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one item to the combo.');
      return;
    }
    final lines = draftsToEntries(_rows);
    if (lines.error != null) {
      setState(() => _error = lines.error!);
      return;
    }
    final base = widget.editing;
    final combo = base == null
        ? Combo(id: newId(), name: name, items: lines.entries!)
        : base.copyWith(name: name, items: lines.entries);
    setState(() => _saving = true);
    try {
      final saved = await ref.read(appDataProvider.notifier).saveCombo(combo);
      if (mounted) Navigator.pop(context, saved);
    } on DuplicateNameException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'A combo named $e';
        });
      }
    }
  }

  Future<void> _delete() async {
    final combo = widget.editing!;
    final ok = await confirm(
      context,
      title: 'Delete “${combo.name}”?',
      message: 'Meals you already logged with it are kept.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    await ref.read(appDataProvider.notifier).deleteCombo(combo.id);
    nav.pop();
  }

  /// Calories for [r] from its food's current default; null if the food is
  /// gone, has no default, or the line is in another unit.
  double? _calories(DraftLine r, AppData data) {
    final item = data.itemById(r.itemId);
    if (item == null) return null;
    final q = r.qty.text.trim();
    return itemCalories(item, q.isEmpty ? null : parseNum(q), r.unit);
  }

  String _caloriesText(DraftLine r, AppData data) {
    final cal = _calories(r, data);
    if (cal != null) return '${fmtN(cal)} kcal';
    final item = data.itemById(r.itemId);
    if (item?.defaultCalories != null && item?.defaultUnit != null) {
      return 'Default is per ${item!.defaultUnit!.label.toLowerCase()}';
    }
    return 'No default';
  }

  MealTotals _total(AppData data) => MealTotals.of([
    for (final r in _rows)
      MealEntry(id: r.rid, nameSnapshot: r.name, calories: _calories(r, data)),
  ]);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = ref.watch(appDataProvider).requireValue;
    final editing = widget.editing;

    return Column(
      children: [
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => SheetHeader(
            title: editing == null ? 'New Combo' : 'Edit Combo',
            onCancel: () => Navigator.pop(context),
            onSave: _save,
            canSave: _name.text.trim().isNotEmpty && _rows.isNotEmpty,
          ),
        ),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: InfoBanner.error(_error),
          ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
            children: [
              const FieldLabel('Name'),
              AppTextField(
                controller: _name,
                hint: 'e.g. Usual breakfast',
                fontSize: 16,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                autofocus: editing == null,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  if (_error.isNotEmpty) setState(() => _error = '');
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Expanded(child: SectionLabel('Items')),
                    if (_rows.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 13),
                        // Follows the calorie fields as they're typed in.
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            for (final r in _rows) r.qty,
                          ]),
                          builder: (context, _) => Text(
                            calLabel(_total(data)),
                            style: sans(
                              13,
                              weight: FontWeight.w600,
                              color: c.inkA(.55),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_rows.isEmpty)
                DashedBox(
                  fill: c.surface,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Search below to add the foods you eat together.',
                    textAlign: TextAlign.center,
                    style: sans(13.5, color: c.inkA(.5)),
                  ),
                ),
              for (final r in _rows)
                Padding(
                  key: ValueKey(r.rid),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DraftLineCard(
                    row: r,
                    onRemove: () => _remove(r),
                    onUnit: (u) => setState(() => r.unit = u),
                    fixedCalories: () => _caloriesText(r, data),
                  ),
                ),
              const SizedBox(height: 6),
              FoodPickPanel(
                key: _pickKey,
                controller: _search,
                items: data.items,
                onChanged: () {
                  setState(() {});
                  _revealPicker();
                },
                onPick: (i) => _add(i, data.defaultUnit),
                onCreate: () => _createFromSearch(data.defaultUnit),
              ),
              const SizedBox(height: 12),
              Text(
                'Calories come from each food’s default when you add the '
                'combo to a meal; you can still change them in the meal.',
                style: sans(12.5, color: c.inkA(.45), height: 1.5),
              ),
              if (editing != null) ...[
                const SizedBox(height: 18),
                Center(
                  child: Pill(
                    label: 'Delete combo',
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
    );
  }
}
