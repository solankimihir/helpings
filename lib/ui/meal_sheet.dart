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
import 'widgets/line_editor.dart';

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
  final _rows = <DraftLine>[];
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
    _rows.addAll([for (final e in entries) draftFromEntry(e, data)]);
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
      _rows.add(draftFromItem(item, fallbackUnit));
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

  void _removeRow(DraftLine r) {
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
    final r = draftsToEntries(_rows);
    if (r.error != null) setState(() => _error = r.error!);
    return r.entries;
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
                      label: 'Same as ${_sameAsLabel(prev, data)}',
                      icon: Icons.replay_rounded,
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
                  child: DraftLineCard(
                    row: r,
                    onRemove: () => _removeRow(r),
                    onUnit: (u) => setState(() => r.unit = u),
                    units: data.unitsFor(r.unit),
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
                            _addEntries(data.comboLines(combo), data);
                          });
                          _revealPicker();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              FoodPickPanel(
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
