defmodule Play.Conversation do
  @moduledoc """
  Schema for storing LLM conversation history.

  Messages are stored as a JSON array of serialized LangChain.Message structs.
  Use `Play.LangChain.MessageSerializer` for serialization/deserialization.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field :name, :string
    field :messages, {:array, :map}, default: []

    belongs_to :user_profile, Play.UserProfile

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for creating a new conversation.
  """
  def create_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name, :messages])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Changeset for updating a conversation.
  """
  def update_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:name, :messages])
    |> validate_length(:name, min: 1, max: 255)
  end
end
