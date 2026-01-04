defmodule Play.Conversations do
  @moduledoc """
  Context module for managing conversation history.
  """

  import Ecto.Query

  alias Play.Conversation
  alias Play.Repo
  alias Play.UserProfile

  @doc """
  Returns all conversations for the given user profile.
  """
  def list_conversations(%UserProfile{id: profile_id}) do
    Conversation
    |> where(user_profile_id: ^profile_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single conversation by id, scoped to the given profile.

  Raises `Ecto.NoResultsError` if the Conversation does not exist or does not belong to the profile.
  """
  def get_conversation!(%UserProfile{id: profile_id}, conversation_id) do
    Conversation
    |> where(id: ^conversation_id, user_profile_id: ^profile_id)
    |> Repo.one!()
  end

  @doc """
  Gets a single conversation by id, scoped to the given profile.

  Returns `nil` if the Conversation does not exist or does not belong to the profile.
  """
  def get_conversation(%UserProfile{id: profile_id}, conversation_id) do
    Conversation
    |> where(id: ^conversation_id, user_profile_id: ^profile_id)
    |> Repo.one()
  end

  @doc """
  Creates a new conversation for the given profile.
  """
  def create_conversation(%UserProfile{id: profile_id}, attrs \\ %{}) do
    %Conversation{user_profile_id: profile_id}
    |> Conversation.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the given conversation.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes the given conversation.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking conversation changes.
  """
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.update_changeset(conversation, attrs)
  end
end
