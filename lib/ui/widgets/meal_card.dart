import 'package:material_ui/material_ui.dart';

import '../../data/format.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// Full meal card on Home: header + each line with its calories.
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.meal,
    required this.data,
    required this.onTap,
  });

  final Meal meal;
  final AppData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = meal.totals;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MealBadge(meal.type),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meal.type.label,
                      style: sans(
                        16.5,
                        weight: FontWeight.w700,
                        color: c.ink,
                        letterSpacing: -.16,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${fmtTime(meal.time)} · ${plural(meal.entries.length, 'item')}',
                      style: sans(12, color: c.inkA(.45)),
                    ),
                  ],
                ),
              ),
              Text(
                calLabel(t),
                style: sans(
                  13,
                  weight: FontWeight.w500,
                  color: t.complete ? c.inkA(.6) : c.amberText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, e) in meal.entries.indexed) ...[
            if (i > 0) const SizedBox(height: 7),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.inkA(.2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lineText(data.displayName(e), e.qty, e.unit),
                    style: sans(14.5, color: c.inkA(.82)),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  e.calories == null ? '—' : fmtN(e.calories),
                  style: sans(12.5, color: c.inkA(.4)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
