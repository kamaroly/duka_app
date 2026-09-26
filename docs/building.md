# Building for testers

Testers install a sideloaded release APK.

## Version

Each tester release needs a higher `versionCode` than the last, or Android
won't install it over the old one. Both numbers are in
`android/app/build.gradle`:

```gradle
versionCode 3
versionName "1.2"
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

cd android && ./gradlew assembleRelease
# → android/app/build/outputs/apk/release/app-release.apk
```

The release is signed with `android/upload_jks.keystore`. Its SHA-1 must be
registered for Google sign-in (see [Signing in](sign-in.md)).

## Before handing it out

- Deploy the matching server release first (see
  [The server and sync](server-and-sync.md)).
- Install over the previous version, and check that existing transactions,
  photos and attachments are still there.
- Sign in, add an expense, and check it syncs (it shows as sent).
- If Google is set up, try "Continue with Google" on a real phone.
