import Config

# On device RisitiApp.Repo.init/2 replaces this with a file under MOB_DATA_DIR.
config :risiti_app, RisitiApp.Repo, database: Path.expand("../priv/repo/risiti_app.db", __DIR__)
