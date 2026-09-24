defmodule DukaApp.Repo.Migrations.CreateRequestAttachments do
  use Ecto.Migration

  def change do
    create table(:request_attachments) do
      add :request_id, references(:requests, on_delete: :delete_all), null: false
      # Stored file name under the app's request_attachments/ directory.
      add :file_name, :string, null: false
      # What the user picked it as, for display.
      add :name, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps()
    end

    create index(:request_attachments, [:request_id])
  end
end
