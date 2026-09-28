import Config

config :risiti_app, RisitiApp.Repo,
  database: Path.expand("../priv/repo/risiti_app_dev.db", __DIR__),
  show_sensitive_data_on_connection_error: true,
  pool_size: 5
