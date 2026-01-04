defmodule Play.Repo.Migrations.CreateGraphs do
  use Ecto.Migration

  def change do
    create table(:graphs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false
      add :data, :map, null: false, default: %{}

      add :user_profile_id, references(:user_profiles, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:graphs, [:user_profile_id])
  end
end
