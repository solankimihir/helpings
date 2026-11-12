import 'package:material_ui/material_ui.dart';

/// Design tokens from the Claude Design "Meal Tracker" mockup, plus a dark
/// counterpart. Read them anywhere with `context.c`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.primary,
    required this.primaryPressed,
    required this.onPrimary,
    required this.tabActive,
    required this.greenText,
    required this.link,
    required this.greenTint,
    required this.amberText,
    required this.amberStrong,
    required this.warnBg,
    required this.warnText,
    required this.danger,
    required this.errorBg,
    required this.errorText,
    required this.deactivate,
    required this.chipOnBg,
    required this.chipOnFg,
    required this.scrim,
    required this.shadow,
  });

  final Color bg; // #F7F5F0 page background
  final Color surface; // #fff cards
  final Color surfaceAlt; // #FAF9F6 hover / pressed rows
  final Color ink; // #17201C text
  final Color primary;
  final Color primaryPressed;
  final Color onPrimary;
  final Color tabActive;
  final Color greenText;
  final Color link;
  final Color greenTint;
  final Color amberText;
  final Color amberStrong;
  final Color warnBg;
  final Color warnText;
  final Color danger;
  final Color errorBg;
  final Color errorText;
  final Color deactivate;
  final Color chipOnBg;
  final Color chipOnFg;
  final Color scrim;
  final Color shadow;

  /// Ink at the given opacity — the design uses rgba(23,32,28,x) everywhere.
  Color inkA(double opacity) => ink.withValues(alpha: opacity);

  static const light = AppColors(
    bg: Color(0xFFF7F5F0),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFFAF9F6),
    ink: Color(0xFF17201C),
    primary: Color(0xFF2E854D),
    primaryPressed: Color(0xFF1A763F),
    onPrimary: Color(0xFFFFFFFF),
    tabActive: Color(0xFF1F6F3D),
    greenText: Color(0xFF1F6538),
    link: Color(0xFF267543),
    greenTint: Color(0xFFDEF6E3),
    amberText: Color(0xFF966626),
    amberStrong: Color(0xFF875814),
    warnBg: Color(0xFFFCEDCD),
    warnText: Color(0xFF694413),
    danger: Color(0xFFBD413F),
    errorBg: Color(0xFFFFDFDA),
    errorText: Color(0xFF972527),
    deactivate: Color(0xFFB34F2A),
    chipOnBg: Color(0xFF17201C),
    chipOnFg: Color(0xFFFFFFFF),
    scrim: Color(0x5217201C),
    shadow: Color(0xFF17201C),
  );

  static const dark = AppColors(
    bg: Color(0xFF111614),
    surface: Color(0xFF1B221F),
    surfaceAlt: Color(0xFF232B27),
    ink: Color(0xFFE9EDE9),
    primary: Color(0xFF3F945B),
    primaryPressed: Color(0xFF2E854D),
    onPrimary: Color(0xFFFFFFFF),
    tabActive: Color(0xFF72C78B),
    greenText: Color(0xFF7FCC94),
    link: Color(0xFF79C58E),
    greenTint: Color(0xFF203927),
    amberText: Color(0xFFE4B572),
    amberStrong: Color(0xFFEABB79),
    warnBg: Color(0xFF3C2E14),
    warnText: Color(0xFFF0CF98),
    danger: Color(0xFFEA6A64),
    errorBg: Color(0xFF4A2321),
    errorText: Color(0xFFFFC0BA),
    deactivate: Color(0xFFEE8F63),
    chipOnBg: Color(0xFFE9EDE9),
    chipOnFg: Color(0xFF111614),
    scrim: Color(0x99000000),
    shadow: Color(0xFF000000),
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      ink: l(ink, other.ink),
      primary: l(primary, other.primary),
      primaryPressed: l(primaryPressed, other.primaryPressed),
      onPrimary: l(onPrimary, other.onPrimary),
      tabActive: l(tabActive, other.tabActive),
      greenText: l(greenText, other.greenText),
      link: l(link, other.link),
      greenTint: l(greenTint, other.greenTint),
      amberText: l(amberText, other.amberText),
      amberStrong: l(amberStrong, other.amberStrong),
      warnBg: l(warnBg, other.warnBg),
      warnText: l(warnText, other.warnText),
      danger: l(danger, other.danger),
      errorBg: l(errorBg, other.errorBg),
      errorText: l(errorText, other.errorText),
      deactivate: l(deactivate, other.deactivate),
      chipOnBg: l(chipOnBg, other.chipOnBg),
      chipOnFg: l(chipOnFg, other.chipOnFg),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}

const kSans = 'DMSans';
const kSerif = 'InstrumentSerif';

/// DM Sans is a variable font; set the `wght` axis explicitly so every
/// weight renders correctly on both platforms.
TextStyle sans(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  return TextStyle(
    fontFamily: kSans,
    fontSize: size,
    fontWeight: weight,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}

TextStyle serif(double size, {Color? color, double? height}) {
  return TextStyle(
    fontFamily: kSerif,
    fontSize: size,
    color: color,
    height: height,
    letterSpacing: -0.01 * size,
  );
}

/// Small uppercase section label ("CALORIES", "ITEMS", "NOTES").
TextStyle overline(BuildContext context, {double spacing = 0.1}) => sans(
  11,
  weight: FontWeight.w500,
  color: context.c.inkA(.45),
  letterSpacing: spacing * 11,
);

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: c.primary,
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    surface: c.surface,
    onSurface: c.ink,
    error: c.danger,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: kSans,
    extensions: [c],
    splashFactory: InkSparkle.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.primary,
      selectionColor: c.primary.withValues(alpha: .25),
      selectionHandleColor: c.primary,
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: c.surface),
    timePickerTheme: TimePickerThemeData(backgroundColor: c.surface),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.chipOnBg,
      contentTextStyle: sans(14, color: c.chipOnFg),
    ),
  );
}
