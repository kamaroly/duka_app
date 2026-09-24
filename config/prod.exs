import Config

# On device DukaApp.Repo.init/2 replaces this with a file under MOB_DATA_DIR.
config :duka_app, DukaApp.Repo, database: Path.expand("../priv/repo/duka_app.db", __DIR__)
