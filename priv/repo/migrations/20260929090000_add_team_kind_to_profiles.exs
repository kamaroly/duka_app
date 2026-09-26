defmodule DukaApp.Repo.Migrations.AddTeamKindToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # From the server: "personal" (just this person: no approvals, no
      # refunds or payment requests) or "business".
      add :team_kind, :string
      add :team_name, :string
    end
  end
end
