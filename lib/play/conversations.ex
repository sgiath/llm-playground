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

  @doc """
  Updates a specific message at the given index within a conversation.
  Returns {:ok, conversation} or {:error, changeset}.
  """
  def update_message(%Conversation{} = conversation, index, new_message) when is_integer(index) do
    messages = conversation.messages

    if index >= 0 and index < length(messages) do
      updated_messages = List.replace_at(messages, index, new_message)
      update_conversation(conversation, %{messages: updated_messages})
    else
      {:error, :invalid_index}
    end
  end

  @doc """
  Deletes a message at the given index within a conversation.
  Returns {:ok, conversation} or {:error, changeset}.
  """
  def delete_message(%Conversation{} = conversation, index) when is_integer(index) do
    messages = conversation.messages

    if index >= 0 and index < length(messages) do
      updated_messages = List.delete_at(messages, index)
      update_conversation(conversation, %{messages: updated_messages})
    else
      {:error, :invalid_index}
    end
  end

  @doc """
  Reorders messages according to the given list of indices.
  The new_order list contains the original indices in their new positions.
  Returns {:ok, conversation} or {:error, changeset}.
  """
  def reorder_messages(%Conversation{} = conversation, new_order) when is_list(new_order) do
    messages = conversation.messages

    if length(new_order) == length(messages) and
         Enum.all?(new_order, &(&1 >= 0 and &1 < length(messages))) do
      reordered_messages = Enum.map(new_order, fn idx -> Enum.at(messages, idx) end)
      update_conversation(conversation, %{messages: reordered_messages})
    else
      {:error, :invalid_order}
    end
  end
end
