defmodule DukaApp.DataCase do
  @moduledoc """
  Test case for anything that touches the database. Each test runs in a
  sandboxed transaction that is rolled back afterwards.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias DukaApp.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import DukaApp.DataCase
    end
  end

  setup tags do
    DukaApp.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(DukaApp.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc "Changeset errors as `%{field: [message]}`, with values interpolated."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
