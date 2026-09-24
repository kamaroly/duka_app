defmodule DukaApp.Repo.Migrations.CreateProfiles do
  use Ecto.Migration

  # The old single-row `profile` table (email required, phone optional) and the
  # dice game's `rounds` table belong to the starter app. A receipt book is keyed
  # by phone number instead, so both are replaced rather than altered — SQLite
  # cannot relax a NOT NULL column in place.
  def up do
    drop_if_exists table(:profile)
    drop_if_exists table(:rounds)

    create table(:profiles) do
      add :phone, :string, null: false
      add :name, :string
      add :email, :string
      add :kra_pin, :string
      add :app_lock, :boolean, null: false, default: false
      add :last_signed_in_at, :utc_datetime
      timestamps()
    end

    create unique_index(:profiles, [:phone])
  end

  def down do
    drop table(:profiles)

    create table(:profile) do
      add :email, :string, null: false
      add :phone, :string
      timestamps()
    end
  end
end
