import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/format.dart';
import '../../data/models.dart';
import '../../theme/app_theme.dart';

bool isCupertino(BuildContext context) {
  final p = Theme.of(context).platform;
  return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
}

List<BoxShadow> softShadow(BuildContext context, {bool raised = false}) {
  final s = context.c.shadow;
  return [
    BoxShadow(
      color: s.withValues(alpha: .05),
      blurRadius: 2,
      offset: const Offset(0, 1),
    ),
    if (raised)
      BoxShadow(
        color: s.withValues(alpha: .04),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
  ];
}

/// White rounded surface. Tappable when [onTap] is given.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = 22,
    this.onTap,
    this.raised = false,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool raised;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: br,
        boxShadow: softShadow(context, raised: raised),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: br,
        clipBehavior: Clip.antiAlias,
        child: onTap == null
            ? Padding(padding: padding, child: child)
            : InkWell(
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
      ),
    );
  }
}

/// Generic tappable with ink feedback clipped to a radius.
class Tap extends StatelessWidget {
  const Tap({
    super.key,
    required this.child,
    required this.onTap,
    this.radius = 999,
    this.color = Colors.transparent,
    this.border,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final Color color;
  final BoxBorder? border;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    Widget w = Material(
      color: color,
      borderRadius: br,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: border == null
              ? null
              : BoxDecoration(border: border, borderRadius: br),
          child: child,
        ),
      ),
    );
    if (semanticLabel != null) {
      w = Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: w,
      );
    }
    return w;
  }
}

enum PillStyle {
  dark,
  primary,
  outline,
  white,
  ghost,
  danger,
  dangerSolid,
  disabled,
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    required this.onTap,
    this.style = PillStyle.outline,
    this.fontSize = 13.5,
    this.padding = const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
    this.weight = FontWeight.w500,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final PillStyle style;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final FontWeight weight;

  /// Overrides the text colour (ghost/outline pills).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, border) = switch (style) {
      PillStyle.dark => (c.chipOnBg, c.chipOnFg, null),
      PillStyle.primary => (c.primary, c.onPrimary, null),
      PillStyle.outline => (
        Colors.transparent,
        c.ink,
        Border.all(color: c.inkA(.14)),
      ),
      PillStyle.white => (c.surface, c.ink, null),
      PillStyle.ghost => (Colors.transparent, c.ink, null),
      PillStyle.danger => (c.surface, c.danger, null),
      PillStyle.dangerSolid => (c.danger, Colors.white, null),
      PillStyle.disabled => (c.inkA(.1), c.inkA(.4), null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: style == PillStyle.white || style == PillStyle.danger
            ? softShadow(context)
            : null,
      ),
      child: Tap(
        onTap: onTap,
        color: bg,
        border: border,
        padding: padding,
        child: Text(
          label,
          style: sans(fontSize, weight: weight, color: color ?? fg),
        ),
      ),
    );
  }
}

/// Filter / meal-type chip.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      selected: selected,
      button: true,
      child: Tap(
        onTap: onTap,
        color: selected ? c.chipOnBg : c.surface,
        border: Border.all(color: selected ? Colors.transparent : c.inkA(.14)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Text(
          label,
          style: sans(
            13.5,
            weight: FontWeight.w500,
            color: selected ? c.chipOnFg : c.inkA(.7),
          ),
        ),
      ),
    );
  }
}

InputDecoration fieldDecoration(
  BuildContext context, {
  String? hint,
  double radius = 14,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  ),
  Color? fill,
}) {
  final c = context.c;
  OutlineInputBorder b(Color col, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(radius),
    borderSide: BorderSide(color: col, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: sans(14.5, color: c.inkA(.38)),
    isDense: true,
    filled: true,
    fillColor: fill ?? c.surface,
    contentPadding: padding,
    enabledBorder: b(c.inkA(.12)),
    border: b(c.inkA(.12)),
    focusedBorder: b(c.primary.withValues(alpha: .6), 2),
  );
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.fontSize = 14.5,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.maxLines = 1,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.semanticLabel,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final double fontSize;
  final double radius;
  final EdgeInsetsGeometry padding;
  final int maxLines;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: maxLines > 1 ? maxLines : null,
      autofocus: autofocus,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      style: sans(fontSize, color: context.c.ink),
      decoration: fieldDecoration(
        context,
        hint: hint,
        radius: radius,
        padding: padding,
      ),
    );
    return semanticLabel == null
        ? field
        : Semantics(label: semanticLabel, child: field);
  }
}

final decimalOnly = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
final digitsOnly = [FilteringTextInputFormatter.digitsOnly];

/// Field label above an input ("DATE", "QTY").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.small = false});
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: small ? 3 : 5),
    child: Text(
      small ? text : text.toUpperCase(),
      style: small ? sans(10.5, color: context.c.inkA(.45)) : overline(context),
    ),
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(0, 20, 0, 7),
  });
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(text.toUpperCase(), style: overline(context)),
  );
}

class InfoBanner extends StatelessWidget {
  const InfoBanner.error(this.text, {super.key}) : warn = false;
  const InfoBanner.warn(this.text, {super.key}) : warn = true;
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: warn ? c.warnBg : c.errorBg,
        borderRadius: BorderRadius.circular(warn ? 16 : 13),
      ),
      child: Text(
        text,
        style: sans(13.5, color: warn ? c.warnText : c.errorText, height: 1.45),
      ),
    );
  }
}

/// Dashed outline box used for empty states and "+ Add" actions.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    this.radius = 16,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.fill,
  });

  final Widget child;
  final double radius;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return CustomPaint(
      foregroundPainter: _DashedBorderPainter(c.inkA(.2), radius),
      child: Tap(
        onTap: onTap,
        radius: radius,
        color: fill ?? Colors.transparent,
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(.5),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Rounded-square badge with the meal type's initial.
class MealBadge extends StatelessWidget {
  const MealBadge(this.name, {super.key, this.size = 34});

  /// Meal type name; the badge shows its first character (emoji included).
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.greenTint,
        borderRadius: BorderRadius.circular(size * .35),
      ),
      child: Text(
        name.isEmpty ? '·' : name.characters.first.toUpperCase(),
        style: sans(size * .38, weight: FontWeight.w700, color: c.greenText),
      ),
    );
  }
}

/// Header row for bottom sheets: Cancel · Title · Save.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    super.key,
    required this.title,
    required this.onCancel,
    required this.onSave,
    required this.canSave,
  });

  final String title;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final bool canSave;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.inkA(.07))),
      ),
      child: Row(
        children: [
          Tap(
            onTap: onCancel,
            radius: 10,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text('Cancel', style: sans(14.5, color: c.inkA(.55))),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: sans(15.5, weight: FontWeight.w700, color: c.ink),
            ),
          ),
          Pill(
            label: 'Save',
            onTap: onSave,
            style: canSave ? PillStyle.primary : PillStyle.disabled,
            fontSize: 14,
            weight: FontWeight.w700,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ],
      ),
    );
  }
}

// ---- Native pickers --------------------------------------------------------

/// Read-only field that looks like an input and opens a picker on tap.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.text,
    required this.onTap,
    this.radius = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    this.fontSize = 14.5,
    this.semanticLabel,
  });

  final String text;
  final VoidCallback onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      label: semanticLabel,
      value: text,
      excludeSemantics: true,
      child: Tap(
        onTap: onTap,
        radius: radius,
        color: c.surface,
        border: Border.all(color: c.inkA(.12)),
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(fontSize, color: c.ink),
              ),
            ),
            Icon(Icons.unfold_more_rounded, size: 16, color: c.inkA(.35)),
          ],
        ),
      ),
    );
  }
}

/// Returns the chosen index, or null when dismissed.
Future<int?> _cupertinoWheel<T>(
  BuildContext context, {
  required List<T> values,
  required T initial,
  required String Function(T) label,
}) {
  var index = values.indexOf(initial).clamp(0, values.length - 1);
  return showCupertinoModalPopup<int>(
    context: context,
    builder: (ctx) => _CupertinoPopup(
      onDone: () => Navigator.pop(ctx, index),
      child: CupertinoPicker(
        itemExtent: 36,
        scrollController: FixedExtentScrollController(initialItem: index),
        onSelectedItemChanged: (i) => index = i,
        children: [for (final v in values) Center(child: Text(label(v)))],
      ),
    ),
  );
}

class _CupertinoPopup extends StatelessWidget {
  const _CupertinoPopup({required this.child, required this.onDone});
  final Widget child;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      height: 280,
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: onDone,
                child: Text(
                  'Done',
                  style: sans(16, weight: FontWeight.w700, color: c.primary),
                ),
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: CupertinoThemeData(
                  brightness: Theme.of(context).brightness,
                  textTheme: CupertinoTextThemeData(
                    pickerTextStyle: sans(20, color: c.ink),
                    dateTimePickerTextStyle: sans(20, color: c.ink),
                  ),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Unit picker: wheel on iOS, menu on Android. [allowNone] adds a "None" row.
class UnitPicker extends StatelessWidget {
  const UnitPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowNone = false,
    this.radius = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    this.fontSize = 14.5,
  });

  final FoodUnit? value;
  final ValueChanged<FoodUnit?> onChanged;
  final bool allowNone;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double fontSize;

  List<FoodUnit?> get _values => [if (allowNone) null, ...FoodUnit.values];
  String _label(FoodUnit? u) => u?.label ?? 'None';

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      return PickerField(
        text: _label(value),
        radius: radius,
        padding: padding,
        fontSize: fontSize,
        semanticLabel: 'Unit',
        onTap: () async {
          final values = _values;
          final i = await _cupertinoWheel<FoodUnit?>(
            context,
            values: values,
            initial: value,
            label: _label,
          );
          if (i != null && values[i] != value) onChanged(values[i]);
        },
      );
    }
    final c = context.c;
    return DropdownButtonFormField<FoodUnit?>(
      initialValue: value,
      isExpanded: true,
      isDense: true,
      icon: Icon(Icons.unfold_more_rounded, size: 16, color: c.inkA(.35)),
      dropdownColor: c.surface,
      borderRadius: BorderRadius.circular(14),
      style: sans(fontSize, color: c.ink),
      decoration: fieldDecoration(context, radius: radius, padding: padding),
      items: [
        for (final u in _values)
          DropdownMenuItem(value: u, child: Text(_label(u))),
      ],
      onChanged: onChanged,
    );
  }
}

/// Earliest date any picker offers.
final firstPickableDate = DateTime(2000);

/// [last] defaults to a year from now.
Future<String?> pickDate(
  BuildContext context,
  String current, {
  DateTime? last,
}) async {
  final initial = parseKey(current);
  final first = firstPickableDate;
  last ??= DateTime.now().add(const Duration(days: 365));
  if (isCupertino(context)) {
    var picked = initial;
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => _CupertinoPopup(
        onDone: () => Navigator.pop(ctx, true),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: initial,
          minimumDate: first,
          maximumDate: last,
          onDateTimeChanged: (d) => picked = d,
        ),
      ),
    );
    return ok == true ? dayKey(picked) : null;
  }
  final d = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
  );
  return d == null ? null : dayKey(d);
}

Future<String?> pickTime(BuildContext context, String current) async {
  final (h, m) = parseTime(current);
  if (isCupertino(context)) {
    var picked = DateTime(2000, 1, 1, h, m);
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => _CupertinoPopup(
        onDone: () => Navigator.pop(ctx, true),
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: picked,
          onDateTimeChanged: (d) => picked = d,
        ),
      ),
    );
    return ok == true ? timeKey(picked.hour, picked.minute) : null;
  }
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: h, minute: m),
  );
  return t == null ? null : timeKey(t.hour, t.minute);
}

/// Platform-styled yes/no confirmation.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = true,
}) async {
  final r = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) {
      final cupertino = isCupertino(ctx);
      Widget btn(
        String label,
        bool value, {
        bool isDefault = false,
        bool danger = false,
      }) => cupertino
          ? CupertinoDialogAction(
              isDefaultAction: isDefault,
              isDestructiveAction: danger,
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(label),
            )
          : TextButton(
              onPressed: () => Navigator.pop(ctx, value),
              style: danger
                  ? TextButton.styleFrom(foregroundColor: ctx.c.danger)
                  : null,
              child: Text(label),
            );
      return AlertDialog.adaptive(
        title: Text(title),
        content: Text(message),
        actions: [
          btn('Cancel', false, isDefault: true),
          btn(action, true, danger: destructive),
        ],
      );
    },
  );
  return r ?? false;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}
