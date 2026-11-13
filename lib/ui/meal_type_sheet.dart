import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Add or edit a meal type. Resolves to the saved type, or null if cancelled
/// or deleted.
Future<MealType?> showMealTypeSheet(BuildContext context, {MealType? editing}) {
  return showModalBottomSheet<MealType>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => MealTypeSheet(editing: editing),
  );
}

/// `HH:mm` for minutes after midnight.
String minuteKey(int m) => timeKey(m ~/ 60, m % 60);

class MealTypeSheet extends ConsumerStatefulWidget {
  const MealTypeSheet({super.key, this.editing});
  final MealType? editing;

  @override
  ConsumerState<MealTypeSheet> createState() => _MealTypeSheetState();
}

class _MealTypeSheetState extends ConsumerState<MealTypeSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.editing?.name ?? '',
  );
  late int? _start = widget.editing?.startMinute;
  late int? _remind = widget.editing?.remindMinute;
  late bool _active = widget.editing?.active ?? true;
  String _error = '';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the meal type a name.');
      return;
    }
    final base = widget.editing;
    final type = base == null
        ? MealType(
            id: newId(),
            name: name,
            startMinute: _start,
            remindMinute: _remind,
          )
        : base.copyWith(
            name: name,
            active: _active,
            startMinute: () => _start,
            remindMinute: () => _remind,
          );
    setState(() => _saving = true);
    try {
      final saved = await ref.read(appDataProvider.notifier).saveMealType(type);
      if (mounted) Navigator.pop(context, saved);
    } on DuplicateNameException catch (e) {
      _fail(e.toString());
    } on LastMealTypeException catch (e) {
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

  /// A time picker field with a Clear button; [value] is minutes after
  /// midnight, null when not set.
  Widget _timeField({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(label),
      Row(
        children: [
          Expanded(
            child: PickerField(
              text: value == null ? 'Not set' : fmtTime(minuteKey(value)),
              semanticLabel: label,
              fontSize: 16,
              radius: 14,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              onTap: () async {
                final t = await pickTime(context, minuteKey(value ?? 12 * 60));
                if (t == null) return;
                final (h, m) = parseTime(t);
                onChanged(h * 60 + m);
              },
            ),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Pill(
              label: 'Clear',
              style: PillStyle.ghost,
              onTap: () => onChanged(null),
            ),
          ],
        ],
      ),
    ],
  );

  Future<void> _delete() async {
    final type = widget.editing!;
    final notifier = ref.read(appDataProvider.notifier);
    final data = ref.read(appDataProvider).requireValue;
    if (data.visibleTypes.every((t) => t.id == type.id)) {
      setState(() => _error = const LastMealTypeException().toString());
      return;
    }
    final uses = await notifier.mealTypeUsageCount(type.id);
    if (!mounted) return;
    String? moveTo;
    if (uses == 0) {
      final ok = await confirm(
        context,
        title: 'Delete “${type.name}”?',
        message: 'No meals use it.',
        action: 'Delete',
      );
      if (!ok) return;
    } else {
      moveTo = await _chooseMoveTarget(
        type,
        uses,
        data.mealTypes.where((t) => t.id != type.id).toList(),
      );
      if (moveTo == null) return;
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    await notifier.deleteMealType(type.id, moveTo: moveTo);
    nav.pop();
  }

  /// Asks which type the [uses] meals of [type] should become.
  Future<String?> _chooseMoveTarget(
    MealType type,
    int uses,
    List<MealType> others,
  ) {
    // Visible types first, preselecting the first of them.
    final sorted = [
      ...others.where((t) => t.active),
      ...others.where((t) => !t.active),
    ];
    var selected = sorted.first.id;
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Delete “${type.name}”?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Move its ${plural(uses, 'meal')} to:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final t in sorted)
                    AppChip(
                      label: t.name,
                      selected: t.id == selected,
                      onTap: () => setDialog(() => selected = t.id),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, selected),
              style: TextButton.styleFrom(foregroundColor: ctx.c.danger),
              child: const Text('Move & delete'),
            ),
          ],
        ),
      ),
    );
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
                title: editing == null ? 'Add Meal Type' : 'Edit Meal Type',
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
                  AppTextField(
                    controller: _name,
                    hint: 'e.g. Pre-workout',
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
                  const SizedBox(height: 14),
                  _timeField(
                    label: 'Usually starts at',
                    value: _start,
                    onChanged: (v) => setState(() => _start = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'New meals pick the type whose start time passed most '
                    'recently. Without one, this type is only used when you '
                    'tap it.',
                    style: sans(12.5, color: c.inkA(.45), height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  _timeField(
                    label: 'Remind me at',
                    value: _remind,
                    onChanged: (v) => setState(() => _remind = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'A nudge at this time if nothing of this type is '
                    'logged yet that day. Turn reminders on in Settings.',
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
                                'Show when adding meals',
                                style: sans(
                                  15,
                                  weight: FontWeight.w500,
                                  color: c.ink,
                                ),
                              ),
                              Text(
                                'Hidden types stay on past meals.',
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
                  if (editing != null) ...[
                    const SizedBox(height: 18),
                    Center(
                      child: Pill(
                        label: 'Delete meal type',
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
