defmodule DukaApp.Repo.Migrations.AddApprovals do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # "staff" or "manager". A manager sees the Approvals area.
      add :role, :string, null: false, default: "staff"
    end

    alter table(:receipts) do
      # Every receipt is an expense a manager approves or rejects.
      add :approval_status, :string, null: false, default: "pending"
      add :approval_note, :string
      add :decided_at, :utc_datetime
    end

    create index(:receipts, [:approval_status])
  end
end
