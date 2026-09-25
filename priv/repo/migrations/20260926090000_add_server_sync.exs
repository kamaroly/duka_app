defmodule DukaApp.Repo.Migrations.AddServerSync do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # Set by SMS sign-in with the Risiti server; nil means this receipt book
      # isn't connected to a team yet.
      add :api_token, :text
      add :remote_user_id, :string
      add :team, :string
      # What the server says this person may do (see /api/me).
      add :can_approve_receipts, :boolean, null: false, default: false
      add :can_approve_requests, :boolean, null: false, default: false
      add :can_mark_paid, :boolean, null: false, default: false
    end

    alter table(:receipts) do
      # The phone's own id for the receipt: the server keys on it, so a resend
      # updates rather than copies.
      add :client_id, :string
      add :remote_id, :string
      # True when this copy has changes the server hasn't seen.
      add :needs_push, :boolean, null: false, default: true
      add :photo_pushed, :boolean, null: false, default: false
      add :synced_at, :utc_datetime
    end

    alter table(:requests) do
      add :client_id, :string
      add :remote_id, :string
      add :synced_at, :utc_datetime
    end

    # Existing rows get an id now; new ones get it when created.
    execute(
      "UPDATE receipts SET client_id = lower(hex(randomblob(16))) WHERE client_id IS NULL",
      ""
    )

    execute(
      "UPDATE requests SET client_id = lower(hex(randomblob(16))) WHERE client_id IS NULL",
      ""
    )

    create unique_index(:receipts, [:client_id])
    create unique_index(:requests, [:client_id])
  end
end
