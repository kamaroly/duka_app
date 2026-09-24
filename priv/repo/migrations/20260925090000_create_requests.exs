defmodule DukaApp.Repo.Migrations.CreateRequests do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add :profile_id, references(:profiles, on_delete: :delete_all), null: false
      # "refund" (money back for a saved receipt) or "payment" (ask for a
      # payment to be made).
      add :kind, :string, null: false
      # pending -> approved | rejected -> paid. Decided by a manager once the
      # approval backend exists.
      add :status, :string, null: false, default: "pending"
      add :amount_cents, :integer, null: false
      add :purpose, :string
      # The receipt a refund is for.
      add :receipt_id, references(:receipts, on_delete: :nilify_all)

      # How to pay: "send_money" (to a phone), "till" (Buy Goods) or "paybill".
      add :method, :string, null: false
      add :phone, :string
      add :till_number, :string
      add :paybill_number, :string
      add :account_number, :string
      add :payee_name, :string

      # Filled in by the approval backend: when it received the request, and
      # the manager's decision.
      add :submitted_at, :utc_datetime
      add :decided_at, :utc_datetime
      add :decision_note, :string

      timestamps()
    end

    create index(:requests, [:profile_id, :inserted_at])
    create index(:requests, [:receipt_id])
  end
end
