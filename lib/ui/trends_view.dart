import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/trends.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'shell.dart';
import 'widgets/common.dart';

/// History → Trends: calories per day for a week or month, the average,
/// meal count and most-logged foods.
class TrendsView extends ConsumerStatefulWidget {
  const TrendsView({super.key});

  @override
  ConsumerState<TrendsView> createState() => _TrendsViewState();
}

class _TrendsViewState extends ConsumerState<TrendsView> {
  TrendRange _range = TrendRange.week;

  /// Periods back from the current one.
  int _offset = 0;

  /// [dayKey] of the tapped bar.
  String? _selected;

  void _setPeriod(TrendRange range, int offset) => setState(() {
    _range = range;
    _offset = offset;
    _selected = null;
  });

  void _openDay(String date) {
    ref.read(homeDayProvider.notifier).show(daysAgo(date));
    ref.read(currentTabProvider.notifier).select(AppTab.home);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final s = summarizeTrends(data, _range, _offset, DateTime.now());
    final avg = s.averagePerLoggedDay;
    final logged = s.loggedDays.length;
    final selected = _selected == null
        ? null
        : s.days.where((d) => d.date == _selected).firstOrNull;

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 4, 16, shellBottomInset(context)),
      children: [
        Row(
          children: [
            for (final r in TrendRange.values)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: AppChip(
                  label: r == TrendRange.week ? 'Week' : 'Month',
                  selected: r == _range,
                  onTap: () => _setPeriod(r, 0),
                ),
              ),
            const SizedBox(width: 4),
            // Navigation hugs the right; the label shrinks only when the
            // remaining space really is too narrow for it.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NavButton(
                    icon: Icons.chevron_left_rounded,
                    label: 'Previous ${_range.name}',
                    onTap: () => _setPeriod(_range, _offset + 1),
                  ),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        s.label,
                        maxLines: 1,
                        style: sans(
                          13.5,
                          weight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  _NavButton(
                    icon: Icons.chevron_right_rounded,
                    label: 'Next ${_range.name}',
                    onTap: _offset == 0
                        ? null
                        : () => _setPeriod(_range, _offset - 1),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: 'Average',
                  value: avg == null ? '—' : fmtN(avg),
                  unit: avg == null ? null : 'kcal/day',
                  note: logged == 0
                      ? 'nothing logged'
                      : 'over ${plural(logged, 'logged day')}',
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'Meals',
                  value: '${s.mealCount}',
                  note: _range == TrendRange.week ? 'this week' : 'this month',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  'Calories per day',
                  style: sans(14.5, weight: FontWeight.w600, color: c.ink),
                ),
              ),
              _CaloriesChart(
                summary: s,
                selected: _selected,
                onSelect: (d) =>
                    setState(() => _selected = _selected == d ? null : d),
              ),
              const SizedBox(height: 10),
              if (selected != null)
                _SelectedDay(
                  day: selected,
                  onOpen: () => _openDay(selected.date),
                )
              else
                Text(
                  logged == 0
                      ? 'No meals logged in this period.'
                      : 'Tap a bar for that day’s details.',
                  style: sans(12.5, color: c.inkA(.45)),
                ),
              if (s.days.any((d) => d.incomplete)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CustomPaint(
                        painter: _BarPainter(
                          color: c.primary,
                          hatch: c.surface,
                          incomplete: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Striped: some items have no calories, so the real '
                        'total is higher.',
                        style: sans(12, color: c.inkA(.5), height: 1.35),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Most logged',
                style: sans(14.5, weight: FontWeight.w600, color: c.ink),
              ),
              const SizedBox(height: 6),
              if (s.topFoods.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Nothing logged in this period.',
                    style: sans(13, color: c.inkA(.45)),
                  ),
                ),
              for (final (name, count) in s.topFoods)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name, style: sans(14, color: c.ink)),
                      ),
                      Text(
                        '×$count',
                        style: sans(
                          13.5,
                          weight: FontWeight.w600,
                          color: c.inkA(.55),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tap(
      onTap: onTap,
      semanticLabel: label,
      padding: const EdgeInsets.all(6),
      child: Icon(
        icon,
        size: 24,
        color: onTap == null ? c.inkA(.15) : c.inkA(.6),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.note,
    this.unit,
  });
  final String label;
  final String value;
  final String? unit;
  final String note;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: overline(context)),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: sans(
                  26,
                  weight: FontWeight.w700,
                  color: c.ink,
                  letterSpacing: -.5,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 5),
                Text(unit!, style: sans(12.5, color: c.inkA(.5))),
              ],
            ],
          ),
        ),
        Text(note, style: sans(11.5, color: c.inkA(.45))),
      ],
    );
  }
}

/// Clean y-axis top and step for [max] (0 / 500 / 1,000 / …), 2–4 steps.
(double, double) niceScale(double max) {
  if (max <= 0) return (1000, 500);
  for (final step in const [
    50.0,
    100.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    2500.0,
    5000.0,
    10000.0,
  ]) {
    final top = (max / step).ceil() * step;
    if (top / step <= 4) return (top, step);
  }
  final step = math.pow(10, (math.log(max) / math.ln10).floor()).toDouble();
  return ((max / step).ceil() * step, step);
}

class _CaloriesChart extends StatelessWidget {
  const _CaloriesChart({
    required this.summary,
    required this.selected,
    required this.onSelect,
  });

  final TrendSummary summary;
  final String? selected;
  final ValueChanged<String> onSelect;

  static const _plotHeight = 160.0;
  static const _axisWidth = 40.0;

  /// Room above the top gridline for its label.
  static const _headroom = 10.0;

  /// Height of the scale, 0 to [top], in the plot.
  static const _scaleHeight = _plotHeight - _headroom;

  /// A tick label's box; centred on its gridline.
  static const _tickBox = 14.0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // A stronger step of the same green marks the tapped bar.
    final emphasis = dark ? c.greenText : c.primaryPressed;
    final (top, step) = niceScale(summary.maxCalories);
    final ticks = [for (var v = 0.0; v <= top; v += step) v];
    final today = todayKey();
    final days = summary.days;
    final isWeek = summary.range == TrendRange.week;
    final weekday = DateFormat('E', 'en_US');
    final longDay = DateFormat('EEEE, MMMM d', 'en_US');

    String xLabel(int i) {
      final d = parseKey(days[i].date);
      if (isWeek) return weekday.format(d).substring(0, 1);
      return d.day == 1 || d.day % 7 == 1 ? '${d.day}' : '';
    }

    return Column(
      children: [
        SizedBox(
          height: _plotHeight,
          child: Stack(
            // The "0" label hangs half its height below the baseline.
            clipBehavior: Clip.none,
            children: [
              // Hairline gridlines exactly at their value, each label
              // centred on its line.
              for (final v in ticks)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: v / top * _scaleHeight - _tickBox / 2,
                  height: _tickBox,
                  child: Row(
                    children: [
                      SizedBox(
                        width: _axisWidth,
                        child: Text(
                          fmtN(v),
                          style: sans(10.5, color: c.inkA(.4), height: 1.2),
                        ),
                      ),
                      Expanded(child: Container(height: 1, color: c.inkA(.07))),
                    ],
                  ),
                ),
              Positioned.fill(
                left: _axisWidth,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final slot = box.maxWidth / days.length;
                    // Capped at 24px; the 2px minimum gap keeps touching
                    // month bars apart.
                    final barWidth = math.max(2.0, math.min(24.0, slot - 2));
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final d in days)
                          Expanded(
                            child: Semantics(
                              button: d.logged,
                              selected: d.date == selected,
                              label:
                                  '${longDay.format(parseKey(d.date))}: '
                                  '${d.logged ? '${fmtN(d.calories)} kcal, ${plural(d.meals, 'meal')}${d.incomplete ? ', incomplete' : ''}' : 'nothing logged'}',
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: d.logged ? () => onSelect(d.date) : null,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: !d.logged
                                      ? const SizedBox.shrink()
                                      : SizedBox(
                                          key: ValueKey('bar-${d.date}'),
                                          width: barWidth,
                                          height: math.max(
                                            3,
                                            d.calories / top * _scaleHeight,
                                          ),
                                          child: CustomPaint(
                                            painter: _BarPainter(
                                              color: d.date == selected
                                                  ? emphasis
                                                  : c.primary,
                                              hatch: c.surface,
                                              incomplete: d.incomplete,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: _axisWidth),
          child: Row(
            children: [
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Text(
                    xLabel(i),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: sans(
                      10.5,
                      weight: days[i].date == today
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: days[i].date == today ? c.ink : c.inkA(.45),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A column with a 4px rounded top and square base; [incomplete] adds 45°
/// stripes in the surface colour so it doesn't rely on colour alone.
class _BarPainter extends CustomPainter {
  const _BarPainter({
    required this.color,
    required this.hatch,
    required this.incomplete,
  });

  final Color color;
  final Color hatch;
  final bool incomplete;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(4.0, size.width / 2);
    final shape = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: Radius.circular(r),
      topRight: Radius.circular(r),
    );
    canvas.drawRRect(shape, Paint()..color = color);
    if (!incomplete) return;
    canvas.save();
    canvas.clipRRect(shape);
    final stripe = Paint()
      ..color = hatch.withValues(alpha: .55)
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.color != color || old.hatch != hatch || old.incomplete != incomplete;
}

class _SelectedDay extends StatelessWidget {
  const _SelectedDay({required this.day, required this.onOpen});
  final DayTotal day;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final date = DateFormat('EEE, MMM d', 'en_US').format(parseKey(day.date));
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$date  ',
                  style: sans(13, weight: FontWeight.w600, color: c.ink),
                ),
                TextSpan(
                  text:
                      '${fmtN(day.calories)}${day.incomplete ? '+' : ''} kcal · '
                      '${plural(day.meals, 'meal')}',
                  style: sans(13, color: c.inkA(.6)),
                ),
              ],
            ),
          ),
        ),
        Pill(
          label: 'Open day',
          fontSize: 13,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          onTap: onOpen,
        ),
      ],
    );
  }
}
