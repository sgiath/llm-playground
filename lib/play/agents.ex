defmodule Play.Agents do
  @moduledoc """
  Context module for managing agents.
  """

  import Ecto.Query

  alias Play.Agent
  alias Play.Repo
  alias Play.UserProfile

  @doc """
  Returns all agents for the given user profile.
  """
  def list_agents(%UserProfile{id: profile_id}) do
    Agent
    |> where(user_profile_id: ^profile_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single agent by id, scoped to the given profile.

  Raises `Ecto.NoResultsError` if the Agent does not exist or does not belong to the profile.
  """
  def get_agent!(%UserProfile{id: profile_id}, agent_id) do
    Agent
    |> where(id: ^agent_id, user_profile_id: ^profile_id)
    |> Repo.one!()
  end

  @doc """
  Gets a single agent by id, scoped to the given profile.

  Returns `nil` if the Agent does not exist or does not belong to the profile.
  """
  def get_agent(%UserProfile{id: profile_id}, agent_id) do
    Agent
    |> where(id: ^agent_id, user_profile_id: ^profile_id)
    |> Repo.one()
  end

  @doc """
  Creates a new agent for the given profile.
  """
  def create_agent(%UserProfile{id: profile_id}, attrs \\ %{}) do
    %Agent{user_profile_id: profile_id}
    |> Agent.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the given agent.
  """
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes the given agent.
  """
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking agent changes.
  """
  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.update_changeset(agent, attrs)
  end
end
