import 'package:material_ui/material_ui.dart';

import '../../data/format.dart';
import '../../theme/app_theme.dart';
import 'common.dart';

/// "TODAY / Monday, November 16 ⌄" with a Today pill on past days. Tapping
/// the date calls [onPick]. Shared by Home and Health.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.daysAgo,
    required this.onPick,
    required this.onToday,
  });

  /// 0 = today.
  final int daysAgo;
  final VoidCallback onPick;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = parseKey(shiftKey(-daysAgo));
    final overlineText = switch (daysAgo) {
      0 => 'TODAY',
      1 => 'YESTERDAY',
      _ when date.year != DateTime.now().year => '${date.year}',
      _ => '$daysAgo DAYS AGO',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Choose a day',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPick,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(overlineText, style: overline(context, spacing: .14)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Long dates ("Wednesday, September 30") shrink to
                        // stay on one line rather than wrap.
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              longDate(date),
                              maxLines: 1,
                              style: serif(34, color: c.ink, height: 1.08),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 22,
                          color: c.inkA(.35),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (daysAgo > 0) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Pill(
                label: 'Today',
                fontSize: 13,
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 7,
                ),
                onTap: onToday,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
