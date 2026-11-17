import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'health_sheets.dart';
import 'shell.dart';
import 'widgets/common.dart';
import 'widgets/day_header.dart';
import 'widgets/series_chart.dart';

/// Which day Health shows, as days before today (0 = today).
final healthDayProvider = NotifierProvider<HealthDay, int>(HealthDay.new);

class HealthDay extends Notifier<int> {
  @override
  int build() => 0;
  void show(int daysAgo) => state = daysAgo;
}

/// The optional trackers turned on in Settings, one page per day like Home.
class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  late final PageController _pages;

  @override
  void initState() {
    super.initState();
    _pages = PageController(initialPage: ref.read(healthDayProvider));
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  int get _pageCount => daysAgo(dayKey(firstPickableDate)) + 1;

  void _goTo(int ago) {
    if (!_pages.hasClients) return;
    final from = _pages.page?.round() ?? 0;
    if ((ago - from).abs() <= 3) {
      _pages.animateToPage(
        ago,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _pages.jumpToPage(ago);
    }
  }

  Future<void> _pick(String current) async {
    final picked = await pickDate(context, current, last: DateTime.now());
    if (picked == null) return;
    final ago = daysAgo(picked);
    if (ago >= 0) _goTo(ago);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    if (!data.healthOn) return const SizedBox.shrink();
    final offset = ref.watch(healthDayProvider);
    final key = shiftKey(-offset);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DayHeader(
            daysAgo: offset,
            onPick: () => _pick(key),
            onToday: () => _goTo(0),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              reverse: true,
              itemCount: _pageCount,
              onPageChanged: ref.read(healthDayProvider.notifier).show,
              itemBuilder: (context, i) => _HealthDayView(day: shiftKey(-i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthDayView extends ConsumerWidget {
  const _HealthDayView({required this.day});
  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, shellBottomInset(context) + 72),
      children: [
        if (data.trackWater) _WaterCard(day: day, data: data),
        if (data.trackSugar) _SugarCard(day: day, data: data),
        if (data.trackWeight) _WeightCard(day: day, data: data),
      ],
    );
  }
}

/// Card with a coloured title row; [trailing] sits on the right.
class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.title,
    required this.color,
    required this.child,
    this.trailing,
  });

  final String title;
  final Color color;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: sans(15.5, weight: FontWeight.w600, color: c.ink),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

Widget _addPill(String label, VoidCallback onTap) => Pill(
  label: label,
  onTap: onTap,
  fontSize: 13,
  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
);

/// Big number with a smaller unit after it.
Widget _bigValue(BuildContext context, String value, String unit) {
  final c = context.c;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: sans(
          30,
          weight: FontWeight.w700,
          color: c.ink,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(width: 5),
      Text(unit, style: sans(13, color: c.inkA(.5))),
    ],
  );
}

Widget _caption(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 8),
  child: Text(text.toUpperCase(), style: overline(context)),
);

final _weekday = DateFormat('E', 'en_US');

/// "yesterday" / "on November 12".
String _lastWeighed(String date) {
  final l = dayGroupLabel(date);
  return l == 'Yesterday' ? 'yesterday' : 'on $l';
}

// ---- Water ------------------------------------------------------------------

class _WaterCard extends ConsumerWidget {
  const _WaterCard({required this.day, required this.data});
  final String day;
  final AppData data;

  Future<void> _add(BuildContext context, WidgetRef ref, double ml) async {
    final notifier = ref.read(appDataProvider.notifier);
    final entry = WaterEntry(
      id: newId(),
      date: day,
      time: defaultTimeFor(day),
      ml: ml,
    );
    await notifier.saveWater(entry);
    if (!context.mounted) return;
    final u = data.waterUnit;
    toastWithUndo(
      context,
      'Added ${u.format(ml)} ${u.label} of water.',
      onUndo: () => notifier.deleteWater(entry.id),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    WaterEntry w,
  ) async {
    final notifier = ref.read(appDataProvider.notifier);
    await notifier.deleteWater(w.id);
    if (!context.mounted) return;
    final u = data.waterUnit;
    toastWithUndo(
      context,
      'Removed ${u.format(w.ml)} ${u.label}.',
      onUndo: () => notifier.saveWater(w),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final u = data.waterUnit;
    final total = data.waterTotal(day);
    final goal = data.waterGoalMl;
    final entries = data.waterOn(day);
    final note = goal == null
        ? 'No daily goal set'
        : total >= goal
        ? 'Goal of ${u.format(goal)} ${u.label} reached'
        : '${u.format(goal - total)} ${u.label} to go of ${u.format(goal)}';
    final week = [for (var i = 6; i >= 0; i--) shiftKey(-i, parseKey(day))];

    return _TrackerCard(
      title: 'Water',
      color: c.water,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Ring(
                progress: goal == null ? null : total / goal,
                color: c.water,
                track: c.inkA(.07),
                label: goal == null
                    ? '${entries.length}×'
                    : '${(total / goal * 100).round()}%',
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _bigValue(context, u.format(total), u.label),
                    ),
                    const SizedBox(height: 2),
                    Text(note, style: sans(12, color: c.inkA(.5))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final p in u.presets) ...[
                Expanded(
                  child: Pill(
                    label: '+${u.format(p)} ${u.label}',
                    expand: true,
                    color: c.water,
                    onTap: () => _add(context, ref, p),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Pill(
                  label: 'Custom',
                  expand: true,
                  onTap: () async {
                    final v = await promptNumber(
                      context,
                      title: 'Add water',
                      action: 'Add',
                      unit: u.label,
                    );
                    if (v != null && context.mounted) {
                      await _add(context, ref, u.fromDisplay(v));
                    }
                  },
                ),
              ),
            ],
          ),
          if (entries.isNotEmpty) ...[
            _caption(context, 'Logged · tap to remove'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in entries.reversed)
                  Tap(
                    onTap: () => _remove(context, ref, w),
                    color: c.waterTint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    semanticLabel:
                        'Remove ${u.format(w.ml)} ${u.label} at '
                        '${fmtTime(w.time)}',
                    child: Text(
                      '${fmtTime(w.time)} · ${u.format(w.ml)} ${u.label}',
                      style: sans(12, weight: FontWeight.w500, color: c.ink),
                    ),
                  ),
              ],
            ),
          ],
          _caption(context, 'Last 7 days'),
          DailyBars(
            values: [for (final d in week) u.toDisplay(data.waterTotal(d))],
            labels: [for (final d in week) _weekday.format(parseKey(d))[0]],
            goal: goal == null ? null : u.toDisplay(goal),
            color: c.water,
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({
    required this.progress,
    required this.color,
    required this.track,
    required this.label,
  });

  /// 0..1+, or null to draw just the track.
  final double? progress;
  final Color color;
  final Color track;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 72,
    child: CustomPaint(
      painter: _RingPainter(progress ?? 0, color, track),
      child: Center(
        child: Text(
          label,
          style: sans(14, weight: FontWeight.w600, color: context.c.ink),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color, this.track);
  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(
      r,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (progress <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.track != track;
}

// ---- Blood sugar ------------------------------------------------------------

class _SugarCard extends StatelessWidget {
  const _SugarCard({required this.day, required this.data});
  final String day;
  final AppData data;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final u = data.sugarUnit;
    final readings = data.sugarOn(day);
    final first = shiftKey(-13, parseKey(day));
    final recent = [
      for (final s in data.sugar)
        if (s.date.compareTo(first) >= 0 && s.date.compareTo(day) <= 0)
          SeriesPoint(date: s.date, time: s.time, value: u.toDisplay(s.mgdl)),
    ];

    return _TrackerCard(
      title: 'Blood sugar',
      color: c.sugar,
      trailing: _addPill('+ Add', () => showSugarSheet(context, date: day)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (readings.isEmpty)
            Text(
              'No readings on this day.',
              style: sans(13.5, color: c.inkA(.5)),
            ),
          for (final (i, s) in readings.indexed)
            Tap(
              onTap: () => showSugarSheet(context, date: day, editing: s),
              radius: 10,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: c.inkA(.06))),
                ),
                padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 70,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          fmtTime(s.time),
                          style: sans(12.5, color: c.inkA(.5)),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                u.format(s.mgdl),
                                style: sans(
                                  20,
                                  weight: FontWeight.w700,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(u.label, style: sans(12, color: c.inkA(.5))),
                            ],
                          ),
                          if (s.note.isNotEmpty)
                            Text(s.note, style: sans(12.5, color: c.inkA(.55))),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: c.sugarTint,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        s.context.label,
                        style: sans(
                          11.5,
                          weight: FontWeight.w500,
                          color: c.sugar,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (recent.isNotEmpty) ...[
            _caption(context, 'Last 14 days'),
            SeriesChart(
              key: ValueKey('sugar-$day-${u.name}'),
              points: recent,
              first: first,
              last: day,
              color: c.sugar,
              format: (v) => v.toStringAsFixed(u.digits),
              unit: u.label,
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Weight -----------------------------------------------------------------

class _WeightCard extends StatefulWidget {
  const _WeightCard({required this.day, required this.data});
  final String day;
  final AppData data;

  @override
  State<_WeightCard> createState() => _WeightCardState();
}

class _WeightCardState extends State<_WeightCard> {
  int _range = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final data = widget.data;
    final day = widget.day;
    final u = data.weightUnit;
    final latest = data.weightAsOf(day);
    final onDay = data.weight.where((w) => w.date == day).toList();

    String? change(int days) {
      if (latest == null) return null;
      final prior = data.weightAsOf(shiftKey(-days, parseKey(latest.date)));
      if (prior == null) return null;
      final d = u.formatChange(latest.kg - prior.kg);
      return d == '0'
          ? 'no change in $days days'
          : '$d ${u.label} in $days days';
    }

    final changes = [change(7), change(30)].nonNulls.join(' · ');
    final first = shiftKey(-(_range - 1), parseKey(day));
    final points = [
      for (final w in data.weight)
        if (w.date.compareTo(first) >= 0 && w.date.compareTo(day) <= 0)
          SeriesPoint(date: w.date, time: w.time, value: u.toDisplay(w.kg)),
    ];

    return _TrackerCard(
      title: 'Weight',
      color: c.weight,
      trailing: _addPill('+ Add', () => showWeightSheet(context, date: day)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (latest == null)
            Text('No weigh-ins yet.', style: sans(13.5, color: c.inkA(.5)))
          else ...[
            _bigValue(context, u.format(latest.kg), u.label),
            const SizedBox(height: 2),
            Text(
              [
                latest.date == day
                    ? 'Weighed at ${fmtTime(latest.time)}'
                    : 'Last weighed ${_lastWeighed(latest.date)}',
                if (changes.isNotEmpty) changes,
              ].join(' · '),
              style: sans(12, color: c.inkA(.5)),
            ),
          ],
          if (onDay.isNotEmpty) ...[
            _caption(context, 'This day · tap to edit'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in onDay)
                  Tap(
                    onTap: () =>
                        showWeightSheet(context, date: day, editing: w),
                    color: c.weightTint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      '${fmtTime(w.time)} · ${u.format(w.kg)} ${u.label}'
                      '${w.note.isEmpty ? '' : ' · ${w.note}'}',
                      style: sans(12, weight: FontWeight.w500, color: c.ink),
                    ),
                  ),
              ],
            ),
          ],
          if (data.weight.length > 1) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text('TREND', style: overline(context))),
                  for (final r in const [30, 90]) ...[
                    const SizedBox(width: 6),
                    AppChip(
                      label: '$r days',
                      selected: _range == r,
                      onTap: () => setState(() => _range = r),
                    ),
                  ],
                ],
              ),
            ),
            if (points.length > 1)
              SeriesChart(
                key: ValueKey('weight-$day-$_range-${u.name}'),
                points: points,
                first: first,
                last: day,
                color: c.weight,
                line: true,
                format: (v) => v.toStringAsFixed(v.abs() >= 100 ? 0 : 1),
                unit: u.label,
              )
            else
              Text(
                'Log a few more weigh-ins to see a trend.',
                style: sans(13, color: c.inkA(.5)),
              ),
          ],
        ],
      ),
    );
  }
}
