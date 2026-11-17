import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> _show(BuildContext context, Widget sheet) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.c.bg,
      barrierColor: context.c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => sheet,
    );

/// Add a blood sugar reading on [date], or edit [editing].
Future<void> showSugarSheet(
  BuildContext context, {
  required String date,
  SugarReading? editing,
}) => _show(context, _ReadingSheet.sugar(date: date, sugar: editing));

/// Add a weigh-in on [date], or edit [editing].
Future<void> showWeightSheet(
  BuildContext context, {
  required String date,
  WeightEntry? editing,
}) => _show(context, _ReadingSheet.weight(date: date, weight: editing));

/// Time for a new entry on [date]: now today, midday on other days.
String defaultTimeFor(String date) => date == todayKey() ? nowTime() : '12:00';

class _ReadingSheet extends ConsumerStatefulWidget {
  const _ReadingSheet.sugar({required this.date, this.sugar})
    : isSugar = true,
      weight = null;
  const _ReadingSheet.weight({required this.date, this.weight})
    : isSugar = false,
      sugar = null;

  final bool isSugar;
  final String date;
  final SugarReading? sugar;
  final WeightEntry? weight;

  bool get editing => sugar != null || weight != null;

  @override
  ConsumerState<_ReadingSheet> createState() => _ReadingSheetState();
}

class _ReadingSheetState extends ConsumerState<_ReadingSheet> {
  late final AppData _data = ref.read(appDataProvider).requireValue;
  late String _date = widget.sugar?.date ?? widget.weight?.date ?? widget.date;
  late String _time =
      widget.sugar?.time ?? widget.weight?.time ?? defaultTimeFor(widget.date);
  late SugarContext _context = widget.sugar?.context ?? _guessContext();
  late final TextEditingController _value = TextEditingController(
    text: _initialValue(),
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.sugar?.note ?? widget.weight?.note ?? '',
  );
  bool _saving = false;

  String _initialValue() {
    if (widget.sugar case final s?) return _data.sugarUnit.format(s.mgdl);
    if (widget.weight case final w?) return _data.weightUnit.format(w.kg);
    // A new weigh-in starts from the last one; easier to nudge than type.
    if (!widget.isSugar) {
      if (_data.weightAsOf(widget.date) case final w?) {
        return _data.weightUnit.format(w.kg);
      }
    }
    return '';
  }

  /// First reading of the day before 10 AM is most likely fasting.
  SugarContext _guessContext() {
    final (h, _) = parseTime(defaultTimeFor(widget.date));
    return h < 10 && _data.sugarOn(widget.date).isEmpty
        ? SugarContext.fasting
        : SugarContext.other;
  }

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _parsed {
    final v = parseNum(_value.text);
    return v == null || v <= 0 ? null : v;
  }

  String get _unit =>
      widget.isSugar ? _data.sugarUnit.label : _data.weightUnit.label;

  Future<void> _save() async {
    final v = _parsed;
    if (v == null || _saving) return;
    setState(() => _saving = true);
    final notifier = ref.read(appDataProvider.notifier);
    final note = _note.text.trim();
    if (widget.isSugar) {
      final mgdl = _data.sugarUnit.fromDisplay(v);
      await notifier.saveSugar(
        SugarReading(
          id: widget.sugar?.id ?? newId(),
          date: _date,
          time: _time,
          mgdl: mgdl,
          context: _context,
          note: note,
        ),
      );
    } else {
      await notifier.saveWeight(
        WeightEntry(
          id: widget.weight?.id ?? newId(),
          date: _date,
          time: _time,
          kg: _data.weightUnit.fromDisplay(v),
          note: note,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: widget.isSugar ? 'Delete this reading?' : 'Delete this weigh-in?',
      message: 'It will be removed from this device.',
      action: 'Delete',
    );
    if (!ok || !mounted) return;
    final notifier = ref.read(appDataProvider.notifier);
    final nav = Navigator.of(context);
    if (widget.sugar case final s?) await notifier.deleteSugar(s.id);
    if (widget.weight case final w?) await notifier.deleteWeight(w.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final w = widget;
    final title = w.isSugar
        ? (w.editing ? 'Edit Reading' : 'Blood Sugar')
        : (w.editing ? 'Edit Weight' : 'Weight');
    final pickerPad = const EdgeInsets.symmetric(horizontal: 14, vertical: 13);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: _value,
                builder: (context, _) => SheetHeader(
                  title: title,
                  onCancel: () => Navigator.pop(context),
                  onSave: _save,
                  canSave: _parsed != null && !_saving,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel(w.isSugar ? 'Reading' : 'Weight'),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _value,
                            hint: w.isSugar ? 'e.g. 104' : 'e.g. 72.5',
                            fontSize: 22,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            autofocus: !w.editing,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: decimalOnly,
                            semanticLabel: w.isSugar ? 'Reading' : 'Weight',
                            onSubmitted: (_) => _save(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(_unit, style: sans(16, color: c.inkA(.55))),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Date'),
                              PickerField(
                                text: dayGroupLabel(_date),
                                semanticLabel: 'Date',
                                padding: pickerPad,
                                onTap: () async {
                                  final d = await pickDate(
                                    context,
                                    _date,
                                    last: DateTime.now(),
                                  );
                                  if (d != null) setState(() => _date = d);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const FieldLabel('Time'),
                              PickerField(
                                text: fmtTime(_time),
                                semanticLabel: 'Time',
                                padding: pickerPad,
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
                    if (w.isSugar) ...[
                      const SizedBox(height: 14),
                      const FieldLabel('When'),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final sc in SugarContext.values)
                            AppChip(
                              label: sc.label,
                              selected: sc == _context,
                              onTap: () => setState(() => _context = sc),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 14),
                    const FieldLabel('Note'),
                    AppTextField(
                      controller: _note,
                      hint: 'Optional',
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    if (w.editing) ...[
                      const SizedBox(height: 20),
                      Pill(
                        label: 'Delete',
                        style: PillStyle.danger,
                        expand: true,
                        onTap: _delete,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
