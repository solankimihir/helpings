import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

/// Add or edit a food item. Resolves to the saved item, or null if cancelled.
Future<FoodItem?> showItemSheet(
  BuildContext context, {
  FoodItem? editing,
  String presetName = '',
}) {
  return showModalBottomSheet<FoodItem>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => ItemSheet(editing: editing, presetName: presetName),
  );
}

class ItemSheet extends ConsumerStatefulWidget {
  const ItemSheet({super.key, this.editing, this.presetName = ''});
  final FoodItem? editing;
  final String presetName;

  @override
  ConsumerState<ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<ItemSheet> {
  late final TextEditingController _name;
  late final TextEditingController _cal;
  FoodUnit? _unit;
  String _error = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = TextEditingController(text: e?.name ?? widget.presetName);
    _cal = TextEditingController(
      text: e == null ? '' : fmtQty(e.defaultCalories),
    );
    _unit = e != null
        ? e.defaultUnit
        : ref.read(appDataProvider).value?.defaultUnit;
  }

  @override
  void dispose() {
    _name.dispose();
    _cal.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the item a name.');
      return;
    }
    final calText = _cal.text.trim();
    final cal = calText.isEmpty ? null : parseNum(calText);
    if (calText.isNotEmpty && cal == null) {
      setState(() => _error = 'Calories must be a number.');
      return;
    }
    final base = widget.editing;
    final item = base == null
        ? FoodItem(
            id: newId(),
            name: name,
            defaultCalories: cal,
            defaultUnit: _unit,
          )
        : base.copyWith(
            name: name,
            defaultCalories: () => cal,
            defaultUnit: () => _unit,
          );
    setState(() => _saving = true);
    try {
      final saved = await ref.read(appDataProvider.notifier).saveItem(item);
      if (mounted) Navigator.pop(context, saved);
    } on DuplicateNameException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
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
                title: widget.editing == null
                    ? 'Add Meal Item'
                    : 'Edit Meal Item',
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
                    hint: 'e.g. Roti',
                    fontSize: 16,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    autofocus:
                        widget.editing == null && widget.presetName.isEmpty,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) {
                      if (_error.isNotEmpty) setState(() => _error = '');
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Default calories'),
                            AppTextField(
                              controller: _cal,
                              hint: 'optional',
                              fontSize: 16,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 13,
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: decimalOnly,
                              onSubmitted: (_) => _save(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const FieldLabel('Default unit'),
                            UnitPicker(
                              value: _unit,
                              allowNone: true,
                              radius: 14,
                              fontSize: 16,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 13,
                              ),
                              onChanged: (u) => setState(() => _unit = u),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    InfoBanner.error(_error),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Defaults pre-fill new entries. Changing them never rewrites meals you already saved.',
                    style: sans(12.5, color: c.inkA(.45), height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
