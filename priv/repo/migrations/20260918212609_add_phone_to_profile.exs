defmodule DukaApp.Repo.Migrations.AddPhoneToProfile do
  use Ecto.Migration

  def change do
    alter table(:profile) do
      add :phone, :string, nil: true
    end
  end
end
