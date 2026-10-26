# Android release to Google Play (Omni HR)

How an Android build goes from this repo to Play **production**, and how to set up a second Mac
to do it. No secrets are in this file: keys and passwords are copied by hand, never committed.

## How it works

Nothing goes through the Play Console UI. fastlane's `upload_to_play_store` (supply) talks to the
**Google Play Developer API** with a **service account** that has release rights on the app
`com.omnisoft.omnihr`. The lanes are in `android/fastlane/Fastfile`; the key path and package name
are in `android/fastlane/Appfile`.

| Lane | What it does |
|---|---|
| `build_and_internal` | `flutter build appbundle --release`, then uploads the AAB to the **Internal testing** track with the release notes |
| `internal` | Uploads an AAB you already built to Internal testing (no build) |
| `promote_to_alpha` | Moves the current Internal build to **Closed testing (alpha)** |
| `promote_to_prod` | Moves the current alpha build to **Production** |

So production is always internal → alpha → production: the build that testers had is the exact
binary that ships. Listing text, images and screenshots stay managed in the Play Console; only the
"What's new" notes are uploaded from the repo.

After `promote_to_prod`, Google reviews the release (usually hours, sometimes a day or two). With
managed publishing off, it goes live by itself once approved; check Play Console → Publishing
overview.

## One-time setup on a new Mac

1. **Tools**
   - Flutter **≥ 3.44** (`app_links` 6.4.1 needs Dart ≥ 3.12). Check: `flutter --version`.
   - JDK 17, pinned for Flutter: `flutter config --jdk-dir <temurin-17 home>`
     (the Kotlin JVM-target fix in `android/gradle.properties` assumes it).
   - fastlane: `brew install fastlane`.
2. **Repo**: clone `omnisoft-hrms-mobile`, then `flutter pub get`.
3. **Play service account key** (JSON). `Appfile` reads it from
   `/Users/willytanuwiharja/Keys/play-publisher-omnihr.json`.
   - Copy the file from the first Mac's `~/Keys/` by hand (AirDrop / USB / password manager),
     into `~/Keys/` with `chmod 700 ~/Keys` and `chmod 600` on the file.
   - If the home folder differs on the new Mac, change the path in `Appfile` **locally only**
     (or use a symlink). Don't commit a machine-specific path.
   - Alternative: create a second key for the same service account in Google Cloud Console
     (IAM → Service accounts → Keys). Its Play permissions stay as they are.
4. **Upload signing key** (keystore `.jks`). Copy it by hand, outside the repo (e.g. `~/Keys/`).
   Then create `android/key.properties` (gitignored) with these four keys, values from your
   password manager:
   ```
   storeFile=<absolute path to the .jks>
   storePassword=<…>
   keyAlias=<…>
   keyPassword=<…>
   ```
   Without this file Gradle falls back to the debug keystore and Play rejects the upload
   ("signed with the wrong key").
5. **Check the key works** (read-only, uploads nothing):
   ```
   cd android && fastlane run validate_play_store_json_key json_key:"$HOME/Keys/play-publisher-omnihr.json"
   ```

## Each release

1. Bump `version:` in `pubspec.yaml` (`1.34.1+110` → `1.34.2+111`). The build number (after `+`)
   must be higher than any build Play has ever seen, on any track.
2. Write the notes in `android/fastlane/metadata/android/en-US/changelogs/default.txt`
   (≤ 500 characters).
3. From `android/`, always with a UTF-8 locale (fastlane crashes on Xcode/Gradle output without it):
   ```
   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane build_and_internal
   ```
4. Install from the Internal track on a test phone and check it.
5. When ready for the wider test group, then production:
   ```
   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane promote_to_alpha
   LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane promote_to_prod
   ```
6. Commit the version bump and the notes.

## Gotchas

- **Git worktree**: `android/key.properties` is gitignored, so a worktree has none. Copy it from the
  main checkout before building, or the AAB is debug-signed.
- **"Version code already used"**: bump the `+N` build number; Play never accepts a number twice.
- **`promote_to_prod` finds nothing**: the build must be on alpha first (`promote_to_alpha`).
- **403 / "caller does not have permission"**: the service account lost its access in Play Console
  → Users and permissions; it needs release rights for this app.
- **Production rollout is 100%** with these lanes. For a staged rollout add
  `rollout: "0.1"` to the `promote_to_prod` call (then raise it in the Play Console).

## Rules

- Never commit, paste in chat, or put in notes: the service-account JSON, the `.jks`,
  `key.properties` or its passwords.
- If the upload key is lost or leaked: Play Console → App integrity → request an upload key reset
  (Play App Signing keeps the real app-signing key, so users are not affected).
