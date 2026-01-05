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
    |> cast(sanitize_attrs(attrs), [:name, :data])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Changeset for updating an agent.
  """
  def update_changeset(agent, attrs) do
    agent
    |> cast(sanitize_attrs(attrs), [:name, :data])
    |> validate_length(:name, min: 1, max: 255)
  end

  # Sanitize attributes before casting to remove null bytes that PostgreSQL can't handle.
  # This is necessary because URL content may contain \u0000 characters.
  defp sanitize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn {k, v} -> {k, sanitize_value(v)} end)
  end

  defp sanitize_attrs(attrs), do: attrs

  defp sanitize_value(value) when is_binary(value) do
    String.replace(value, <<0>>, "")
  end

  defp sanitize_value(value) when is_map(value) do
    Map.new(value, fn {k, v} -> {sanitize_value(k), sanitize_value(v)} end)
  end

  defp sanitize_value(value) when is_list(value) do
    Enum.map(value, &sanitize_value/1)
  end

  defp sanitize_value(value), do: value
end
