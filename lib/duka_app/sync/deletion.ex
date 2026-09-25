defmodule DukaApp.Sync.Deletion do
  @moduledoc """
  A receipt deleted or a request withdrawn on the phone, waiting for the
  next sync to tell the server. Until then, the pull doesn't bring it back.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "sync_deletions" do
    field :kind, :string
    field :client_id, :string

    belongs_to :profile, DukaApp.Accounts.Profile

    timestamps(updated_at: false)
  end
end
