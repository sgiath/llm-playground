defmodule PlayWeb.GraphLive do
  use PlayWeb, :live_view

  alias Play.Graphs
  alias Play.Web.Live.Nodes
  alias Play.WorkflowExecutor

  require Logger

  @impl true
  def mount(%{"graph_id" => graph_id}, _session, socket) do
    profile = socket.assigns.current_scope.profile

    case Graphs.get_graph(profile, graph_id) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Graph not found")
          |> push_navigate(to: ~p"/graph")

        {:ok, socket}

      graph ->
        graph_data = if graph.data == %{}, do: nil, else: graph.data

        socket =
          socket
          |> assign(:graph, graph)
          |> assign(:graph_state, graph_data)
          |> assign(:selected_node, nil)
          |> assign(:node_count, length(graph_data["nodes"] || []))
          |> assign(:link_count, length(graph_data["links"] || []))
          |> assign(:node_types, Nodes.node_types())
          |> assign(:execution_status, :idle)
          |> assign(:editing_name, false)
          |> assign(:page_title, graph.name)

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-[calc(100vh-14rem)]">
        <%!-- Graph Canvas Area --%>
        <div class="flex-1 bg-base-300 relative" id="graph-container">
          <canvas
            id="graph-canvas"
            phx-hook="LitegraphHook"
            phx-update="ignore"
            class="w-full h-full block"
          >
          </canvas>
          <div class="absolute top-4 left-4 flex items-center gap-4">
            <.link navigate={~p"/graph"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>

            <div :if={!@editing_name} class="flex items-center gap-2">
              <h1 class="text-lg font-semibold">{@graph.name}</h1>
              <button phx-click="start_editing_name" class="btn btn-ghost btn-xs btn-square">
                <.icon name="hero-pencil" class="w-3 h-3" />
              </button>
            </div>

            <form :if={@editing_name} phx-submit="save_name" class="flex items-center gap-2">
              <input
                type="text"
                name="name"
                value={@graph.name}
                class="input input-sm input-bordered w-64"
                autofocus
                phx-keydown="cancel_editing_name"
                phx-key="escape"
              />
              <button type="submit" class="btn btn-primary btn-sm">Save</button>
              <button type="button" phx-click="cancel_editing_name" class="btn btn-ghost btn-sm">
                Cancel
              </button>
            </form>
          </div>

          <div class="absolute top-4 right-4 flex items-center gap-3">
            <div
              :if={@execution_status != :idle}
              class="flex items-center gap-2 bg-base-200/90 px-3 py-2 rounded-lg"
            >
              <span
                :if={@execution_status == :running}
                class="loading loading-spinner loading-sm text-primary"
              >
              </span>
              <span :if={@execution_status == :running} class="text-sm text-primary font-medium">
                Running...
              </span>
              <span :if={@execution_status == :complete} class="text-sm text-success font-medium">
                ✓ Complete
              </span>
            </div>
            <button
              phx-click="run_workflow"
              disabled={@execution_status == :running}
              class={[
                "btn btn-primary",
                @execution_status == :running && "btn-disabled"
              ]}
            >
              <.icon name="hero-play" class="w-5 h-5" /> Run Workflow
            </button>
          </div>

          <div class="absolute bottom-4 left-4 bg-base-200/90 p-3 rounded-lg text-sm">
            <p class="font-semibold mb-1">Graph Stats</p>
            <p>Nodes: {@node_count} | Links: {@link_count}</p>
          </div>
        </div>

        <%!-- Node Details Sidebar --%>
        <div
          id="node-sidebar"
          class={[
            "w-80 bg-base-200 border-l border-base-300 overflow-y-auto transition-all duration-200",
            !@selected_node && "w-0 opacity-0 overflow-hidden"
          ]}
        >
          <div :if={@selected_node} class="p-4">
            <%!-- Node Header --%>
            <div class="flex items-start justify-between mb-4">
              <div>
                <h2 class="text-lg font-bold text-base-content">
                  {@selected_node["title"]}
                </h2>
                <p class="text-sm text-base-content/60">
                  {@selected_node["type"]}
                </p>
              </div>
              <div
                class="w-4 h-4 rounded-full"
                style={"background-color: #{@selected_node["color"] || "#666"}"}
              >
              </div>
            </div>

            <%!-- Description --%>
            <p
              :if={@selected_node["description"] && @selected_node["description"] != ""}
              class="text-sm text-base-content/70 mb-4"
            >
              {@selected_node["description"]}
            </p>

            <%!-- Properties Section --%>
            <div
              :if={@selected_node["properties"] && map_size(@selected_node["properties"]) > 0}
              class="mb-4"
            >
              <div tabindex="0" class="collapse collapse-arrow bg-base-300 rounded-lg">
                <input type="checkbox" checked />
                <div class="collapse-title font-semibold text-sm">
                  Properties
                  <span class="badge badge-sm badge-neutral ml-2">
                    {map_size(@selected_node["properties"])}
                  </span>
                </div>
                <div class="collapse-content">
                  <div class="space-y-3">
                    <%= for {key, value} <- @selected_node["properties"] do %>
                      <div class="text-sm border-b border-base-content/10 last:border-0 pb-2">
                        <div class="flex items-center gap-2 mb-1">
                          <span class="font-mono text-base-content/70 font-semibold">{key}</span>
                          <span class="badge badge-xs badge-ghost">{get_type_label(value)}</span>
                        </div>
                        {render_property_value(assigns, key, value)}
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Inputs Section --%>
            <div :if={@selected_node["inputs"] && length(@selected_node["inputs"]) > 0} class="mb-4">
              <div tabindex="0" class="collapse collapse-arrow bg-base-300 rounded-lg">
                <input type="checkbox" checked />
                <div class="collapse-title font-semibold text-sm">
                  Inputs
                  <span class="badge badge-sm badge-neutral ml-2">
                    {length(@selected_node["inputs"])}
                  </span>
                </div>
                <div class="collapse-content">
                  <div class="space-y-2">
                    <%= for input <- @selected_node["inputs"] do %>
                      <div class="flex items-center gap-2 text-sm py-1">
                        <span class={[
                          "w-2 h-2 rounded-full",
                          input["connected"] && "bg-success",
                          !input["connected"] && "bg-base-content/30"
                        ]}>
                        </span>
                        <span class="font-mono">{input["name"]}</span>
                        <span
                          :if={input["type"]}
                          class="text-xs text-base-content/50 ml-auto"
                        >
                          {input["type"]}
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Outputs Section --%>
            <div :if={@selected_node["outputs"] && length(@selected_node["outputs"]) > 0} class="mb-4">
              <div tabindex="0" class="collapse collapse-arrow bg-base-300 rounded-lg">
                <input type="checkbox" checked />
                <div class="collapse-title font-semibold text-sm">
                  Outputs
                  <span class="badge badge-sm badge-neutral ml-2">
                    {length(@selected_node["outputs"])}
                  </span>
                </div>
                <div class="collapse-content">
                  <div class="space-y-2">
                    <%= for output <- @selected_node["outputs"] do %>
                      <div class="flex items-center gap-2 text-sm py-1">
                        <span class={[
                          "w-2 h-2 rounded-full",
                          output["connected"] && "bg-success",
                          !output["connected"] && "bg-base-content/30"
                        ]}>
                        </span>
                        <span class="font-mono">{output["name"]}</span>
                        <span
                          :if={output["connection_count"] && output["connection_count"] > 0}
                          class="badge badge-xs badge-success"
                        >
                          {output["connection_count"]}
                        </span>
                        <span
                          :if={output["type"]}
                          class="text-xs text-base-content/50 ml-auto"
                        >
                          {output["type"]}
                        </span>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            </div>

            <%!-- Node Info Section --%>
            <div class="text-xs text-base-content/50 space-y-1 mt-4 pt-4 border-t border-base-content/10">
              <p>ID: {@selected_node["node_id"]}</p>
              <p :if={@selected_node["pos"]}>
                Position: ({get_array_value(@selected_node["pos"], 0) |> round()}, {get_array_value(
                  @selected_node["pos"],
                  1
                )
                |> round()})
              </p>
              <p :if={@selected_node["size"]}>
                Size: {get_array_value(@selected_node["size"], 0)}×{get_array_value(
                  @selected_node["size"],
                  1
                )}
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Get type label for display
  defp get_type_label(value) when is_binary(value), do: "string"
  defp get_type_label(value) when is_list(value), do: "array[#{length(value)}]"
  defp get_type_label(value) when is_map(value), do: "object"
  defp get_type_label(value) when is_boolean(value), do: "boolean"
  defp get_type_label(value) when is_number(value), do: "number"
  defp get_type_label(nil), do: "null"
  defp get_type_label(_), do: "unknown"

  # Render property value based on type
  defp render_property_value(assigns, key, value) when is_list(value) and length(value) > 0 do
    assigns = assign(assigns, :items, value) |> assign(:key, key)

    ~H"""
    <div class="bg-base-100 rounded-lg p-2 max-h-48 overflow-y-auto">
      <%= for {item, idx} <- Enum.with_index(@items) do %>
        <div class="text-xs border-b border-base-content/5 last:border-0 py-1">
          <span class="text-base-content/40 mr-2">[{idx}]</span>
          <span class="font-mono">{format_list_item(item)}</span>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_property_value(assigns, _key, value) when is_list(value) do
    ~H"""
    <span class="font-mono text-xs text-base-content/50">[]</span>
    """
  end

  defp render_property_value(assigns, _key, value) when is_map(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <div class="bg-base-100 rounded-lg p-2 max-h-32 overflow-y-auto">
      <pre class="text-xs font-mono whitespace-pre-wrap break-all">{Jason.encode!(@value, pretty: true)}</pre>
    </div>
    """
  end

  defp render_property_value(assigns, _key, value) when is_binary(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <div class={[
      "font-mono text-xs bg-base-100 px-2 py-1 rounded",
      String.length(@value) > 100 && "max-h-24 overflow-y-auto"
    ]}>
      <span class="whitespace-pre-wrap break-all">{@value}</span>
    </div>
    """
  end

  defp render_property_value(assigns, _key, value) when is_boolean(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <span class={[
      "badge badge-sm",
      @value && "badge-success",
      !@value && "badge-neutral"
    ]}>
      {to_string(@value)}
    </span>
    """
  end

  defp render_property_value(assigns, _key, value) when is_number(value) do
    assigns = assign(assigns, :value, value)

    ~H"""
    <span class="font-mono text-xs bg-base-100 px-2 py-1 rounded">{@value}</span>
    """
  end

  defp render_property_value(assigns, _key, nil) do
    ~H"""
    <span class="font-mono text-xs text-base-content/40 italic">null</span>
    """
  end

  defp render_property_value(assigns, _key, value) do
    assigns = assign(assigns, :value, inspect(value, limit: 200))

    ~H"""
    <span class="font-mono text-xs bg-base-100 px-2 py-1 rounded">{@value}</span>
    """
  end

  # Format list items for display (especially for conversation history)
  defp format_list_item(item) when is_map(item) do
    cond do
      # Chat message format
      Map.has_key?(item, "role") and Map.has_key?(item, "content") ->
        role = item["role"]
        content = item["content"]

        truncated =
          if String.length(content || "") > 80,
            do: String.slice(content, 0, 77) <> "...",
            else: content

        "#{role}: #{truncated}"

      true ->
        Jason.encode!(item)
    end
  end

  defp format_list_item(item) when is_binary(item) do
    if String.length(item) > 100 do
      String.slice(item, 0, 97) <> "..."
    else
      item
    end
  end

  defp format_list_item(item), do: inspect(item, limit: 50)

  # Get value from array (handles both list and map with string keys from JS)
  defp get_array_value(data, index) when is_list(data), do: Enum.at(data, index, 0)
  defp get_array_value(data, index) when is_map(data), do: Map.get(data, to_string(index), 0)
  defp get_array_value(_, _), do: 0

  # ============================================================================
  # Event Handlers
  # ============================================================================

  # Hook is ready - register all node types and load saved graph or add sample nodes
  @impl true
  def handle_event("hook_ready", _params, socket) do
    Logger.info("Hook ready, registering #{length(socket.assigns.node_types)} node types")

    socket = push_event(socket, "register_node_types", %{types: socket.assigns.node_types})

    # If we have a saved graph, load it; otherwise create sample nodes
    socket =
      if socket.assigns.graph_state do
        node_count = length(socket.assigns.graph_state["nodes"] || [])
        Logger.info("Loading saved workflow with #{node_count} nodes")
        push_event(socket, "load_graph", %{graph_data: socket.assigns.graph_state})
      else
        Logger.info("No saved workflow found")
        socket
      end

    {:noreply, socket}
  end

  # Handle full graph state changes - save to database
  @impl true
  def handle_event("graph_state_changed", %{"trigger" => trigger, "graph" => graph_data}, socket) do
    Logger.debug("Graph state changed: #{trigger}")

    node_count = length(graph_data["nodes"] || [])
    link_count = length(graph_data["links"] || [])

    # Skip the initial empty graph state if we have a saved graph to load
    # This prevents the JS initialization from overwriting our saved state
    if trigger == "graph_initialized" and socket.assigns.graph_state != nil do
      Logger.debug("Skipping graph_initialized - will load saved graph")
      {:noreply, socket}
    else
      # Save the graph state to database
      graph = socket.assigns.graph

      socket =
        case Graphs.update_graph(graph, %{data: graph_data}) do
          {:ok, updated_graph} ->
            socket
            |> assign(:graph, updated_graph)
            |> assign(:graph_state, graph_data)
            |> assign(:node_count, node_count)
            |> assign(:link_count, link_count)

          {:error, _changeset} ->
            Logger.error("Failed to save graph to database")

            socket
            |> assign(:graph_state, graph_data)
            |> assign(:node_count, node_count)
            |> assign(:link_count, link_count)
        end

      {:noreply, socket}
    end
  end

  # Handle name editing
  @impl true
  def handle_event("start_editing_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  @impl true
  def handle_event("cancel_editing_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, false)}
  end

  @impl true
  def handle_event("save_name", %{"name" => name}, socket) do
    graph = socket.assigns.graph

    case Graphs.update_graph(graph, %{name: name}) do
      {:ok, updated_graph} ->
        socket =
          socket
          |> assign(:graph, updated_graph)
          |> assign(:editing_name, false)
          |> assign(:page_title, updated_graph.name)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update graph name")}
    end
  end

  # Handle node added
  @impl true
  def handle_event("node_added", params, socket) do
    Logger.info("Node added: #{params["type"]} (id: #{params["node_id"]})")
    {:noreply, socket}
  end

  # Handle node removed
  @impl true
  def handle_event("node_removed", params, socket) do
    Logger.info("Node removed: #{params["type"]} (id: #{params["node_id"]})")

    # Clear selection if the removed node was selected
    socket =
      if socket.assigns.selected_node &&
           socket.assigns.selected_node["node_id"] == params["node_id"] do
        assign(socket, :selected_node, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle connection changed
  @impl true
  def handle_event("connection_changed", params, socket) do
    Logger.info(
      "Connection changed: #{params["change_type"]} on node #{params["node_id"]} slot #{params["slot"]}"
    )

    {:noreply, socket}
  end

  # Handle node moved
  @impl true
  def handle_event("node_moved", params, socket) do
    Logger.debug("Node #{params["node_id"]} moved to #{inspect(params["pos"])}")
    {:noreply, socket}
  end

  # Handle node selected
  @impl true
  def handle_event("node_selected", %{"node_id" => nil}, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("node_selected", params, socket) do
    Logger.debug("Node selected: #{params["title"]} (id: #{params["node_id"]})")
    {:noreply, assign(socket, :selected_node, params)}
  end

  # Handle node deselected
  @impl true
  def handle_event("node_deselected", _params, socket) do
    {:noreply, assign(socket, :selected_node, nil)}
  end

  # Handle property changed
  @impl true
  def handle_event("property_changed", params, socket) do
    Logger.info(
      "Property changed on node #{params["node_id"]}: #{params["property"]} = #{inspect(params["value"])}"
    )

    {:noreply, socket}
  end

  # Handle graph loaded
  @impl true
  def handle_event("graph_loaded", params, socket) do
    Logger.info("Graph loaded with #{params["node_count"]} nodes")
    {:noreply, socket}
  end

  # Handle run workflow button click
  @impl true
  def handle_event("run_workflow", _params, socket) do
    if socket.assigns.execution_status == :running do
      {:noreply, socket}
    else
      # Request the current graph from JS for execution
      socket =
        socket
        |> assign(:execution_status, :running)
        |> push_event("request_execution", %{})

      {:noreply, socket}
    end
  end

  # Handle execution request with graph data from JS
  @impl true
  def handle_event("execute_workflow", %{"graph" => graph}, socket) do
    Logger.info("Starting workflow execution with #{length(graph["nodes"] || [])} nodes")

    # Start async execution
    WorkflowExecutor.execute_async(graph, self())

    {:noreply, socket}
  end

  # ============================================================================
  # Execution Progress Handlers (handle_info)
  # ============================================================================

  @impl true
  def handle_info({:node_executing, node_id}, socket) do
    Logger.debug("Node #{node_id} is executing")
    socket = push_event(socket, "node_executing", %{node_id: node_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:node_completed, node_id, result}, socket) do
    Logger.debug("Node #{node_id} completed with result: #{inspect(result, limit: 50)}")

    # Extract the primary output value (slot 0) for display nodes
    output_value =
      case result do
        %{0 => value} when is_binary(value) -> value
        %{0 => value} -> inspect(value, limit: 200)
        _ -> nil
      end

    socket = push_event(socket, "node_completed", %{node_id: node_id, output: output_value})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_delta, node_id, content}, socket) do
    # Push streaming content to JS for real-time display
    socket = push_event(socket, "stream_delta", %{node_id: node_id, content: content})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:node_error, node_id, reason}, socket) do
    Logger.error("Node #{node_id} error: #{reason}")

    socket =
      socket
      |> assign(:execution_status, :idle)
      |> push_event("node_error", %{node_id: node_id, reason: reason})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:update_node_properties, node_id, properties}, socket) do
    Logger.debug("Updating properties for node #{node_id}: #{inspect(properties, limit: 50)}")

    socket =
      push_event(socket, "update_node_properties", %{node_id: node_id, properties: properties})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:execution_complete, results}, socket) do
    Logger.info("Workflow execution complete with #{map_size(results)} node results")

    socket =
      socket
      |> assign(:execution_status, :complete)
      |> push_event("execution_complete", %{})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:execution_error, reason}, socket) do
    Logger.error("Workflow execution error: #{reason}")

    socket =
      socket
      |> assign(:execution_status, :idle)
      |> push_event("execution_error", %{reason: reason})

    {:noreply, socket}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Register a new node type dynamically.
  Call this from any event handler to add new node types at runtime.
  """
  def register_node_type(socket, node_def) do
    push_event(socket, "register_node_type", node_def)
  end

  @doc """
  Add a node to the graph.
  """
  def add_node(socket, type, opts \\ []) do
    push_event(socket, "add_node", %{
      type: type,
      pos: Keyword.get(opts, :pos),
      properties: Keyword.get(opts, :properties, %{})
    })
  end

  @doc """
  Connect two nodes.
  """
  def connect_nodes(socket, from_node_id, from_slot, to_node_id, to_slot) do
    push_event(socket, "connect_nodes", %{
      from_node_id: from_node_id,
      from_slot: from_slot,
      to_node_id: to_node_id,
      to_slot: to_slot
    })
  end

  @doc """
  Clear the entire graph.
  """
  def clear_graph(socket) do
    push_event(socket, "clear_graph", %{})
  end

  @doc """
  Load a graph from serialized data.
  """
  def load_graph(socket, graph_data) do
    push_event(socket, "load_graph", %{graph_data: graph_data})
  end
end
