import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'item_sheet.dart';
import 'shell.dart';
import 'meal_type_sheet.dart';
import 'widgets/common.dart';

/// Add a new meal (on [date], default today), or edit [editing]. A
/// [template] pre-fills a new meal from an existing one ("Log again").
Future<void> showMealSheet(
  BuildContext context, {
  Meal? editing,
  Meal? template,
  String? date,
  String? typeId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    // Lift the sheet above the keyboard rather than letting the list run
    // underneath it: otherwise a focused field "fits" in a viewport the
    // keyboard is covering, and Flutter never scrolls it into view.
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: FractionallySizedBox(
        heightFactor: .92,
        child: MealSheet(
          editing: editing,
          template: template,
          date: date,
          typeId: typeId,
        ),
      ),
    ),
  );
}

class _DraftRow {
  _DraftRow({
    required this.itemId,
    required this.name,
    required String qty,
    required this.unit,
    required String cal,
  }) : rid = newId(),
       qty = TextEditingController(text: qty),
       cal = TextEditingController(text: cal);

  final String rid;
  final String? itemId;
  final String name;
  final TextEditingController qty;
  final TextEditingController cal;
  FoodUnit? unit;

  void dispose() {
    qty.dispose();
    cal.dispose();
  }
}

class MealSheet extends ConsumerStatefulWidget {
  const MealSheet({
    super.key,
    this.editing,
    this.template,
    this.date,
    this.typeId,
  });

  /// Preselected [MealType.id] for a new meal (e.g. from a reminder).
  final String? typeId;
  final Meal? editing;

  /// Copied into a new meal: type, items and notes. Ignored when editing.
  final Meal? template;

  /// [dayKey] for a new meal; today when null. Ignored when editing.
  final String? date;

  @override
  ConsumerState<MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends ConsumerState<MealSheet> {
  /// [MealType.id].
  late String _typeId;
  late String _date;
  late String _time;
  late final TextEditingController _notes;
  final _search = TextEditingController();
  final _rows = <_DraftRow>[];
  final _pickKey = GlobalKey();
  String _error = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.editing;
    final data = ref.read(appDataProvider).requireValue;
    if (m == null) {
      final t = widget.template;
      _typeId =
          t?.typeId ??
          (data.typeById(widget.typeId ?? '') != null ? widget.typeId : null) ??
          (guessMealType(data.mealTypes, DateTime.now()) ??
                  data.mealTypes.firstOrNull)
              ?.id ??
          'other';
      _date = widget.date ?? todayKey();
      _time = nowTime();
      _notes = TextEditingController(text: t?.notes ?? '');
      if (t != null) _addEntries(t.entries, data);
    } else {
      _typeId = m.typeId;
      _date = m.date;
      _time = m.time;
      _notes = TextEditingController(text: m.notes);
      _addEntries(m.entries, data);
    }
  }

  /// Appends editable copies of logged lines.
  void _addEntries(List<MealEntry> entries, AppData data) {
    for (final e in entries) {
      _rows.add(
        _DraftRow(
          itemId: e.itemId,
          name: data.displayName(e),
          qty: fmtQty(e.qty),
          unit: e.unit,
          cal: fmtQty(e.calories),
        ),
      );
    }
  }

  /// "yesterday’s Lunch", "today’s Lunch", or "Lunch from November 3".
  static String _sameAsLabel(Meal prev, AppData data) {
    final type = data.typeName(prev);
    if (prev.date == shiftKey(-1)) return 'yesterday’s $type';
    if (prev.date == todayKey()) return 'today’s $type';
    return '$type from ${dayGroupLabel(prev.date)}';
  }

  /// The latest meal of the selected type on the day before this meal's
  /// date, offered as a one-tap start for a new, still-empty meal.
  Meal? _previousDayMeal(AppData data) {
    if (widget.editing != null || _rows.isNotEmpty) return null;
    final prev = dayKey(parseKey(_date).subtract(const Duration(days: 1)));
    for (final m in data.meals.reversed) {
      if (m.date == prev && m.typeId == _typeId && m.entries.isNotEmpty) {
        return m;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _notes.dispose();
    _search.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addFromItem(FoodItem item, FoodUnit fallbackUnit) {
    setState(() {
      _error = '';
      _search.clear();
      _rows.add(
        _DraftRow(
          itemId: item.id,
          name: item.name,
          qty: '1',
          unit: item.defaultUnit ?? fallbackUnit,
          cal: fmtQty(item.defaultCalories),
        ),
      );
    });
    _revealPicker();
  }

  /// Keeps the search box and its results on screen above the keyboard:
  /// each added item pushes it further down the list.
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

  void _removeRow(_DraftRow r) {
    setState(() => _rows.remove(r));
    r.dispose();
  }

  Future<void> _createFromSearch(FoodUnit fallbackUnit) async {
    final created = await showItemSheet(
      context,
      presetName: _search.text.trim(),
    );
    if (created != null && mounted) _addFromItem(created, fallbackUnit);
  }

  /// The draft rows as fresh entries, or null (with [_error] set) if a
  /// quantity or calorie value isn't a number.
  List<MealEntry>? _validEntries() {
    for (final r in _rows) {
      final q = r.qty.text.trim();
      if (q.isNotEmpty && parseNum(q) == null) {
        setState(() => _error = 'Quantity must be a number.');
        return null;
      }
      final cal = r.cal.text.trim();
      if (cal.isNotEmpty && parseNum(cal) == null) {
        setState(() => _error = 'Calories must be a number.');
        return null;
      }
    }
    return [
      for (final r in _rows)
        MealEntry(
          id: newId(),
          itemId: r.itemId,
          nameSnapshot: r.name,
          qty: r.qty.text.trim().isEmpty ? null : parseNum(r.qty.text),
          unit: r.unit,
          calories: r.cal.text.trim().isEmpty ? null : parseNum(r.cal.text),
        ),
    ];
  }

  /// Saves the current lines as a named combo for one-tap reuse.
  Future<void> _saveAsCombo() async {
    if (_rows.isEmpty) {
      setState(
        () => _error =
            'Add the items you eat together first, then save them as a combo.',
      );
      return;
    }
    final entries = _validEntries();
    if (entries == null) return;
    final name = await promptText(
      context,
      title: 'Save as combo',
      action: 'Save',
      hint: 'e.g. Usual breakfast',
    );
    if (name == null || !mounted) return;
    try {
      await ref
          .read(appDataProvider.notifier)
          .saveCombo(Combo(id: newId(), name: name, items: entries));
      if (mounted) setState(() => _error = '');
    } on DuplicateNameException catch (e) {
      if (mounted) setState(() => _error = 'A combo named $e');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one meal item before saving.');
      return;
    }
    final entries = _validEntries();
    if (entries == null) return;
    final isNew = widget.editing == null;
    final meal = Meal(
      id: widget.editing?.id ?? newId(),
      typeId: _typeId,
      date: _date,
      time: _time,
      notes: _notes.text.trim(),
      entries: entries,
    );
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    await ref.read(appDataProvider.notifier).saveMeal(meal);
    if (isNew) ref.read(currentTabProvider.notifier).select(AppTab.home);
    if (mounted) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = ref.watch(appDataProvider).requireValue;

    return Column(
      children: [
        SheetHeader(
          title: widget.editing == null ? 'Add Meal' : 'Edit Meal',
          onCancel: () => Navigator.pop(context),
          onSave: _save,
          canSave: _rows.isNotEmpty,
        ),
        // Pinned under the header so it's visible wherever the list is
        // scrolled.
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
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in data.mealTypes)
                    // Hidden types only show when this meal already uses one.
                    if (t.active || t.id == _typeId)
                      AppChip(
                        label: t.name,
                        selected: t.id == _typeId,
                        onTap: () => setState(() => _typeId = t.id),
                      ),
                  AppChip(
                    label: '+ New',
                    selected: false,
                    onTap: () async {
                      final created = await showMealTypeSheet(context);
                      if (created != null && mounted) {
                        setState(() => _typeId = created.id);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 13,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Date'),
                        PickerField(
                          text: _dateLabel(_date),
                          semanticLabel: 'Date',
                          onTap: () async {
                            final d = await pickDate(context, _date);
                            if (d != null) setState(() => _date = d);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const FieldLabel('Time'),
                        PickerField(
                          text: fmtTime(_time),
                          semanticLabel: 'Time',
                          onTap: () async {
                            final t = await pickTime(context, _time);
                            if (t != null) setState(() => _time = t);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Items heading, with Save as combo always in reach.
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Row(
                  children: [
                    const Expanded(
                      child: SectionLabel(
                        'Items',
                        padding: EdgeInsets.only(top: 8, bottom: 5),
                      ),
                    ),
                    Pill(
                      label: 'Save as combo',
                      icon: Icons.star_border_rounded,
                      style: PillStyle.ghost,
                      color: _rows.isEmpty ? c.inkA(.4) : c.link,
                      fontSize: 13,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      onTap: _saveAsCombo,
                    ),
                  ],
                ),
              ),
              if (_previousDayMeal(data) case final prev?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(
                      label: '↻ Same as ${_sameAsLabel(prev, data)}',
                      style: PillStyle.white,
                      onTap: () => setState(() {
                        _error = '';
                        _addEntries(prev.entries, data);
                      }),
                    ),
                  ),
                ),
              if (_rows.isEmpty)
                DashedBox(
                  fill: c.surface,
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Search below to add what you ate.',
                    textAlign: TextAlign.center,
                    style: sans(13.5, color: c.inkA(.5)),
                  ),
                ),
              for (final r in _rows)
                Padding(
                  key: ValueKey(r.rid),
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DraftRowCard(
                    row: r,
                    onRemove: () => _removeRow(r),
                    onUnit: (u) => setState(() => r.unit = u),
                  ),
                ),
              if (data.combos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final combo in data.combos)
                      Pill(
                        label: combo.name,
                        icon: Icons.star_rounded,
                        style: PillStyle.white,
                        fontSize: 13,
                        onTap: () {
                          setState(() {
                            _error = '';
                            _addEntries(combo.items, data);
                          });
                          _revealPicker();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              _PickPanel(
                key: _pickKey,
                controller: _search,
                items: data.items,
                onChanged: () {
                  setState(() {});
                  _revealPicker();
                },
                onPick: (i) => _addFromItem(i, data.defaultUnit),
                onCreate: () => _createFromSearch(data.defaultUnit),
              ),
              const SectionLabel('Notes'),
              AppTextField(
                controller: _notes,
                hint: 'Optional',
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _dateLabel(String key) {
    if (key == todayKey()) return 'Today';
    if (key == shiftKey(-1)) return 'Yesterday';
    return dayGroupLabel(key);
  }
}

class _DraftRowCard extends StatelessWidget {
  const _DraftRowCard({
    required this.row,
    required this.onRemove,
    required this.onUnit,
  });

  final _DraftRow row;
  final VoidCallback onRemove;
  final ValueChanged<FoodUnit?> onUnit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    const fieldPad = EdgeInsets.symmetric(horizontal: 10, vertical: 9);
    return AppCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  style: sans(15.5, weight: FontWeight.w500, color: c.ink),
                ),
              ),
              Tap(
                onTap: onRemove,
                color: c.bg,
                semanticLabel: 'Remove ${row.name}',
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(Icons.close_rounded, size: 15, color: c.inkA(.5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 66,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Qty', small: true),
                    AppTextField(
                      controller: row.qty,
                      radius: 11,
                      padding: fieldPad,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: decimalOnly,
                      semanticLabel: 'Quantity',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Unit', small: true),
                    UnitPicker(
                      value: row.unit,
                      allowNone: row.unit == null,
                      onChanged: onUnit,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Calories', small: true),
                    AppTextField(
                      controller: row.cal,
                      hint: 'optional',
                      radius: 11,
                      padding: fieldPad,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: decimalOnly,
                      semanticLabel: 'Calories',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Search box + matching active food chips + "Create …".
class _PickPanel extends StatelessWidget {
  const _PickPanel({
    super.key,
    required this.controller,
    required this.items,
    required this.onChanged,
    required this.onPick,
    required this.onCreate,
  });

  final TextEditingController controller;
  final List<FoodItem> items;
  final VoidCallback onChanged;
  final ValueChanged<FoodItem> onPick;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final q = controller.text.trim().toLowerCase();
    final results = items
        .where(
          (i) => i.active && (q.isEmpty || i.name.toLowerCase().contains(q)),
        )
        .take(8)
        .toList();
    final exact = items.any((i) => i.name.toLowerCase() == q);

    return AppCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: controller,
            hint: 'Search food — e.g. Roti',
            radius: 12,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => onChanged(),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (results.length == 1) onPick(results.first);
            },
          ),
          if (results.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final i in results)
                  Tap(
                    onTap: () => onPick(i),
                    color: c.bg,
                    border: Border.all(color: c.inkA(.1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: i.name,
                        children: [
                          if (i.defaultCalories != null)
                            TextSpan(
                              text: '  ${fmtN(i.defaultCalories)}',
                              style: sans(12.5, color: c.inkA(.4)),
                            ),
                        ],
                      ),
                      style: sans(14, color: c.ink),
                    ),
                  ),
              ],
            ),
          ],
          if (q.isNotEmpty && !exact) ...[
            const SizedBox(height: 10),
            DashedBox(
              radius: 13,
              padding: const EdgeInsets.all(11),
              onTap: onCreate,
              child: Text(
                '+ Create “${controller.text.trim()}” as a new food item',
                textAlign: TextAlign.center,
                style: sans(13.5, weight: FontWeight.w500, color: c.greenText),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
