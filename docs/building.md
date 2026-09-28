# Building for testers

Testers install a sideloaded release APK.

## Version

Each tester release needs a higher `versionCode` than the last, or Android
won't install it over the old one. Both numbers are in
`android/app/build.gradle`:

```gradle
versionCode 5
versionName "1.4"
```

Add release notes for each version in `docs/releases/`.

## Plugins

The app uses two local plugins in `plugins/`: `mob_ocr` (reading receipt
photos) and `mob_google` (Sign in with Google). Enable them in `mob.exs`,
which is local and not in git:

```elixir
config :mob, :plugins, [..., :mob_google]
config :mob, :acknowledge_unsafe_plugins, [:mob_ocr, :mob_google]
```

`mix mob.release` does **not** regenerate the Android plugin wiring: the
bridge `.kt` files, the Gradle dependencies, `MobPluginBootstrap` and the
NIF table. A native debug build does. The current wiring is committed, so
you only need this after adding or changing a plugin:

```sh
# Builds everything, installs nothing (no such device)
mix mob.deploy --native --android --device not-a-real-device
```

## The APK

```sh
mix mob.release --android

# Mob's cached runtime ships a stale exqlite (black screen) and no inets
# (every server call fails with "Can't reach the server"): fix both in otp.zip.
zip -d android/app/src/release/assets/otp.zip 'lib/exqlite-0.36.0/*' 'lib/exqlite-0.36.0/' 'lib/._exqlite-0.36.0'
(cd ~/.mob/cache/otp-android-5c9c69fc && zip -qr "$OLDPWD/android/app/src/release/assets/otp.zip" lib/inets-9.7 \
  -x 'lib/inets-9.7/src/*' 'lib/inets-9.7/include/*' 'lib/inets-9.7/examples/*' '*/._*')

# Drop OTP apps the app never loads (about 4.5 MB) and macOS "._" files.
zip -dq android/app/src/release/assets/otp.zip 'lib/common_test-*' 'lib/ssh-*' \
  'lib/mnesia-*' 'lib/jinterface-*' 'lib/eldap-*' 'lib/odbc-*' '*/._*' '._*' \
  'erts-*/include/*' 'lib/erts-*/include/*'

cd android && ./gradlew assembleRelease
# → android/app/build/outputs/apk/release/app-arm64-v8a-release.apk   (~51 MB)
#   android/app/build/outputs/apk/release/app-armeabi-v7a-release.apk (~49 MB)
```

Hand out the **arm64-v8a** APK: almost every phone is 64-bit ARM. The
armeabi-v7a one is for old 32-bit phones (Android's settings → About phone
won't say; if the arm64 APK won't install, "App not installed", use it).

What keeps it small (it was 133 MB):

- **R8** (`minifyEnabled`, `shrinkResources`) removes unused code, most of
  it from Compose's icon set. `android/app/proguard-rules.pro` keeps what
  the BEAM calls through JNI (`com.example.risiti_app.**`, `io.mob.**`).
  If a release build crashes with `ClassNotFoundException` or
  `NoSuchMethodError`, add a `-keep` for that class there.
- **One APK per ABI** (`splits` in `app/build.gradle`), without x86_64,
  which only emulators use. Debug builds (`mix mob.deploy`) and the `.aab`
  still carry every ABI.
- **The trimmed `otp.zip`** above.

A stale `libduka_app.so` (from before the rename) in
`android/app/src/main/jniLibs/*/` doubles the native code; delete it if it's
there.

The release is signed with `android/upload_jks.keystore`. Its SHA-1 must be
registered for Google sign-in (see [Signing in](sign-in.md)).

## Before handing it out

- Deploy the matching server release first (see
  [The server and sync](server-and-sync.md)).
- Install over the previous version, and check that existing transactions,
  photos and attachments are still there. A phone with a debug build
  (`mix mob.deploy`) can't take the release APK: uninstall first.
- Open the camera, scan a receipt QR, and read a photo: those go through
  the plugins' bridges, the code R8 must keep.
- Sign in, add an expense, and check it syncs (it shows as sent).
- If Google is set up, try "Continue with Google" on a real phone.
