defmodule Play.Agent do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Keep the database table name as "graphs" to avoid migration
  schema "graphs" do
    field :name, :string
    field :data, :map, default: %{}

    belongs_to :user_profile, Play.UserProfile

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new agent.
  """
  def create_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :data])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Changeset for updating an agent.
  """
  def update_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :data])
    |> validate_length(:name, min: 1, max: 255)
  end
end
