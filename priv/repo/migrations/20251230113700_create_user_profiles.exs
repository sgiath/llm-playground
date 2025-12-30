defmodule Play.Repo.Migrations.CreateUserProfiles do
  use Ecto.Migration

  def change do
    create table(:user_profiles, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, :string, size: 32

      timestamps(type: :utc_datetime_usec)
    end

    # indexes
    create index(:user_profiles, [:user_id])
  end
end
