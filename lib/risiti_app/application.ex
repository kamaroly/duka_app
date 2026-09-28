defmodule RisitiApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [RisitiApp.Repo]

    opts = [strategy: :one_for_one, name: RisitiApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
