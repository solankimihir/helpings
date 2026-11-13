# iOS home-screen widget (not built yet)

The Android widget shipped first. Read this before adding the iOS version.
The iOS version can't be built and signed until an **App Group** exists in
the Apple Developer account. iOS widgets run as a separate process, and the
App Group is the shared storage they read from.

## What Android does today (match it)

- **Shows:** "TODAY", the day's calories (with `+` when some items have no
  calories), the meal count, and a **+ Add meal** button.
- **Data:** written from Dart in `lib/data/home_widget_data.dart`, using the keys
  `date`, `calories`, `meals` and `incomplete`.
- **Updates:** `lib/ui/home_widget_sync.dart` publishes on app start, after every
  change that affects today, and when the app comes back to the foreground.
- **Midnight:** a stored `date` that isn't today shows as zero.
- **Links:** the widget body opens `helpings://today`. The button opens
  `helpings://add-meal`, which opens Add Meal.

## One-time setup in the Apple Developer account

1. **Identifiers → App Groups → +**: create `group.in.mihirsolanki.helpings`.
2. **Identifiers → `in.mihirsolanki.helpings`**: enable **App Groups** and tick
   that group.
3. **Register a second App ID** `in.mihirsolanki.helpings.TodayWidget`, also with
   the App Group enabled.

## Code changes when the App Group exists

1. **Add the target.** In Xcode, File → New → Target → **Widget Extension**
   named `TodayWidget`. Turn off Live Activity and Configuration Intent.
2. **Turn on the App Group.** Add the App Groups capability, with the same group,
   to both **Runner** and **TodayWidget**.
3. **Set the group in Dart.** In `NativeHomeWidgetBridge`:
   - Call `HomeWidget.setAppGroupId('group.in.mihirsolanki.helpings')` before
     the first save.
   - Pass `iOSName: 'TodayWidget'` to `updateWidget`.
   - Drop the Android-only guard.
4. **Build the widget view.** In `TodayWidget.swift`, read the four keys from
   `UserDefaults(suiteName: "group.in.mihirsolanki.helpings")`, apply the
   midnight rule, and lay it out like the Android widget. The button uses
   `Link(destination: URL(string: "helpings://add-meal")!)`.
5. **Handle the link.** Register the `helpings` URL scheme in
   `ios/Runner/Info.plist` (`CFBundleURLTypes`) so the links open the app.
   `home_widget` then delivers them to `HomeWidget.widgetClicked` /
   `initiallyLaunchedFromHomeWidget`, which the app already handles.
