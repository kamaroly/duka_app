import Config

config :logger, level: :warning

config :duka_app, DukaApp.Repo,
  database:
    Path.expand("../priv/repo/duka_app_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :duka_app, :native, false

# Receipt photos written by tests go to a throwaway directory.
config :duka_app, :data_dir, Path.join(System.tmp_dir!(), "duka_app_test_data")

# Server calls go to a scripted stand-in (see test/support/fake_server.ex).
config :duka_app, :http, DukaApp.FakeServer
config :duka_app, :api_url, "http://risiti.test"
