defmodule Play.Graphs do
  @moduledoc """
  Context module for managing graphs.
  """

  import Ecto.Query

  alias Play.Graph
  alias Play.Repo
  alias Play.UserProfile

  @doc """
  Returns all graphs for the given user profile.
  """
  def list_graphs(%UserProfile{id: profile_id}) do
    Graph
    |> where(user_profile_id: ^profile_id)
    |> order_by(desc: :updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single graph by id, scoped to the given profile.

  Raises `Ecto.NoResultsError` if the Graph does not exist or does not belong to the profile.
  """
  def get_graph!(%UserProfile{id: profile_id}, graph_id) do
    Graph
    |> where(id: ^graph_id, user_profile_id: ^profile_id)
    |> Repo.one!()
  end

  @doc """
  Gets a single graph by id, scoped to the given profile.

  Returns `nil` if the Graph does not exist or does not belong to the profile.
  """
  def get_graph(%UserProfile{id: profile_id}, graph_id) do
    Graph
    |> where(id: ^graph_id, user_profile_id: ^profile_id)
    |> Repo.one()
  end

  @doc """
  Creates a new graph for the given profile.
  """
  def create_graph(%UserProfile{id: profile_id}, attrs \\ %{}) do
    %Graph{user_profile_id: profile_id}
    |> Graph.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates the given graph.
  """
  def update_graph(%Graph{} = graph, attrs) do
    graph
    |> Graph.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes the given graph.
  """
  def delete_graph(%Graph{} = graph) do
    Repo.delete(graph)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking graph changes.
  """
  def change_graph(%Graph{} = graph, attrs \\ %{}) do
    Graph.update_changeset(graph, attrs)
  end
end
