# Publishing Helpings on Google Play

Package: `in.mihirsolanki.helpings` · Account: personal (created after Nov 2023),
so a **closed test with ≥ 12 testers for 14 consecutive days** is required before
production.

## 0. One-time local setup (done)

| Item | Where |
|---|---|
| Upload keystore | `~/.android-keys/helpings-upload.jks` (alias `upload`) |
| Keystore password | `android/key.properties` (git-ignored) |
| Store listing text + images | `android/fastlane/metadata/android/en-US/` |
| Privacy policy page | `docs/privacy-policy.html` |

**Back up now:** copy `helpings-upload.jks` and the password from
`android/key.properties` into Bitwarden (or another safe place). If the upload key
is lost, Play can reset it, but it takes days and needs support.

## 1. Host the privacy policy

Upload `docs/privacy-policy.html` so it's reachable at
**https://mihirsolanki.in/helpings/privacy** (or any public URL on your domain).
Make sure `support@mihirsolanki.in` receives mail.

## 2. Create the app in Play Console

Play Console → **Create app**

- App name: `Helpings - Meal Tracker`
- Default language: English (United States) – en-US
- App or game: **App** · Free or paid: **Free**
- Accept the declarations.

## 3. Set up your app (Dashboard → "Set up your app")

| Section | Answer |
|---|---|
| Privacy policy | `https://mihirsolanki.in/helpings/privacy` |
| App access | All functionality is available without special access |
| Ads | **No**, my app does not contain ads |
| Content rating | Start questionnaire → email `support@mihirsolanki.in` → category **All Other App Types** → answer **No** to every question (no violence, sexuality, language, controlled substances, gambling, user interaction/sharing, location sharing, digital purchases). Result is typically *Everyone / PEGI 3*. |
| Target audience | **13–15, 16–17, 18 and over** (don't select under 13 — that triggers the Families policy). "Could unintentionally appeal to children?" → **No** |
| News app | No |
| Data safety | See below |
| Government app | No |
| Financial features | My app doesn't provide any financial features |
| Health apps | Select **Nutrition and weight management** (meal / calorie logging). Not a medical device. |
| App category | **Health & Fitness** · Tags: Nutrition, Diet, Calorie counter (pick what's offered) |
| Store contact | Email `support@mihirsolanki.in`; website `https://mihirsolanki.in` (optional) |

### Data safety answers

- Does your app collect or share any of the required user data types? → **No**
  (all data stays on device; the app has no internet permission. Data in the
  user's own Android backup is not considered collection by Google.)

Answering **No** skips the encryption and deletion-request questions; the
listing then shows "No data collected · No data shared".

## 4. Store listing (Grow → Store presence → Main store listing)

Copy from `android/fastlane/metadata/android/en-US/` (or run `fastlane listing`
once step 7 is done):

| Field | File |
|---|---|
| App name | `title.txt` |
| Short description | `short_description.txt` |
| Full description | `full_description.txt` |
| App icon (512×512) | `images/icon.png` |
| Feature graphic (1024×500) | `images/featureGraphic.png` |
| Phone screenshots (1080×1920) | `images/phoneScreenshots/1…5_*.png` |

## 5. First release → Closed testing (manual upload)

1. Build the bundle: `flutter build appbundle --release`
   → `build/app/outputs/bundle/release/app-release.aab`
2. Testing → **Closed testing** → create track (or use *Alpha*) → **Testers**:
   add an email list or Google Group with **at least 12** people. Copy the
   opt-in link and send it to them.
3. **Create release** → upload the `.aab`. When asked about **Play App Signing**,
   accept (Google manages the app signing key; your keystore is the *upload* key).
4. Release notes: copy `changelogs/1.txt`. Save → Review → **Start rollout**.
5. Select countries (e.g. India, or all).

Testers must **opt in via the link and stay opted in for 14 days**. Google also
looks for genuine usage, so ask them to actually use it and send feedback.

## 6. Apply for production

After 14 days with ≥ 12 opted-in testers: Dashboard → **Apply for production**.
Answer the questionnaire about the test (how testers were recruited, feedback
received, what you changed). Review usually takes a few days. Then:
`cd android && fastlane production` (or upload the AAB in Production manually).

## 7. fastlane for later uploads (service account)

The very first AAB must be uploaded in the Console (step 5). After that:

1. Google Cloud Console → create/select a project → **APIs & Services → Enable
   APIs** → enable **Google Play Android Developer API**.
2. **IAM & Admin → Service accounts → Create** (e.g. `play-publisher`). No roles
   needed. Open it → **Keys → Add key → JSON** → download.
3. Save it as `~/.android-keys/play-service-account.json` (`chmod 600`). Never commit it.
4. Play Console → **Users and permissions → Invite new users** → paste the
   service account email → App permissions: add Helpings → grant
   *Release apps to testing tracks*, *Release to production…*, *Manage store
   presence*. Invite.
5. Verify: `fastlane run validate_play_store_json_key json_key:~/.android-keys/play-service-account.json`

Then for each new version:

```sh
# 1. bump the build number in pubspec.yaml, e.g. version: 1.0.1+2
# 2. add android/fastlane/metadata/android/en-US/changelogs/2.txt
cd android
fastlane closed       # or: fastlane production
fastlane listing      # only when listing text/images change
```
