import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/cycles.dart';
import '../data/format.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'health_screen.dart' show periodOutlook;
import 'widgets/common.dart';

Future<void> openPeriodCalendar(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PeriodCalendarScreen()));

/// Months shown after the current one, so estimates can be seen ahead.
const _monthsAhead = 3;

final _monthTitle = DateFormat('MMMM y', 'en_US');
final _shortDay = DateFormat('MMM d', 'en_US');
final _shortDayYear = DateFormat('MMM d, y', 'en_US');

/// Health › Period › Calendar & history: tap days to log or clear them.
class PeriodCalendarScreen extends ConsumerStatefulWidget {
  const PeriodCalendarScreen({super.key});

  @override
  ConsumerState<PeriodCalendarScreen> createState() =>
      _PeriodCalendarScreenState();
}

class _PeriodCalendarScreenState extends ConsumerState<PeriodCalendarScreen> {
  late final DateTime _first = DateTime(
    firstPickableDate.year,
    firstPickableDate.month,
  );
  late final int _thisMonth = _index(DateTime.now());
  late final PageController _pages = PageController(initialPage: _thisMonth);
  late int _page = _thisMonth;

  int _index(DateTime d) =>
      (d.year - _first.year) * 12 + d.month - _first.month;

  DateTime _month(int i) => DateTime(_first.year, _first.month + i);

  void _goTo(int i) => _pages.animateToPage(
    i,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final today = todayKey();
    final predicted = predictedDays(data.periods, data.cycleStats, today);
    final stats = data.cycleStats;
    final outlook = periodOutlook(data, today);
    final month = _month(_page);
    final lastPage = _thisMonth + _monthsAhead;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: softShadow(context),
                  ),
                  child: Tap(
                    onTap: () => Navigator.of(context).maybePop(),
                    color: c.surface,
                    semanticLabel: 'Back',
                    child: SizedBox(
                      width: 38,
                      height: 38,
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 24,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 2),
              child: Text('Period', style: serif(32, color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(
                'Tap a day to log it as a period day, or tap again to clear it.',
                style: sans(13, color: c.inkA(.5)),
              ),
            ),
            AppCard(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      _NavButton(
                        icon: Icons.chevron_left_rounded,
                        label: 'Previous month',
                        onTap: _page > 0 ? () => _goTo(_page - 1) : null,
                      ),
                      Expanded(
                        child: Text(
                          _monthTitle.format(month),
                          textAlign: TextAlign.center,
                          style: sans(
                            15,
                            weight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ),
                      _NavButton(
                        icon: Icons.chevron_right_rounded,
                        label: 'Next month',
                        onTap: _page < lastPage ? () => _goTo(_page + 1) : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Text(
                            d,
                            textAlign: TextAlign.center,
                            style: sans(11.5, color: c.inkA(.45)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Six rows of square cells fit every month.
                  LayoutBuilder(
                    builder: (context, box) => SizedBox(
                      height: box.maxWidth / 7 * 6,
                      child: PageView.builder(
                        controller: _pages,
                        itemCount: lastPage + 1,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => _MonthGrid(
                          month: _month(i),
                          logged: data.periodDays,
                          predicted: predicted,
                          today: today,
                          onToggle: (key, on) => ref
                              .read(appDataProvider.notifier)
                              .setPeriodDays([key], on),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Legend(color: c.period, label: 'Logged'),
                      const SizedBox(width: 18),
                      _Legend(
                        color: c.periodTint,
                        border: c.period.withValues(alpha: .6),
                        label: 'Estimated',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppCard(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: stats == null
                  ? Text(
                      data.periods.isEmpty
                          ? 'Log your period days to see your cycle here.'
                          : 'Log two periods to see your average cycle and when the next period is likely.',
                      style: sans(13.5, color: c.inkA(.55)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _Stat(
                                value: '${stats.cycleLength}',
                                unit: 'days',
                                label: 'Average cycle',
                              ),
                            ),
                            Expanded(
                              child: _Stat(
                                value: '${stats.periodLength}',
                                unit: stats.periodLength == 1 ? 'day' : 'days',
                                label: 'Average period',
                              ),
                            ),
                          ],
                        ),
                        if (outlook != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            outlook,
                            style: sans(
                              13.5,
                              weight: FontWeight.w500,
                              color: c.ink,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          'Estimates come from your last '
                          '${plural(stats.cycles, 'cycle')}. They are not '
                          'medical advice and not a method of contraception.',
                          style: sans(12, color: c.inkA(.5)),
                        ),
                      ],
                    ),
            ),
            if (data.periods.isNotEmpty) ...[
              const SectionLabel('History'),
              AppCard(
                radius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (var i = data.periods.length - 1; i >= 0; i--)
                      _HistoryRow(
                        period: data.periods[i],
                        cycle: i + 1 < data.periods.length
                            ? dayOrdinal(data.periods[i + 1].start) -
                                  dayOrdinal(data.periods[i].start)
                            : null,
                        divider: i > 0,
                        onTap: () =>
                            _goTo(_index(parseKey(data.periods[i].start))),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.logged,
    required this.predicted,
    required this.today,
    required this.onToggle,
  });

  final DateTime month;
  final Set<String> logged;
  final Set<String> predicted;
  final String today;
  final void Function(String key, bool on) onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lead = month.weekday - DateTime.monday;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final t = dayOrdinal(today);
    return GridView.count(
      crossAxisCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < lead; i++) const SizedBox.shrink(),
        for (var d = 1; d <= days; d++)
          Builder(
            builder: (context) {
              final key = dayKey(DateTime(month.year, month.month, d));
              final isLogged = logged.contains(key);
              final isPredicted = !isLogged && predicted.contains(key);
              final future = dayOrdinal(key) > t;
              final isToday = key == today;
              final fg = isLogged
                  ? c.bg
                  : future && !isPredicted
                  ? c.inkA(.3)
                  : c.ink;
              return Padding(
                padding: const EdgeInsets.all(3),
                child: Semantics(
                  button: !future,
                  selected: isLogged,
                  label: _shortDayYear.format(parseKey(key)),
                  child: Tap(
                    onTap: future ? null : () => onToggle(key, !isLogged),
                    color: isLogged
                        ? c.period
                        : isPredicted
                        ? c.periodTint
                        : Colors.transparent,
                    border: isToday
                        ? Border.all(color: c.ink, width: 1.5)
                        : isPredicted
                        ? Border.all(color: c.period.withValues(alpha: .6))
                        : null,
                    padding: EdgeInsets.zero,
                    child: Center(
                      child: Text(
                        '$d',
                        style: sans(
                          13.5,
                          weight: isLogged || isToday
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: fg,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
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
      color: Colors.transparent,
      semanticLabel: label,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, size: 24, color: onTap == null ? c.inkA(.2) : c.ink),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.border});
  final Color color;
  final Color? border;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border == null ? null : Border.all(color: border!),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: sans(12, color: c.inkA(.6))),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.unit, required this.label});
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: overline(context)),
        const SizedBox(height: 4),
        Row(
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
            const SizedBox(width: 4),
            Text(unit, style: sans(13, color: c.inkA(.5))),
          ],
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.period,
    required this.cycle,
    required this.divider,
    required this.onTap,
  });

  final Period period;

  /// Days from this period's start to the next one's; null for the latest.
  final int? cycle;
  final bool divider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = parseKey(period.start);
    final e = parseKey(period.end);
    final range = period.length == 1
        ? _shortDayYear.format(s)
        : s.year == e.year
        ? '${_shortDay.format(s)} – ${_shortDayYear.format(e)}'
        : '${_shortDayYear.format(s)} – ${_shortDayYear.format(e)}';
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: c.inkA(.06)))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: c.period,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                range,
                style: sans(14, weight: FontWeight.w500, color: c.ink),
              ),
            ),
            Text(
              [
                plural(period.length, 'day'),
                if (cycle != null) '$cycle-day cycle',
              ].join(' · '),
              style: sans(12.5, color: c.inkA(.55)),
            ),
          ],
        ),
      ),
    );
  }
}
