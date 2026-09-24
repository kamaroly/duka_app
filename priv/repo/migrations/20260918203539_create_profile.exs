defmodule DukaApp.Repo.Migrations.CreateProfile do
  use Ecto.Migration

  def change do
    create table(:profile) do
      add :email, :string, null: false
      timestamps()
    end
  end
end
