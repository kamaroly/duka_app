defmodule DukaApp.Repo.Migrations.CreateReceipts do
  use Ecto.Migration

  def change do
    create table(:receipts) do
      add :profile_id, references(:profiles, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :vendor, :string, null: false
      add :description, :string
      add :amount_cents, :integer, null: false
      add :category, :string, null: false
      # What the QR code carried — kept so the receipt can be re-verified on
      # KRA's portal later and so the same receipt is never saved twice.
      add :qr_content, :text
      add :source, :string, null: false, default: "manual"
      add :seller_pin, :string
      add :branch_id, :string
      add :invoice_number, :string
      add :verify_url, :text
      timestamps()
    end

    create index(:receipts, [:profile_id, :date])
    create unique_index(:receipts, [:profile_id, :qr_content])
  end
end
