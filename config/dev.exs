import Config

config :duka_app, DukaApp.Repo,
  database: Path.expand("../priv/repo/duka_app_dev.db", __DIR__),
  show_sensitive_data_on_connection_error: true,
  pool_size: 5
