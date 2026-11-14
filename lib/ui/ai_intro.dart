import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/home_widget_data.dart';
import '../data/reminders.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ai_foods_screen.dart';
import 'widgets/common.dart';

/// Shows the "Ask an AI" walkthrough once per device: on a new install and,
/// for existing users, on the first launch after updating. Waits for a
/// normal launch: not one from the home-screen widget or a reminder, which
/// open a meal sheet of their own.
class AiIntroRunner extends ConsumerStatefulWidget {
  const AiIntroRunner({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AiIntroRunner> createState() => _AiIntroRunnerState();
}

class _AiIntroRunnerState extends ConsumerState<AiIntroRunner> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final AppData data;
    try {
      data = await ref.read(appDataProvider.future);
    } catch (_) {
      return; // The UI shows load errors.
    }
    if (data.aiIntroSeen) return;
    try {
      if (await ref.read(homeWidgetBridgeProvider).launchUri() != null) return;
      if (data.remindersOn &&
          await ref.read(reminderSchedulerProvider).launchTypeId() != null) {
        return;
      }
    } catch (e) {
      debugPrint('Checking how the app was opened failed: $e');
    }
    if (!mounted) return;
    // Marked first, so a crash or a killed app never shows it twice.
    await ref.read(appDataProvider.notifier).markAiIntroSeen();
    if (mounted) await showAiIntro(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> showAiIntro(BuildContext context) async {
  final open = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.c.bg,
    barrierColor: context.c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const AiIntroSheet(),
  );
  if (open == true && context.mounted) await openAiFoods(context);
}

class AiIntroSheet extends StatefulWidget {
  const AiIntroSheet({super.key});

  @override
  State<AiIntroSheet> createState() => _AiIntroSheetState();
}

class _AiIntroSheetState extends State<AiIntroSheet> {
  final _pages = PageController();
  int _page = 0;

  static const _content = [
    (
      Icons.restaurant_menu_rounded,
      'Build your food list with AI',
      'ChatGPT, Claude or Gemini can set up your food list for you. It asks '
          'where you live, which cuisines you eat, veg or non-veg, and how '
          'often you eat home-cooked food or eat out, then suggests the foods '
          'you’re likely to log, with calories.',
    ),
    (
      Icons.edit_note_rounded,
      'Fill in missing calories',
      'Already have foods without calories? Send your list to the chat. It '
          'asks how big your portions are and how the food is cooked, then '
          'fills in only the blanks.',
    ),
    (
      Icons.content_paste_rounded,
      'How it works',
      '1. Copy a prompt from Helpings.\n'
          '2. Paste it into ChatGPT, Claude or Gemini and answer its questions.\n'
          '3. Copy its reply and paste it back into Helpings.\n\n'
          'Your data is backed up first, and you review every change before '
          'it’s imported. Helpings itself stays offline.\n\n'
          'You’ll find this any time in Meal Items → Ask AI.',
    ),
  ];

  bool get _last => _page == _content.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 380,
              child: PageView(
                controller: _pages,
                onPageChanged: (p) => setState(() => _page = p),
                children: [
                  for (final (icon, title, body) in _content)
                    SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: c.greenTint,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: c.greenText, size: 26),
                          ),
                          const SizedBox(height: 18),
                          Text(title, style: serif(28, color: c.ink)),
                          const SizedBox(height: 10),
                          Text(
                            body,
                            style: sans(15, color: c.inkA(.65), height: 1.5),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _content.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page ? c.primary : c.inkA(.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Tap(
                  onTap: () => Navigator.pop(context, false),
                  radius: 10,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  child: Text(
                    _last ? 'Maybe later' : 'Skip',
                    style: sans(14.5, color: c.inkA(.55)),
                  ),
                ),
                const Spacer(),
                Pill(
                  label: _last ? 'Show me' : 'Next',
                  style: PillStyle.primary,
                  fontSize: 14.5,
                  weight: FontWeight.w700,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  onTap: _last
                      ? () => Navigator.pop(context, true)
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
