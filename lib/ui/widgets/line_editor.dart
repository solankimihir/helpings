import 'package:material_ui/material_ui.dart';

import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Pieces shared by the meal and combo sheets: editable lines, their cards,
/// and the food search panel.

/// One editable line (food, qty, unit, calories) in a meal or combo.
class DraftLine {
  DraftLine({
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

class DraftLineCard extends StatelessWidget {
  const DraftLineCard({
    super.key,
    required this.row,
    required this.onRemove,
    required this.onUnit,
    required this.units,
    this.fixedCalories,
  });

  final DraftLine row;
  final VoidCallback onRemove;
  final ValueChanged<FoodUnit?> onUnit;

  /// Units to offer, from `AppData.unitsFor(row.unit)`.
  final List<FoodUnit> units;

  /// When set, calories aren't editable: shows this text (worked out from
  /// the line's quantity) instead of the calorie field. Used by combos.
  final String Function()? fixedCalories;

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
                      units: units,
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
                    if (fixedCalories case final fixed?)
                      ListenableBuilder(
                        listenable: row.qty,
                        builder: (context, _) => Padding(
                          padding: fieldPad.add(
                            const EdgeInsets.symmetric(vertical: 1),
                          ),
                          child: Text(
                            fixed(),
                            maxLines: 2,
                            style: sans(14, color: c.inkA(.6)),
                          ),
                        ),
                      )
                    else
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
class FoodPickPanel extends StatelessWidget {
  const FoodPickPanel({
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

/// Editable copy of a logged or saved line.
DraftLine draftFromEntry(MealEntry e, AppData data) => DraftLine(
  itemId: e.itemId,
  name: data.displayName(e),
  qty: fmtQty(e.qty),
  unit: e.unit,
  cal: fmtQty(e.calories),
);

/// A new line for [item], pre-filled from its defaults.
DraftLine draftFromItem(FoodItem item, FoodUnit fallbackUnit) => DraftLine(
  itemId: item.id,
  name: item.name,
  qty: '1',
  unit: item.defaultUnit ?? fallbackUnit,
  cal: fmtQty(item.defaultCalories),
);

/// The lines as fresh entries, or a user-facing error if a quantity or
/// calorie value isn't a number.
({List<MealEntry>? entries, String? error}) draftsToEntries(
  List<DraftLine> lines,
) {
  for (final r in lines) {
    final q = r.qty.text.trim();
    if (q.isNotEmpty && parseNum(q) == null) {
      return (entries: null, error: 'Quantity must be a number.');
    }
    final cal = r.cal.text.trim();
    if (cal.isNotEmpty && parseNum(cal) == null) {
      return (entries: null, error: 'Calories must be a number.');
    }
  }
  return (
    entries: [
      for (final r in lines)
        MealEntry(
          id: newId(),
          itemId: r.itemId,
          nameSnapshot: r.name,
          qty: r.qty.text.trim().isEmpty ? null : parseNum(r.qty.text),
          unit: r.unit,
          calories: r.cal.text.trim().isEmpty ? null : parseNum(r.cal.text),
        ),
    ],
    error: null,
  );
}
