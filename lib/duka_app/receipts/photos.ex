defmodule DukaApp.Receipts.Photos do
  @moduledoc """
  Where receipt photos live: `receipt_photos/` in the app's private data
  directory (next to the SQLite database), so they survive app updates and
  are removed with the app.

  The database stores only the file name; `path/1` turns it into a full path.
  The data directory is not the same on every install, so a stored absolute
  path could go stale.
  """

  @dir "receipt_photos"

  @doc "A fresh, unused path to save a new photo to."
  @spec new_path() :: String.t()
  def new_path do
    name = "receipt-#{System.os_time(:millisecond)}-#{:rand.uniform(1_000_000)}.jpg"
    Path.join(dir(), name)
  end

  @doc "Full path for a stored file name, or nil."
  @spec path(String.t() | nil) :: String.t() | nil
  def path(nil), do: nil
  def path(name), do: Path.join(dir(), Path.basename(name))

  @doc "The file name to store for a full path."
  @spec name(String.t()) :: String.t()
  def name(path), do: Path.basename(path)

  @spec exists?(String.t() | nil) :: boolean()
  def exists?(nil), do: false
  def exists?(name), do: File.regular?(path(name))

  @doc "Deletes a stored photo. Missing files are fine."
  @spec delete(String.t() | nil) :: :ok
  def delete(nil), do: :ok

  def delete(name) do
    _ = File.rm(path(name))
    :ok
  end

  @spec dir() :: String.t()
  def dir do
    base =
      Application.get_env(:duka_app, :photos_dir) ||
        case System.get_env("MOB_DATA_DIR") do
          nil -> DukaApp.Repo.config() |> Keyword.fetch!(:database) |> Path.dirname()
          data_dir -> data_dir
        end

    path = Path.join(base, @dir)
    File.mkdir_p!(path)
    path
  end
end
