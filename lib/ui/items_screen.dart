import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/format.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'item_sheet.dart';
import 'shell.dart';
import 'widgets/common.dart';

class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _create(String name) async {
    final saved = await showItemSheet(context, presetName: name);
    if (saved != null && mounted) {
      _query.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(appDataProvider).requireValue;
    final c = context.c;
    final q = _query.text.trim().toLowerCase();
    final items =
        data.items
            .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) {
            if (a.active != b.active) return a.active ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
    final exact = data.items.any((i) => i.name.toLowerCase() == q);

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('Meal Items', style: serif(32, color: c.ink)),
                ),
                Pill(
                  label: '+ New',
                  style: PillStyle.dark,
                  onTap: () => _create(''),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: AppTextField(
              controller: _query,
              hint: 'Search food items',
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                16,
                10,
                16,
                shellBottomInset(context) - 60,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    plural(items.length, 'item').toUpperCase(),
                    style: overline(context, spacing: .12),
                  ),
                ),
                if (items.isNotEmpty)
                  AppCard(
                    radius: 20,
                    child: Column(
                      children: [
                        for (final (i, item) in items.indexed)
                          _ItemRow(
                            item: item,
                            showDivider: i > 0,
                            onEdit: () => showItemSheet(context, editing: item),
                            onToggle: () => ref
                                .read(appDataProvider.notifier)
                                .setItemActive(item.id, !item.active),
                          ),
                      ],
                    ),
                  ),
                if (q.isNotEmpty && !exact)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: DashedBox(
                      radius: 18,
                      onTap: () => _create(_query.text.trim()),
                      child: Text(
                        '+ Create “${_query.text.trim()}”',
                        textAlign: TextAlign.center,
                        style: sans(14, color: c.greenText),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.showDivider,
    required this.onEdit,
    required this.onToggle,
  });

  final FoodItem item;
  final bool showDivider;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final meta = [
      item.defaultCalories == null
          ? 'No default calories'
          : '${fmtN(item.defaultCalories)} kcal',
      item.defaultUnit?.label ?? 'No unit',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 10, 13),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(top: BorderSide(color: c.inkA(.06)))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: item.name,
                    children: [
                      if (!item.active)
                        TextSpan(
                          text: '  Inactive',
                          style: sans(
                            11,
                            weight: FontWeight.w500,
                            color: c.inkA(.4),
                          ),
                        ),
                    ],
                  ),
                  style: sans(
                    15.5,
                    weight: FontWeight.w500,
                    color: item.active ? c.ink : c.inkA(.4),
                  ),
                ),
                const SizedBox(height: 1),
                Text(meta, style: sans(12.5, color: c.inkA(.45))),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Pill(
            label: 'Edit',
            onTap: onEdit,
            fontSize: 12.5,
            weight: FontWeight.w400,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
          const SizedBox(width: 4),
          Pill(
            label: item.active ? 'Deactivate' : 'Activate',
            onTap: onToggle,
            style: PillStyle.ghost,
            color: item.active ? c.deactivate : c.link,
            fontSize: 12.5,
            weight: FontWeight.w400,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          ),
        ],
      ),
    );
  }
}
