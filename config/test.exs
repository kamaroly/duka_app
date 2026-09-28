import Config

config :logger, level: :warning

config :risiti_app, RisitiApp.Repo,
  database:
    Path.expand("../priv/repo/risiti_app_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :risiti_app, :native, false

# Receipt photos written by tests go to a throwaway directory.
config :risiti_app, :data_dir, Path.join(System.tmp_dir!(), "risiti_app_test_data")

# Server calls go to a scripted stand-in (see test/support/fake_server.ex).
config :risiti_app, :http, RisitiApp.FakeServer
config :risiti_app, :api_url, "http://risiti.test"

config :risiti_app, :push, true

# Sign in with Google is offered (the native call is faked, as above).
config :risiti_app, :google_client_id, "risiti-web.apps.googleusercontent.com"
