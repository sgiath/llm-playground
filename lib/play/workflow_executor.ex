defmodule Play.WorkflowExecutor do
  @moduledoc """
  Executes workflows defined in the node graph using LangChain.

  Uses an event-driven execution model where nodes start executing as soon as
  their dependencies are satisfied, rather than waiting for all nodes at a
  level to complete. This allows maximum parallelism for independent branches.

  ## Execution Model

  1. Build dependency graphs (forward and reverse)
  2. Start all root nodes (nodes with no dependencies) immediately
  3. When a node completes, cache its output and check dependents
  4. Start any dependent whose dependencies are now all satisfied
  5. Complete when all nodes have executed

  ## Caching

  Uses a per-execution cache to prevent duplicate computations when nodes
  are dependencies of multiple branches.
  """

  require Logger

  alias Play.NodeExecutors

  # State for the execution coordinator
  defstruct [
    :node_map,
    :input_links,
    :dependents,
    :pending_deps,
    :outputs,
    :context,
    :caller_pid,
    :total_nodes,
    :completed_count,
    :running_tasks,
    :has_error
  ]

  @doc """
  Executes a workflow asynchronously, sending progress updates to the caller process.

  The caller will receive messages:
  - `{:node_executing, node_id}` - when a node starts executing
  - `{:node_completed, node_id, result}` - when a node finishes
  - `{:stream_delta, node_id, content}` - streaming content from Agent nodes
  - `{:execution_complete, results}` - when the entire workflow is done
  - `{:execution_error, reason}` - if an error occurs
  - `{:node_error, node_id, reason}` - if a specific node fails

  ## Options
  - `:message_inputs` - Map of node_id => message_text for Message Input nodes
  """
  def execute_async(graph, caller_pid, opts \\ [])
      when is_map(graph) and is_pid(caller_pid) do
    spawn(fn ->
      try do
        # Forward all options to execute
        results = execute(graph, caller_pid, opts)
        send(caller_pid, {:execution_complete, results})
      rescue
        e ->
          Logger.error(
            "Workflow execution error: #{inspect(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
          )

          send(caller_pid, {:execution_error, Exception.message(e)})
      end
    end)
  end

  @doc """
  Executes a workflow synchronously, returning the results.
  Sends progress updates to the caller_pid.

  Uses event-driven execution where nodes start as soon as their
  dependencies are satisfied, allowing maximum parallelism.

  ## Options
  - `:message_inputs` - Map of node_id => message_text for Message Input nodes
  """
  def execute(graph, caller_pid, opts \\ []) when is_map(graph) do
    nodes = graph["nodes"] || []
    links = graph["links"] || []
    message_inputs = Keyword.get(opts, :message_inputs, %{})
    user_profile = Keyword.get(opts, :user_profile)

    if Enum.empty?(nodes) do
      Logger.info("Empty workflow, nothing to execute")
      %{}
    else
      execute_workflow(nodes, links, caller_pid, message_inputs, user_profile)
    end
  end

  defp execute_workflow(nodes, links, caller_pid, message_inputs, user_profile) do
    # Build all required data structures
    node_map = Map.new(nodes, fn node -> {node["id"], node} end)
    input_links = build_input_links(links)
    {dependencies, dependents} = build_dependency_graphs(links)
    pending_deps = build_pending_deps(nodes, dependencies)

    # Find root nodes (no dependencies)
    root_nodes =
      nodes
      |> Enum.map(& &1["id"])
      |> Enum.filter(fn node_id -> Map.get(pending_deps, node_id, 0) == 0 end)

    total_nodes = length(nodes)

    Logger.info(
      "Executing workflow with #{total_nodes} nodes, #{length(root_nodes)} root nodes: #{inspect(root_nodes)}"
    )

    # Initialize execution state with message_inputs and user_profile in context
    state = %__MODULE__{
      node_map: node_map,
      input_links: input_links,
      dependents: dependents,
      pending_deps: pending_deps,
      outputs: %{},
      context: %{caller_pid: caller_pid, message_inputs: message_inputs, user_profile: user_profile},
      caller_pid: caller_pid,
      total_nodes: total_nodes,
      completed_count: 0,
      running_tasks: MapSet.new(),
      has_error: false
    }

    # Start all root nodes
    state = start_nodes(state, root_nodes)

    # Enter the event loop
    execute_loop(state)
  end

  # ============================================================================
  # Dependency Graph Building
  # ============================================================================

  @doc """
  Builds both forward (dependencies) and reverse (dependents) dependency graphs.

  Returns:
  - `dependencies`: Map of `node_id -> MapSet of node_ids it depends on`
  - `dependents`: Map of `node_id -> list of node_ids that depend on it`
  """
  def build_dependency_graphs(links) do
    Enum.reduce(links, {%{}, %{}}, fn link, {deps_acc, dependents_acc} ->
      [_link_id, from_node_id, _from_slot, to_node_id, _to_slot | _rest] = link

      # Forward: to_node depends on from_node
      deps_acc =
        Map.update(deps_acc, to_node_id, MapSet.new([from_node_id]), fn deps ->
          MapSet.put(deps, from_node_id)
        end)

      # Reverse: from_node has to_node as dependent
      dependents_acc =
        Map.update(dependents_acc, from_node_id, [to_node_id], fn list ->
          [to_node_id | list]
        end)

      {deps_acc, dependents_acc}
    end)
  end

  @doc """
  Builds the pending dependency count for each node.
  Returns a map of `node_id -> count of unfinished dependencies`.
  """
  def build_pending_deps(nodes, dependencies) do
    Map.new(nodes, fn node ->
      node_id = node["id"]
      deps = Map.get(dependencies, node_id, MapSet.new())
      {node_id, MapSet.size(deps)}
    end)
  end

  @doc """
  Builds a map of input connections: {to_node_id, to_slot} -> {from_node_id, from_slot}
  """
  def build_input_links(links) do
    Enum.reduce(links, %{}, fn link, acc ->
      [_link_id, from_node_id, from_slot, to_node_id, to_slot | _rest] = link
      Map.put(acc, {to_node_id, to_slot}, {from_node_id, from_slot})
    end)
  end

  # ============================================================================
  # Event-Driven Execution Loop
  # ============================================================================

  defp execute_loop(%{completed_count: completed, total_nodes: total} = state)
       when completed >= total do
    # All nodes completed
    Logger.info("Workflow execution complete: #{completed}/#{total} nodes")
    state.outputs
  end

  defp execute_loop(%{has_error: true} = state) do
    # Error occurred, return what we have
    Logger.warning("Workflow execution stopped due to error")
    state.outputs
  end

  defp execute_loop(%{running_tasks: running} = state) when map_size(running) == 0 do
    # No running tasks and not complete - should not happen normally
    Logger.warning(
      "No running tasks but execution not complete (#{state.completed_count}/#{state.total_nodes})"
    )

    state.outputs
  end

  defp execute_loop(state) do
    receive do
      {:task_completed, node_id, {:ok, node_outputs}} ->
        state
        |> handle_node_completed(node_id, node_outputs)
        |> execute_loop()

      {:task_completed, node_id, {:ok, node_outputs, property_updates}} ->
        # Handle stateful node with property updates
        send(state.caller_pid, {:update_node_properties, node_id, property_updates})

        state
        |> handle_node_completed(node_id, node_outputs)
        |> execute_loop()

      {:task_completed, node_id, {:error, reason}} ->
        Logger.error("Node #{node_id} failed: #{reason}")
        send(state.caller_pid, {:node_error, node_id, reason})

        state
        |> Map.put(:has_error, true)
        |> Map.update!(:running_tasks, &MapSet.delete(&1, node_id))
        |> execute_loop()

      {:task_crashed, node_id, reason} ->
        Logger.error("Node #{node_id} crashed: #{inspect(reason)}")
        send(state.caller_pid, {:node_error, node_id, "Task crashed: #{inspect(reason)}"})

        state
        |> Map.put(:has_error, true)
        |> Map.update!(:running_tasks, &MapSet.delete(&1, node_id))
        |> execute_loop()

      {:DOWN, _ref, :process, _pid, :normal} ->
        # Task completed normally, ignore
        execute_loop(state)

      {:DOWN, _ref, :process, _pid, reason} ->
        # Task crashed - we should have received a :task_crashed message
        Logger.warning("Received DOWN with reason: #{inspect(reason)}")
        execute_loop(state)

      other ->
        Logger.warning("Unexpected message in execute_loop: #{inspect(other)}")
        execute_loop(state)
    end
  end

  defp handle_node_completed(state, node_id, node_outputs) do
    # Cache the outputs
    new_outputs =
      Enum.reduce(node_outputs, state.outputs, fn {slot, value}, acc ->
        Map.put(acc, {node_id, slot}, value)
      end)

    # Send completion notification to caller
    send(state.caller_pid, {:node_completed, node_id, node_outputs})

    # Update state
    state = %{
      state
      | outputs: new_outputs,
        completed_count: state.completed_count + 1,
        running_tasks: MapSet.delete(state.running_tasks, node_id)
    }

    # Find and start any dependents that are now ready
    dependent_ids = Map.get(state.dependents, node_id, [])
    start_ready_dependents(state, dependent_ids)
  end

  defp start_ready_dependents(state, dependent_ids) do
    # Decrement pending deps for each dependent and collect ready ones
    {new_pending_deps, ready_nodes} =
      Enum.reduce(dependent_ids, {state.pending_deps, []}, fn dep_id, {pending, ready} ->
        current = Map.get(pending, dep_id, 0)
        new_count = max(0, current - 1)
        new_pending = Map.put(pending, dep_id, new_count)

        if new_count == 0 and current > 0 do
          {new_pending, [dep_id | ready]}
        else
          {new_pending, ready}
        end
      end)

    state = %{state | pending_deps: new_pending_deps}

    # Start all ready nodes
    if ready_nodes != [] do
      Logger.info("Starting newly ready nodes: #{inspect(ready_nodes)}")
      start_nodes(state, ready_nodes)
    else
      state
    end
  end

  # ============================================================================
  # Node Execution
  # ============================================================================

  defp start_nodes(state, node_ids) do
    coordinator_pid = self()

    Enum.reduce(node_ids, state, fn node_id, acc_state ->
      node = Map.get(acc_state.node_map, node_id)

      if node do
        # Spawn a task to execute the node
        Task.start(fn ->
          result =
            execute_single_node(
              node,
              acc_state.outputs,
              acc_state.input_links,
              acc_state.context,
              acc_state.caller_pid
            )

          send(coordinator_pid, {:task_completed, node_id, result})
        end)

        %{acc_state | running_tasks: MapSet.put(acc_state.running_tasks, node_id)}
      else
        Logger.warning("Node #{node_id} not found in node_map")
        acc_state
      end
    end)
  end

  defp execute_single_node(node, outputs, input_links, context, caller_pid) do
    node_id = node["id"]
    node_type = node["type"]
    properties = node["properties"] || %{}

    # Notify that we're starting execution
    send(caller_pid, {:node_executing, node_id})

    # Resolve inputs from connected nodes
    inputs = resolve_inputs(node, outputs, input_links)

    Logger.info("[Executing] Node ##{node_id} (#{node_type})")

    # Execute the node using NodeExecutors
    result = NodeExecutors.execute(node_type, node, inputs, properties, context)

    case result do
      {:ok, node_outputs} ->
        Logger.info("[Completed] Node ##{node_id} (#{node_type})")
        {:ok, node_outputs}

      {:ok, node_outputs, property_updates} ->
        Logger.info("[Completed] Node ##{node_id} (#{node_type}) (with property updates)")
        {:ok, node_outputs, property_updates}

      {:error, reason} ->
        Logger.error("[Failed] Node ##{node_id} (#{node_type}): #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Resolves input values for a node based on its connections.
  Returns a map of input_slot -> value.
  """
  def resolve_inputs(node, outputs, input_links) do
    node_id = node["id"]
    inputs = node["inputs"] || []

    Enum.reduce(Enum.with_index(inputs), %{}, fn {_input, slot}, acc ->
      case Map.get(input_links, {node_id, slot}) do
        nil ->
          # No connection to this input slot
          acc

        {from_node_id, from_slot} ->
          # Get the value from the connected node's output
          value = Map.get(outputs, {from_node_id, from_slot})
          Map.put(acc, slot, value)
      end
    end)
  end

  # ============================================================================
  # Legacy API (for compatibility)
  # ============================================================================

  @doc """
  Builds execution levels - groups of nodes that can run in parallel.
  Each level contains nodes whose dependencies are all in previous levels.

  Note: This is kept for compatibility but the new execution model doesn't use levels.
  """
  def build_execution_levels(nodes, links) do
    {dependencies, _dependents} = build_dependency_graphs(links)
    node_ids = MapSet.new(Enum.map(nodes, & &1["id"]))
    build_levels_recursive(node_ids, dependencies, [])
  end

  defp build_levels_recursive(remaining_nodes, dependencies, levels) do
    if MapSet.size(remaining_nodes) == 0 do
      Enum.reverse(levels)
    else
      ready_nodes =
        remaining_nodes
        |> Enum.filter(fn node_id ->
          deps = Map.get(dependencies, node_id, MapSet.new())
          MapSet.disjoint?(deps, remaining_nodes)
        end)
        |> MapSet.new()

      if MapSet.size(ready_nodes) == 0 and MapSet.size(remaining_nodes) > 0 do
        Logger.warning(
          "Potential cycle detected, adding remaining nodes: #{inspect(MapSet.to_list(remaining_nodes))}"
        )

        remaining_list = MapSet.to_list(remaining_nodes)
        Enum.reverse([remaining_list | levels])
      else
        ready_list = MapSet.to_list(ready_nodes)
        new_remaining = MapSet.difference(remaining_nodes, ready_nodes)
        build_levels_recursive(new_remaining, dependencies, [ready_list | levels])
      end
    end
  end

  @doc """
  Builds the execution order - flattened topological sort (for compatibility).
  """
  def build_execution_order(nodes, links) do
    nodes
    |> build_execution_levels(links)
    |> List.flatten()
  end

  @doc """
  Executes a single node with resolved inputs.
  This is the public API for external callers.
  """
  def execute_node(node, outputs, input_links, context, caller_pid) do
    result = execute_single_node(node, outputs, input_links, context, caller_pid)

    case result do
      {:ok, node_outputs} ->
        send(caller_pid, {:node_completed, node["id"], node_outputs})
        {:ok, node_outputs}

      {:ok, node_outputs, property_updates} ->
        send(caller_pid, {:node_completed, node["id"], node_outputs})
        send(caller_pid, {:update_node_properties, node["id"], property_updates})
        {:ok, node_outputs}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
