defmodule DukaApp.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "profile" do
    field(:email, :string)
    field(:phone, :string)
    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:email, :phone])
    |> validate_required([:email, :phone])
  end
end
