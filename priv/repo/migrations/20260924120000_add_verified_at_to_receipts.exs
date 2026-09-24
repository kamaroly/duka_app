defmodule DukaApp.Repo.Migrations.AddVerifiedAtToReceipts do
  use Ecto.Migration

  def change do
    alter table(:receipts) do
      # When KRA's verification page last returned this receipt; nil until
      # it has been checked.
      add :verified_at, :utc_datetime
    end
  end
end
