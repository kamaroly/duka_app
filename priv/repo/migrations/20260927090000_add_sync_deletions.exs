defmodule DukaApp.Repo.Migrations.AddSyncDeletions do
  use Ecto.Migration

  def change do
    # Receipts deleted and requests withdrawn on the phone, until the next
    # sync tells the server (see DukaApp.Sync).
    create table(:sync_deletions) do
      add :profile_id, references(:profiles, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :client_id, :string, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:sync_deletions, [:profile_id, :kind, :client_id])

    # An attachment that came from the server: its id there, to download it.
    alter table(:request_attachments) do
      add :remote_id, :string
    end
  end
end
