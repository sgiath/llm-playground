defmodule Play.WorkflowStore do
  @moduledoc """
  Stores and loads workflow graph state to/from JSON files.

  In development, saves to priv/workflows/ in the project root.
  In production, saves to the application's priv directory.
  """

  @workflows_subdir "workflows"
  @current_file "current.json"

  @doc """
  Saves the workflow graph state to the current.json file.
  """
  def save(graph_state) when is_map(graph_state) do
    ensure_dir!()

    json = Jason.encode!(graph_state, pretty: true)
    File.write!(current_path(), json)

    :ok
  end

  @doc """
  Loads the workflow graph state from the current.json file.
  Returns {:ok, graph_state} or {:error, :not_found}.
  """
  def load do
    path = current_path()
    require Logger
    Logger.info("WorkflowStore loading from: #{path}")

    if File.exists?(path) do
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, graph_state} ->
              Logger.info("WorkflowStore loaded #{length(graph_state["nodes"] || [])} nodes")
              {:ok, graph_state}

            {:error, _} ->
              {:error, :invalid_json}
          end

        {:error, _} ->
          {:error, :read_error}
      end
    else
      Logger.warning("WorkflowStore file not found: #{path}")
      {:error, :not_found}
    end
  end

  @doc """
  Clears the current workflow by deleting the file.
  """
  def clear do
    path = current_path()

    if File.exists?(path) do
      File.rm!(path)
    end

    :ok
  end

  defp current_path do
    Path.join([workflows_dir(), @current_file])
  end

  defp workflows_dir do
    # In development/test, use the project's priv directory (persists across recompilations)
    # In production, use the compiled priv directory
    if Mix.env() in [:dev, :test] do
      Path.join([File.cwd!(), "priv", @workflows_subdir])
    else
      Path.join([:code.priv_dir(:play), @workflows_subdir])
    end
  end

  defp ensure_dir! do
    File.mkdir_p!(workflows_dir())
  end
end
