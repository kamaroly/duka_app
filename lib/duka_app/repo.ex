defmodule DukaApp.Repo do
  use Ecto.Repo,
    otp_app: :duka_app,
    adapter: Ecto.Adapters.SQLite3

  @impl true
  def init(_type, config) do
    # MOB_DATA_DIR is set by mob_beam.c (Android) and mob_beam.m (iOS) to the
    # platform's appropriate persistent storage directory:
    #   Android — context.getFilesDir()  (app-private, survives updates)
    #   iOS     — NSDocumentDirectory    (app-private, iCloud-backed)
    #
    # Off device (mix test, mix ecto.migrate) the path from config wins, so the
    # test sandbox and local development never touch a phone's database.
    case System.get_env("MOB_DATA_DIR") do
      nil ->
        database = Keyword.fetch!(config, :database)
        File.mkdir_p!(Path.dirname(database))
        {:ok, config}

      data_dir ->
        File.mkdir_p!(data_dir)
        {:ok, Keyword.merge(config, database: Path.join(data_dir, "app.db"), pool_size: 1)}
    end
  end
end
