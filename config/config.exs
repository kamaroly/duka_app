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
config :mob, :plugins, [:mob_camera, :mob_scanner, :mob_biometric, :mob_ocr]

# mob_ocr lives in plugins/ and is not signed with the mob release key.
config :mob, :acknowledge_unsafe_plugins, [:mob_ocr]
import_config "#{config_env()}.exs"
