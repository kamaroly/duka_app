import Config
config :duka_app, DukaApp.Repo, timeout: 15_000, busy_timeout: 16_000

# Register the Repo so Mix tasks (mix ecto.create, mix ecto.migrate) can
# discover it. The actual database path is configured at runtime in
# DukaApp.Repo.init/2 via the MOB_DATA_DIR environment variable.
config :duka_app, ecto_repos: [DukaApp.Repo]

# Wire the Repo into Mob.ScreenState so screens using `vsn:` get automatic
# state persistence. Remove this line to disable screen state persistence.
config :mob, :repo, DukaApp.Repo

config :mob, :extra_tags, ~w(ReceiptItem ReceiptDetail SearchField Header Icon)
config :mob, :plugins, [:mob_camera, :mob_scanner, :mob_biometric, :mob_notify, :mob_ocr]

# mob_ocr and mob_google live in plugins/ and are not signed with the mob
# release key.
config :mob, :acknowledge_unsafe_plugins, [:mob_ocr, :mob_google]

# The Risiti server the app signs in to and syncs with (see DukaApp.Api).
# Users can change it in Settings. For a server on your laptop and a phone on
# USB: `adb reverse tcp:4000 tcp:4000`, and 127.0.0.1 reaches the laptop.
config :duka_app, :api_url, "https://expenses.zippiker.com"

# Push notifications from the server (see DukaApp.Push). Needs Firebase set
# up first: android/app/google-services.json, and the server's FCM key. Off
# until then, because registering without Firebase crashes on Android.
config :duka_app, :push, false

# Sign in with Google (see MobGoogle): the *Web* OAuth client id from the
# server's Google Cloud project — the same one in the server's
# GOOGLE_CLIENT_IDS. The app must also be registered there as an Android
# client (package com.example.duka_app and the signing key's SHA-1). Until
# it's set the phone screen doesn't offer Google.
config :duka_app, :google_client_id, nil

import_config "#{config_env()}.exs"
