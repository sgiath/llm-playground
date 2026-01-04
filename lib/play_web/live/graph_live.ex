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
        message_input_nodes = extract_message_input_nodes(graph_data)
        conversation_display_nodes = extract_conversation_display_nodes(graph_data)

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
          |> assign(:message_input_nodes, message_input_nodes)
          |> assign(:message_inputs, %{})
          |> assign(:conversation_display_nodes, conversation_display_nodes)
          |> assign(:conversation_data, %{})

        {:ok, socket}
    end
  end

  # Extracts message_input nodes from graph data for sidebar display
  defp extract_message_input_nodes(nil), do: []

  defp extract_message_input_nodes(graph_data) do
    (graph_data["nodes"] || [])
    |> Enum.filter(fn node -> node["type"] == "input/message_input" end)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        label: get_in(node, ["properties", "label"]) || "User Message"
      }
    end)
  end

  # Extracts conversation_display nodes from graph data for sidebar display
  defp extract_conversation_display_nodes(nil), do: []

  defp extract_conversation_display_nodes(graph_data) do
    (graph_data["nodes"] || [])
    |> Enum.filter(fn node -> node["type"] == "output/conversation_display" end)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        label: get_in(node, ["properties", "label"]) || "Conversation"
      }
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-[calc(100vh-14rem)]">
        <%!-- Message Input Sidebar (Left) --%>
        <div
          :if={@message_input_nodes != []}
          class="w-72 bg-base-200 border-r border-base-300 flex flex-col"
        >
          <div class="p-4 border-b border-base-300">
            <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
              Message Inputs
            </h2>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-4">
            <div :for={node <- @message_input_nodes} class="space-y-2">
              <label class="text-sm font-medium text-base-content" for={"message-input-#{node.id}"}>
                {node.label}
              </label>
              <textarea
                id={"message-input-#{node.id}"}
                name={"message_input[#{node.id}]"}
                phx-blur="message_input_changed"
                phx-keyup="message_input_changed"
                phx-value-node-id={node.id}
                phx-debounce="300"
                placeholder="Type your message..."
                value={Map.get(@message_inputs, node.id, "")}
                class="textarea textarea-bordered w-full h-24 text-sm resize-none"
              ></textarea>
            </div>
          </div>

          <div class="p-4 border-t border-base-300">
            <button
              phx-click="send_messages"
              disabled={@execution_status == :running}
              class={[
                "btn btn-primary w-full",
                @execution_status == :running && "btn-disabled"
              ]}
            >
              <.icon name="hero-paper-airplane" class="w-4 h-4" /> Send
            </button>
          </div>
        </div>

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

        <%!-- Conversation Display Sidebar --%>
        <div
          id="conversation-sidebar"
          class={[
            "w-96 bg-base-200 border-l border-base-300 flex flex-col transition-all duration-200",
            map_size(@conversation_data) == 0 && "w-0 opacity-0 overflow-hidden"
          ]}
        >
          <div :if={map_size(@conversation_data) > 0} class="flex flex-col h-full">
            <%!-- Header --%>
            <div class="p-4 border-b border-base-300 shrink-0">
              <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
                Conversations
              </h2>
            </div>

            <%!-- Conversation Panels --%>
            <div class="flex-1 overflow-y-auto">
              <%= for {{node_id, conv_data}, idx} <- Enum.with_index(@conversation_data) do %>
                <div class="collapse collapse-arrow bg-base-100 border-b border-base-300">
                  <input
                    type="radio"
                    name="conversation-accordion"
                    checked={idx == 0}
                  />
                  <div class="collapse-title font-medium text-sm">
                    {conv_data.label}
                    <span class="badge badge-sm badge-ghost ml-2">
                      {length(conv_data.messages)} messages
                    </span>
                  </div>
                  <div class="collapse-content p-0">
                    <div class="p-3 space-y-3 max-h-[60vh] overflow-y-auto">
                      {render_conversation_messages(assigns, conv_data.messages)}
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ============================================================================
  # Conversation Display Helpers
  # ============================================================================

  # Render all messages in a conversation
  defp render_conversation_messages(assigns, messages) when is_list(messages) do
    # Separate system message from the rest
    {system_messages, chat_messages} =
      Enum.split_with(messages, fn msg -> msg["role"] == "system" end)

    assigns =
      assigns
      |> assign(:system_messages, system_messages)
      |> assign(:chat_messages, chat_messages)

    ~H"""
    <%!-- System Message Banner --%>
    <div :if={@system_messages != []} class="mb-3">
      <div class="collapse collapse-arrow bg-base-200 rounded-lg">
        <input type="checkbox" />
        <div class="collapse-title text-xs font-medium text-base-content/70 py-2 min-h-0">
          <.icon name="hero-cog-6-tooth" class="w-3 h-3 mr-1" /> System Prompt
        </div>
        <div class="collapse-content">
          <p class="text-xs text-base-content/80 whitespace-pre-wrap">
            {Enum.map_join(@system_messages, "\n\n", & &1["content"])}
          </p>
        </div>
      </div>
    </div>

    <%!-- Chat Messages --%>
    <div class="space-y-2">
      <%= for message <- @chat_messages do %>
        {render_chat_message(assigns, message)}
      <% end %>
    </div>
    """
  end

  defp render_conversation_messages(assigns, _), do: ~H""

  # Render a single chat message
  defp render_chat_message(assigns, %{"role" => "user"} = message) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="chat chat-start">
      <div class="chat-header text-xs opacity-70 mb-1">
        User
      </div>
      <div class="chat-bubble chat-bubble-primary text-sm">
        {@message["content"]}
      </div>
    </div>
    """
  end

  defp render_chat_message(assigns, %{"role" => "assistant"} = message) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="chat chat-end">
      <div class="chat-header text-xs opacity-70 mb-1">
        Assistant
      </div>
      <div class="chat-bubble chat-bubble-neutral text-sm">
        <div class="whitespace-pre-wrap">{@message["content"]}</div>

        <%!-- Tool Calls --%>
        <div :if={@message["tool_calls"] && @message["tool_calls"] != []} class="mt-2">
          {render_tool_calls(assigns, @message["tool_calls"])}
        </div>

        <%!-- Token Usage --%>
        <div :if={@message["usage"]} class="mt-2 pt-2 border-t border-base-content/20">
          {render_token_usage(assigns, @message["usage"])}
        </div>
      </div>
    </div>
    """
  end

  defp render_chat_message(assigns, %{"role" => "tool"} = message) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="chat chat-end">
      <div class="chat-header text-xs opacity-70 mb-1">
        <.icon name="hero-wrench-screwdriver" class="w-3 h-3 mr-1" /> Tool Result
      </div>
      <div class="chat-bubble chat-bubble-accent text-xs font-mono">
        <div class="max-h-32 overflow-y-auto whitespace-pre-wrap">
          {truncate_content(@message["content"], 500)}
        </div>
      </div>
    </div>
    """
  end

  defp render_chat_message(assigns, message) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="chat chat-start">
      <div class="chat-header text-xs opacity-70 mb-1">
        {String.capitalize(@message["role"] || "unknown")}
      </div>
      <div class="chat-bubble text-sm">
        {@message["content"]}
      </div>
    </div>
    """
  end

  # Render tool calls
  defp render_tool_calls(assigns, tool_calls) when is_list(tool_calls) do
    assigns = assign(assigns, :tool_calls, tool_calls)

    ~H"""
    <div class="space-y-1">
      <%= for tc <- @tool_calls do %>
        <div class="collapse collapse-arrow bg-base-300/50 rounded">
          <input type="checkbox" />
          <div class="collapse-title text-xs py-1 min-h-0 font-mono">
            <.icon name="hero-wrench-screwdriver" class="w-3 h-3 mr-1" />
            {tc["name"]}
          </div>
          <div class="collapse-content">
            <pre class="text-xs overflow-x-auto whitespace-pre-wrap">{format_json(tc["arguments"])}</pre>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_tool_calls(assigns, _), do: ~H""

  # Render token usage stats
  defp render_token_usage(assigns, usage) when is_map(usage) do
    assigns = assign(assigns, :usage, usage)

    ~H"""
    <div class="flex flex-wrap gap-2 text-xs">
      <span class="badge badge-xs badge-ghost">
        <.icon name="hero-arrow-down-tray" class="w-2 h-2 mr-1" />
        {@usage["input"] || 0} in
      </span>
      <span class="badge badge-xs badge-ghost">
        <.icon name="hero-arrow-up-tray" class="w-2 h-2 mr-1" />
        {@usage["output"] || 0} out
      </span>
      <span class="badge badge-xs badge-info">
        Σ {@usage["total"] || 0}
      </span>
    </div>
    """
  end

  defp render_token_usage(assigns, _), do: ~H""

  # Format JSON for display
  defp format_json(data) when is_map(data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} -> json
      _ -> inspect(data)
    end
  end

  defp format_json(data) when is_binary(data), do: data
  defp format_json(data), do: inspect(data)

  # Truncate long content
  defp truncate_content(content, max_length) when is_binary(content) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "..."
    else
      content
    end
  end

  defp truncate_content(content, _), do: inspect(content)

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
    message_input_nodes = extract_message_input_nodes(graph_data)
    conversation_display_nodes = extract_conversation_display_nodes(graph_data)

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
            |> assign(:message_input_nodes, message_input_nodes)
            |> assign(:conversation_display_nodes, conversation_display_nodes)

          {:error, _changeset} ->
            Logger.error("Failed to save graph to database")

            socket
            |> assign(:graph_state, graph_data)
            |> assign(:node_count, node_count)
            |> assign(:link_count, link_count)
            |> assign(:message_input_nodes, message_input_nodes)
            |> assign(:conversation_display_nodes, conversation_display_nodes)
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
        |> assign(:conversation_data, %{})
        |> push_event("request_execution", %{})

      {:noreply, socket}
    end
  end

  # Handle message input text changes
  @impl true
  def handle_event(
        "message_input_changed",
        %{"value" => value, "node-id" => node_id_str},
        socket
      ) do
    node_id = String.to_integer(node_id_str)
    message_inputs = Map.put(socket.assigns.message_inputs, node_id, value)
    {:noreply, assign(socket, :message_inputs, message_inputs)}
  end

  def handle_event("message_input_changed", _params, socket) do
    # Fallback if node-id is missing
    {:noreply, socket}
  end

  # Handle send messages button click
  @impl true
  def handle_event("send_messages", _params, socket) do
    if socket.assigns.execution_status == :running do
      {:noreply, socket}
    else
      # Request the current graph from JS for execution with message inputs
      socket =
        socket
        |> assign(:execution_status, :running)
        |> assign(:conversation_data, %{})
        |> push_event("request_execution", %{})

      {:noreply, socket}
    end
  end

  # Handle execution request with graph data from JS
  @impl true
  def handle_event("execute_workflow", %{"graph" => graph}, socket) do
    Logger.info("Starting workflow execution with #{length(graph["nodes"] || [])} nodes")

    # Start async execution with message inputs
    message_inputs = socket.assigns.message_inputs
    WorkflowExecutor.execute_async(graph, self(), message_inputs: message_inputs)

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

    # Check if this is a conversation_display node with conversation messages
    socket =
      case Map.get(properties, "conversation_messages") do
        nil ->
          socket

        messages ->
          # Find the node's label from conversation_display_nodes
          label =
            Enum.find_value(socket.assigns.conversation_display_nodes, "Conversation", fn node ->
              if node.id == node_id, do: node.label
            end)

          conversation_data =
            Map.put(socket.assigns.conversation_data, node_id, %{
              label: label,
              messages: messages
            })

          assign(socket, :conversation_data, conversation_data)
      end

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
      |> assign(:message_inputs, %{})
      |> push_event("execution_complete", %{})
      |> push_event("clear_message_inputs", %{})

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
