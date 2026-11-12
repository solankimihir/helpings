# Helpings

A simple, exact meal tracker for Android and iOS, built with Flutter from the
"Meal Tracker" Claude Design. Calories are never estimated — totals only add up
what you enter and say so when a line has no value.

## Features

- **Home** — today's calories and meals, with a card per meal.
- **Add / Edit Meal** — meal type, date and time (native pickers), search your
  food list to add lines pre-filled with default quantity, unit and calories,
  or create a new food item inline. Optional notes.
- **Meal detail** — per-line calories, incomplete-total warning, edit, delete.
- **History** — meals grouped by day with day totals, type filters,
  swipe left to delete.
- **Meal Items** — your food list: search, create, edit defaults, deactivate
  (hides from meal search) or delete (logged meals keep the name).
- **Settings** — default unit, restore default food items, delete all meals.
- Light and dark mode (follows the system).

All data is stored on-device in SQLite (`helpings.db`).

## Project layout

```
lib/
  data/       models, SQLite schema + migrations, repository, seed, formatting
  state/      Riverpod providers (AppDataNotifier holds the in-memory snapshot)
  theme/      design tokens (light/dark), fonts, ThemeData
  ui/         shell (tabs), screens, sheets, shared widgets
test/         repository, formatting and widget tests (in-memory SQLite via FFI)
assets/fonts/ Lexend + DM Serif Display (SIL Open Font License)
```

## Requirements

- Flutter 3.50+ (Dart 3.14)
- Android: a JDK 17+ (Android Studio's bundled JBR works) and the Android SDK
- iOS: full Xcode plus CocoaPods

## Run

```sh
flutter pub get
flutter test            # unit + widget tests, no device needed
flutter run             # on a connected device / emulator / simulator
```

## Schema changes

Bump `AppDatabase.version` in `lib/data/database.dart` and add a new
`if (from < N)` step to `_migrate`. Never edit a step that has shipped.
