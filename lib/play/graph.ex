defmodule Play.Graph do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "graphs" do
    field :name, :string
    field :data, :map, default: %{}

    belongs_to :user_profile, Play.UserProfile

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new graph.
  """
  def create_changeset(graph, attrs) do
    graph
    |> cast(attrs, [:name, :data])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Changeset for updating a graph.
  """
  def update_changeset(graph, attrs) do
    graph
    |> cast(attrs, [:name, :data])
    |> validate_length(:name, min: 1, max: 255)
  end
end
