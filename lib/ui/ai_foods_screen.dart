import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoDialogAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/clipboard.dart';
import '../data/food_csv.dart';
import '../data/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'widgets/common.dart';

Future<void> openAiFoods(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AiFoodsScreen()));

/// Meal Items → Ask AI: copy a prompt for ChatGPT, Claude or Gemini, then
/// paste the reply back. Helpings itself never goes online.
class AiFoodsScreen extends ConsumerWidget {
  const AiFoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final blanks = data.items.where((i) => i.defaultCalories == null).length;

    Widget step({
      required String number,
      required String title,
      required String body,
      required List<Widget> actions,
    }) => AppCard(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.greenTint,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  number,
                  style: sans(
                    12.5,
                    weight: FontWeight.w700,
                    color: c.greenText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: sans(15.5, weight: FontWeight.w600, color: c.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(body, style: sans(13.5, color: c.inkA(.6), height: 1.45)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );

    Future<void> copy(String prompt) async {
      try {
        await ref.read(clipboardProvider).copy(prompt);
        if (context.mounted) {
          toast(
            context,
            'Prompt copied. Paste it into ChatGPT, Claude or Gemini.',
          );
        }
      } catch (e) {
        debugPrint('Copy failed: $e');
        if (context.mounted) toast(context, "Couldn't copy the prompt.");
      }
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            const Align(alignment: Alignment.centerLeft, child: BackDot()),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 14, 6, 4),
              child: Text('Ask an AI', style: serif(32, color: c.ink)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Text(
                'Let ChatGPT, Claude or Gemini build your food list or fill in '
                'missing calories. It asks you about what you eat first. You '
                'copy a prompt, paste it into the chat, then paste the reply '
                'back here.',
                style: sans(13.5, color: c.inkA(.55), height: 1.45),
              ),
            ),
            step(
              number: '1',
              title: 'Copy a prompt',
              body:
                  'Starter list: the chat asks where you live, which cuisines '
                  'you eat, veg or non-veg, home-cooked or eating out, then '
                  'suggests foods with calories.\n'
                  'Missing calories: sends your ${plural(data.items.length, 'food')}'
                  '${blanks == 0 ? '' : ' ($blanks without calories)'}; the chat '
                  'asks about portions and cooking, then fills in the blanks.',
              actions: [
                Pill(
                  label: 'Build a starter list',
                  style: PillStyle.primary,
                  onTap: () => copy(buildStarterPrompt(data)),
                ),
                Pill(
                  label: 'Fill in calories',
                  style: PillStyle.primary,
                  onTap: () => copy(buildFillPrompt(data)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            step(
              number: '2',
              title: 'Chat, then copy its reply',
              body:
                  'Paste the prompt into the chat and answer its questions. '
                  'When it gives you the final list, copy the whole reply.',
              actions: const [],
            ),
            const SizedBox(height: 12),
            step(
              number: '3',
              title: 'Paste the reply here',
              body:
                  'Helpings backs up all your data first, then shows every '
                  'change for you to review. Nothing changes until you '
                  'tap Import.',
              actions: [
                Pill(
                  label: 'Paste reply',
                  style: PillStyle.primary,
                  onTap: () => importFoodList(context, ref, fromFile: false),
                ),
                Pill(
                  label: 'Import a CSV file',
                  onTap: () => importFoodList(context, ref, fromFile: true),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
              child: Text(
                'Helpings stays offline. Your food list only leaves the phone '
                'when you paste it into a chat yourself. Calories from a chat '
                'are its estimates: check the ones that matter to you.',
                style: sans(12, color: c.inkA(.42), height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round back button used at the top of pushed screens.
class BackDot extends StatelessWidget {
  const BackDot({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return DecoratedBox(
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
          child: Icon(Icons.chevron_left_rounded, size: 24, color: c.ink),
        ),
      ),
    );
  }
}

// ---- Import ----------------------------------------------------------------

/// Backs up all data, then reads a food list from the clipboard (or a
/// file) and opens the review screen. Nothing is read until the backup
/// has been saved.
Future<void> importFoodList(
  BuildContext context,
  WidgetRef ref, {
  required bool fromFile,
}) async {
  final where = await _backupFirst(context, ref);
  if (where == null || !context.mounted) return;
  String? text;
  try {
    text = fromFile
        ? await ref.read(foodCsvPickerProvider)()
        : await ref.read(clipboardProvider).paste();
  } catch (e) {
    debugPrint('Reading the food list failed: $e');
    if (context.mounted) {
      toast(
        context,
        fromFile ? "Couldn't open that file." : "Couldn't read the clipboard.",
      );
    }
    return;
  }
  if (!context.mounted) return;
  if (text == null || text.trim().isEmpty) {
    if (!fromFile) {
      toast(context, 'The clipboard is empty. Copy the chat’s reply first.');
    }
    return;
  }
  final FoodImport imp;
  try {
    imp = parseFoodCsv(text, ref.read(appDataProvider).requireValue);
  } on FoodCsvException catch (e) {
    toast(context, e.message);
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FoodImportScreen(import: imp, backedUpTo: where),
    ),
  );
}

enum _BackupChoice { cancel, appFolder, chooseFolder }

/// Saves a full backup before an import. With no backup folder set, first
/// asks whether to choose one or use the app's own folder. Returns where
/// the backup went, or null if the import must not go ahead.
Future<String?> _backupFirst(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(appDataProvider.notifier);
  var toApp = false;
  if (ref.read(appDataProvider).requireValue.autoBackup == null) {
    final choice = await showAdaptiveDialog<_BackupChoice>(
      context: context,
      builder: (ctx) {
        Widget btn(String label, _BackupChoice v, {bool isDefault = false}) =>
            isCupertino(ctx)
            ? CupertinoDialogAction(
                isDefaultAction: isDefault,
                onPressed: () => Navigator.pop(ctx, v),
                child: Text(label),
              )
            : TextButton(
                onPressed: () => Navigator.pop(ctx, v),
                child: Text(label),
              );
        return AlertDialog.adaptive(
          title: const Text('Back up before importing'),
          content: const Text(
            'Helpings saves a full copy of your data before importing. You '
            'haven’t chosen a backup folder, so it will go to the app’s own '
            'folder (Android/data/…/files/backups). That folder is deleted '
            'if you uninstall the app.\n\n'
            'Choosing a folder also turns on daily backups.',
          ),
          actions: [
            btn('Cancel', _BackupChoice.cancel),
            btn('Choose folder', _BackupChoice.chooseFolder),
            btn('Use app folder', _BackupChoice.appFolder, isDefault: true),
          ],
        );
      },
    );
    switch (choice) {
      case null || _BackupChoice.cancel:
        return null;
      case _BackupChoice.chooseFolder:
        if (!await notifier.chooseAutoBackupFolder()) return null;
      case _BackupChoice.appFolder:
        toApp = true;
    }
  }
  try {
    return await notifier.backupBeforeImport(toAppFolder: toApp);
  } on ImportBackupException catch (e) {
    if (!context.mounted) return null;
    if (!toApp) {
      final ok = await confirm(
        context,
        title: 'Couldn’t back up',
        message:
            '${e.message} Save the backup to the app’s own folder instead? '
            'It’s deleted if you uninstall the app.',
        action: 'Use app folder',
        destructive: false,
      );
      if (ok) {
        try {
          return await notifier.backupBeforeImport(toAppFolder: true);
        } on ImportBackupException catch (e2) {
          if (context.mounted) {
            toast(context, '${e2.message} Nothing was imported.');
          }
          return null;
        }
      }
      if (context.mounted) toast(context, 'Nothing was imported.');
      return null;
    }
    toast(context, '${e.message} Nothing was imported.');
    return null;
  }
}

/// Review of a pasted food list: tick what to import.
class FoodImportScreen extends ConsumerStatefulWidget {
  const FoodImportScreen({
    super.key,
    required this.import,
    required this.backedUpTo,
  });

  final FoodImport import;

  /// Where the pre-import backup was saved.
  final String backedUpTo;

  @override
  ConsumerState<FoodImportScreen> createState() => _FoodImportScreenState();
}

class _FoodImportScreenState extends ConsumerState<FoodImportScreen> {
  late final Set<int> _selected = {
    for (final (i, r) in widget.import.rows.indexed)
      if (r.selectedByDefault) i,
  };
  bool _busy = false;

  List<ImportRow> get _rows => widget.import.rows;

  Future<void> _apply() async {
    setState(() => _busy = true);
    final notifier = ref.read(appDataProvider.notifier);
    final chosen = [for (final i in _selected) _rows[i]];
    final FoodImportResult result;
    try {
      result = await notifier.importFoods(chosen);
    } on DuplicateNameException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e Nothing was imported.');
      }
      return;
    } catch (e) {
      debugPrint('Food import failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        toast(context, "Couldn't import the food list.");
      }
      return;
    }
    var filled = 0;
    final fillable = await notifier.importFillable(result);
    final n = fillable.fold(0, (s, f) => s + f.$2.length);
    if (n > 0 && mounted) {
      final ok = await confirm(
        context,
        title: 'Fill in past meals?',
        message:
            '${plural(n, 'logged line')} of these foods '
            '${n == 1 ? 'has' : 'have'} no calories. Fill '
            '${n == 1 ? 'it' : 'them'} in from the new values, scaled by '
            'quantity? Lines that already have calories stay as they are.',
        action: 'Fill in',
        cancel: 'Leave as is',
        destructive: false,
      );
      if (ok) filled = await notifier.fillImportedLines(fillable);
    }
    if (!mounted) return;
    final parts = [
      if (result.created.isNotEmpty)
        'added ${plural(result.created.length, 'food')}',
      if (result.after.isNotEmpty)
        'updated ${plural(result.after.length, 'food')}',
      if (filled > 0) 'filled in ${plural(filled, 'past line')}',
    ].join(', ');
    final messenger = ScaffoldMessenger.of(context);
    toastWithUndo(
      context,
      parts.isEmpty
          ? 'Nothing changed'
          : parts[0].toUpperCase() + parts.substring(1),
      onUndo: () async {
        await notifier.undoImportFoods(result);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Import undone'),
              duration: Duration(seconds: 2),
            ),
          );
      },
    );
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final imp = widget.import;
    final unchanged = imp.of(ImportKind.unchanged).length;
    final skipped = imp.of(ImportKind.skipped).toList();

    Widget group(ImportKind kind, String label, [String? note]) {
      final entries = [
        for (final (i, r) in _rows.indexed)
          if (r.kind == kind) (i, r),
      ];
      if (entries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('$label · ${entries.length}'),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(note, style: sans(12.5, color: c.inkA(.5))),
            ),
          AppCard(
            radius: 20,
            child: Column(
              children: [
                for (final (n, (i, r)) in entries.indexed)
                  _ImportTile(
                    row: r,
                    selected: _selected.contains(i),
                    showDivider: n > 0,
                    onChanged: _busy
                        ? null
                        : (v) => setState(
                            () => v ? _selected.add(i) : _selected.remove(i),
                          ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final count = _selected.length;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: BackDot(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 10),
                    child: Text(
                      'Review import',
                      style: serif(32, color: c.ink),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: c.greenTint,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Your data was backed up to ${widget.backedUpTo}.',
                      style: sans(13, color: c.greenText, height: 1.45),
                    ),
                  ),
                  group(ImportKind.newFood, 'New foods'),
                  group(ImportKind.newCalories, 'Calories filled in'),
                  group(
                    ImportKind.changed,
                    'Would change',
                    'These replace calories you already have, so they start '
                        'unticked.',
                  ),
                  if (unchanged > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 0),
                      child: Text(
                        '${plural(unchanged, 'food')} unchanged or left blank.',
                        style: sans(13, color: c.inkA(.5)),
                      ),
                    ),
                  if (skipped.isNotEmpty) ...[
                    SectionLabel('Skipped · ${skipped.length}'),
                    AppCard(
                      radius: 20,
                      child: Column(
                        children: [
                          for (final (n, r) in skipped.indexed)
                            _ImportTile(
                              row: r,
                              selected: false,
                              showDivider: n > 0,
                              onChanged: null,
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (!imp.hasChanges)
                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: InfoBanner.warn(
                        'Nothing to import: every food is unchanged or was '
                        'skipped.',
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
              child: SizedBox(
                width: double.infinity,
                child: Pill(
                  expand: true,
                  label: count == 0
                      ? 'Import'
                      : 'Import ${plural(count, 'food')}',
                  style: count == 0 || _busy
                      ? PillStyle.disabled
                      : PillStyle.primary,
                  onTap: count == 0 || _busy ? null : _apply,
                  fontSize: 15,
                  weight: FontWeight.w700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({
    required this.row,
    required this.selected,
    required this.showDivider,
    required this.onChanged,
  });

  final ImportRow row;
  final bool selected;
  final bool showDivider;
  final ValueChanged<bool>? onChanged;

  static String _value(double? cal, FoodUnit? unit) {
    final kcal = cal == null ? 'No calories' : '${fmtQty(cal)} kcal';
    return unit == null ? kcal : '$kcal / ${unit.name}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = row;
    final detail = switch (r.kind) {
      ImportKind.skipped => r.reason ?? '',
      ImportKind.changed =>
        '${_value(r.item!.defaultCalories, r.item!.defaultUnit)}'
            ' → ${_value(r.calories, r.unit)}',
      _ => _value(r.calories, r.unit),
    };
    final skipped = r.kind == ImportKind.skipped;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        child: Container(
          padding: EdgeInsets.fromLTRB(skipped ? 16 : 4, 8, 14, 10),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(top: BorderSide(color: c.inkA(.06)))
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!skipped)
                Checkbox.adaptive(
                  value: selected,
                  onChanged: onChanged == null
                      ? null
                      : (v) => onChanged!(v ?? false),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: skipped ? 4 : 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: sans(
                          15,
                          weight: FontWeight.w500,
                          color: skipped ? c.inkA(.5) : c.ink,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text.rich(
                        TextSpan(
                          text: detail,
                          children: [
                            if (r.newUnit)
                              TextSpan(
                                text: '  New unit',
                                style: sans(
                                  11.5,
                                  weight: FontWeight.w600,
                                  color: c.greenText,
                                ),
                              ),
                          ],
                        ),
                        style: sans(13, color: skipped ? c.danger : c.inkA(.6)),
                      ),
                      if (r.notes.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            r.notes,
                            style: sans(12, color: c.inkA(.45), height: 1.4),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
