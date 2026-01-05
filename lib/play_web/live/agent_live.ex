defmodule PlayWeb.AgentLive do
  use PlayWeb, :live_view

  alias Play.Agents
  alias Play.Web.Live.Nodes
  alias Play.WorkflowExecutor

  import PlayWeb.Helpers.Markdown, only: [render_markdown: 1]

  require Logger

  @impl true
  def mount(%{"agent_id" => agent_id}, _session, socket) do
    profile = socket.assigns.current_scope.profile

    case Agents.get_agent(profile, agent_id) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Agent not found")
          |> push_navigate(to: ~p"/agent")

        {:ok, socket}

      agent ->
        agent_data = if agent.data == %{}, do: nil, else: agent.data
        message_input_nodes = extract_message_input_nodes(agent_data)
        image_input_nodes = extract_image_input_nodes(agent_data)
        conversation_display_nodes = extract_conversation_display_nodes(agent_data)

        socket =
          socket
          |> assign(:agent, agent)
          |> assign(:agent_state, agent_data)
          |> assign(:selected_node, nil)
          |> assign(:node_count, length(agent_data["nodes"] || []))
          |> assign(:link_count, length(agent_data["links"] || []))
          |> assign(:node_types, Nodes.node_types())
          |> assign(:execution_status, :idle)
          |> assign(:is_preview_execution, false)
          |> assign(:editing_name, false)
          |> assign(:page_title, agent.name)
          |> assign(:message_input_nodes, message_input_nodes)
          |> assign(:message_inputs, %{})
          |> assign(:image_input_nodes, image_input_nodes)
          |> assign(:image_inputs, %{})
          |> assign(:conversation_display_nodes, conversation_display_nodes)
          |> assign(:conversation_data, %{})
          |> assign(:execution_outputs, %{})
          |> assign(:streaming_content, %{})
          |> assign(:preview_timer, nil)
          |> assign(:pending_upload_node_id, nil)
          |> allow_upload(:image,
            accept: ~w(.jpg .jpeg .png .webp .gif),
            max_entries: 10,
            max_file_size: 10_000_000,
            auto_upload: true,
            progress: &handle_image_progress/3
          )

        {:ok, socket}
    end
  end

  # Extracts message_input nodes from agent data for sidebar display
  defp extract_message_input_nodes(nil), do: []

  defp extract_message_input_nodes(agent_data) do
    (agent_data["nodes"] || [])
    |> Enum.filter(fn node -> node["type"] == "input/message_input" end)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        label: get_in(node, ["properties", "label"]) || "User Message"
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  # Extracts image_input nodes from agent data for sidebar display
  defp extract_image_input_nodes(nil), do: []

  defp extract_image_input_nodes(agent_data) do
    (agent_data["nodes"] || [])
    |> Enum.filter(fn node -> node["type"] == "input/image_input" end)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        label: get_in(node, ["properties", "label"]) || "Image"
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  # Extracts conversation_display nodes from agent data for sidebar display
  defp extract_conversation_display_nodes(nil), do: []

  defp extract_conversation_display_nodes(agent_data) do
    (agent_data["nodes"] || [])
    |> Enum.filter(fn node -> node["type"] == "output/conversation_display" end)
    |> Enum.map(fn node ->
      %{
        id: node["id"],
        label: get_in(node, ["properties", "label"]) || "Conversation"
      }
    end)
    |> Enum.sort_by(& &1.id)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex h-[calc(100vh-14rem)]">
        <%!-- Input Sidebar (Left) --%>
        <div
          :if={@message_input_nodes != [] || @image_input_nodes != []}
          class="w-72 bg-base-200 border-r border-base-300 flex flex-col"
        >
          <div class="p-4 border-b border-base-300">
            <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
              Inputs
            </h2>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-6">
            <%!-- Message Input Section --%>
            <div :if={@message_input_nodes != []} class="space-y-4">
              <div :for={node <- @message_input_nodes} class="space-y-2">
                <label
                  class="text-sm font-medium text-base-content"
                  for={"message-input-#{node.id}"}
                >
                  {node.label}
                </label>
                <textarea
                  id={"message-input-#{node.id}"}
                  name={"message_input[#{node.id}]"}
                  phx-keyup="message_input_changed"
                  phx-value-node-id={node.id}
                  placeholder="Type your message..."
                  class="textarea textarea-bordered w-full h-24 text-sm resize-none"
                >{Map.get(@message_inputs, node.id, "")}</textarea>
              </div>
            </div>

            <%!-- Image Input Section --%>
            <div :if={@image_input_nodes != []} class="space-y-4">
              <div :for={node <- @image_input_nodes} class="space-y-2">
                <label class="text-sm font-medium text-base-content">
                  {node.label}
                </label>

                <form
                  id={"image-upload-form-#{node.id}"}
                  phx-change="validate_image"
                  phx-submit="upload_image"
                  phx-value-node-id={node.id}
                >
                  <.live_file_input
                    upload={@uploads.image}
                    class="file-input file-input-bordered file-input-sm w-full"
                  />
                </form>

                <%!-- Show uploaded image preview --%>
                <div :if={Map.has_key?(@image_inputs, node.id)} class="mt-2">
                  <div class="relative inline-block">
                    <img
                      src={"data:#{@image_inputs[node.id].media_type};base64,#{@image_inputs[node.id].data}"}
                      class="max-w-full max-h-32 rounded-lg border border-base-300"
                      alt="Uploaded image"
                    />
                    <button
                      type="button"
                      phx-click="remove_image"
                      phx-value-node-id={node.id}
                      class="absolute -top-2 -right-2 btn btn-circle btn-xs btn-error"
                    >
                      <.icon name="hero-x-mark" class="w-3 h-3" />
                    </button>
                  </div>
                </div>

                <%!-- Show pending uploads --%>
                <div
                  :for={entry <- Enum.filter(@uploads.image.entries, &(&1.ref == "#{node.id}"))}
                  class="mt-2"
                >
                  <div class="flex items-center gap-2">
                    <progress
                      class="progress progress-primary w-full"
                      value={entry.progress}
                      max="100"
                    >
                    </progress>
                    <span class="text-xs">{entry.progress}%</span>
                  </div>
                </div>
              </div>
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
            <.link navigate={~p"/agent"} class="btn btn-ghost btn-sm">
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
            </.link>

            <div :if={!@editing_name} class="flex items-center gap-2">
              <h1 class="text-lg font-semibold">{@agent.name}</h1>
              <button phx-click="start_editing_name" class="btn btn-ghost btn-xs btn-square">
                <.icon name="hero-pencil" class="w-3 h-3" />
              </button>
            </div>

            <form :if={@editing_name} phx-submit="save_name" class="flex items-center gap-2">
              <input
                type="text"
                name="name"
                value={@agent.name}
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
              <.icon name="hero-play" class="w-5 h-5" /> Run Agent
            </button>
          </div>

          <div class="absolute bottom-4 left-4 bg-base-200/90 p-3 rounded-lg text-sm">
            <p class="font-semibold mb-1">Agent Stats</p>
            <p>Nodes: {@node_count} | Links: {@link_count}</p>
          </div>
        </div>

        <%!-- Conversation Display Sidebar --%>
        <div
          id="conversation-sidebar"
          class={[
            "w-96 bg-base-200 border-l border-base-300 flex flex-col transition-all duration-200",
            map_size(@conversation_data) == 0 && map_size(@streaming_content) == 0 &&
              "w-0 opacity-0 overflow-hidden"
          ]}
        >
          <div
            :if={map_size(@conversation_data) > 0 || map_size(@streaming_content) > 0}
            class="flex flex-col h-full"
          >
            <%!-- Header --%>
            <div class="p-4 border-b border-base-300 shrink-0">
              <h2 class="text-sm font-semibold text-base-content/70 uppercase tracking-wide">
                <%= if map_size(@conversation_data) == 1 do %>
                  <% [{_node_id, conv_data}] = Enum.to_list(@conversation_data) %>
                  {conv_data.label}
                <% else %>
                  Conversations
                <% end %>
              </h2>
            </div>

            <%!-- Conversation Panels --%>
            <%= if map_size(@conversation_data) == 1 do %>
              <%!-- Single conversation: full height, no accordion --%>
              <% [{_node_id, conv_data}] = Enum.to_list(@conversation_data) %>
              <div id="conversation-scroll" class="flex-1 overflow-y-auto p-3 space-y-3">
                {render_conversation_messages(assigns, conv_data.messages)}
                <%!-- Streaming Content at the bottom --%>
                <div :if={map_size(@streaming_content) > 0}>
                  {render_all_streaming_content(assigns)}
                </div>
              </div>
            <% else %>
              <%= if map_size(@conversation_data) == 0 do %>
                <%!-- No conversation data, just streaming --%>
                <div class="flex-1 overflow-y-auto p-3 space-y-3">
                  <div :if={map_size(@streaming_content) > 0}>
                    {render_all_streaming_content(assigns)}
                  </div>
                </div>
              <% else %>
                <%!-- Multiple conversations: use accordion --%>
                <div class="flex-1 overflow-y-auto">
                  <%= for {{_node_id, conv_data}, idx} <- Enum.with_index(@conversation_data) do %>
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
                  <%!-- Streaming Content at the bottom for multiple conversations --%>
                  <div :if={map_size(@streaming_content) > 0} class="p-3 border-t border-base-300">
                    {render_all_streaming_content(assigns)}
                  </div>
                </div>
              <% end %>
            <% end %>
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

    # Group tool calls with their responses
    grouped_messages = group_tool_messages(chat_messages)

    assigns =
      assigns
      |> assign(:system_messages, system_messages)
      |> assign(:grouped_messages, grouped_messages)

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
            {Enum.map_join(@system_messages, "\n\n", &extract_text_content(&1["content"]))}
          </p>
        </div>
      </div>
    </div>

    <%!-- Chat Messages (grouped) --%>
    <div class="space-y-2">
      <%= for item <- @grouped_messages do %>
        {render_grouped_message(assigns, item)}
      <% end %>
    </div>
    """
  end

  defp render_conversation_messages(assigns, _), do: ~H""

  # Render a grouped message item (message + any tool responses)
  defp render_grouped_message(assigns, %{message: message, tool_responses: tool_responses}) do
    assigns =
      assigns
      |> assign(:message, message)
      |> assign(:tool_responses, tool_responses)

    ~H"""
    {render_chat_message(assigns, @message, @tool_responses)}
    """
  end

  # Render all streaming content with loading indicators
  defp render_all_streaming_content(assigns) do
    streaming_entries =
      assigns.streaming_content
      |> Enum.filter(fn {_node_id, content} -> content != "" end)
      |> Enum.map(fn {node_id, content} ->
        %{node_id: node_id, content: content, rendered: render_markdown(content)}
      end)

    assigns = assign(assigns, :streaming_entries, streaming_entries)

    ~H"""
    <div class="space-y-2">
      <div :for={entry <- @streaming_entries} class="chat chat-end">
        <div class="chat-header text-xs opacity-70 mb-1">
          Assistant
        </div>
        <div class="chat-bubble chat-bubble-neutral text-sm chat-markdown">
          <div>{Phoenix.HTML.raw(entry.rendered)}</div>
          <span class="loading loading-dots loading-xs ml-1"></span>
        </div>
      </div>
    </div>
    """
  end

  # Render a single chat message (with tool responses for grouping)
  defp render_chat_message(assigns, %{"role" => "user"} = message, _tool_responses) do
    text_content = extract_text_content(message["content"])
    image_parts = extract_image_parts(message["content"])

    assigns =
      assigns
      |> assign(:message, message)
      |> assign(:text_content, text_content)
      |> assign(:image_parts, image_parts)

    ~H"""
    <div class="chat chat-start">
      <div class="chat-header text-xs opacity-70 mb-1">
        User
      </div>
      <div class="chat-bubble chat-bubble-primary text-sm">
        <%!-- Text content --%>
        <div :if={@text_content != ""}>{@text_content}</div>

        <%!-- Images --%>
        <div :if={@image_parts != []} class={[@text_content != "" && "mt-2", "flex flex-wrap gap-2"]}>
          <img
            :for={img <- @image_parts}
            :if={img.url}
            src={img.url}
            class="max-w-48 max-h-48 rounded-lg object-contain"
            alt="User uploaded image"
          />
        </div>
      </div>
    </div>
    """
  end

  defp render_chat_message(assigns, %{"role" => "assistant"} = message, tool_responses) do
    # Extract usage from metadata (where serializer stores it)
    usage = get_in(message, ["metadata", "usage"])
    content = extract_text_content(message["content"])
    rendered_content = render_markdown(content)

    assigns =
      assigns
      |> assign(:message, message)
      |> assign(:usage, usage)
      |> assign(:rendered_content, rendered_content)
      |> assign(:tool_responses, tool_responses)

    ~H"""
    <div class="chat chat-end">
      <div class="chat-header text-xs opacity-70 mb-1">
        Assistant
      </div>
      <div class="chat-bubble chat-bubble-neutral text-sm chat-markdown">
        <div :if={@rendered_content != ""}>{Phoenix.HTML.raw(@rendered_content)}</div>

        <%!-- Tool Calls with Grouped Responses --%>
        <div :if={has_tool_calls?(@message)} class="mt-2">
          {render_tool_calls_grouped(assigns, @message["tool_calls"], @tool_responses)}
        </div>

        <%!-- Token Usage --%>
        <div :if={@usage} class="mt-2 pt-2 border-t border-base-content/20">
          {render_token_usage(assigns, @usage)}
        </div>
      </div>
    </div>
    """
  end

  defp render_chat_message(assigns, %{"role" => "tool"} = _message, _tool_responses) do
    # Tool messages are now grouped with assistant messages, so we render nothing here
    # This case shouldn't be reached when using grouped messages, but kept as fallback
    ~H""
  end

  defp render_chat_message(assigns, message, _tool_responses) do
    assigns = assign(assigns, :message, message)

    ~H"""
    <div class="chat chat-start">
      <div class="chat-header text-xs opacity-70 mb-1">
        {String.capitalize(@message["role"] || "unknown")}
      </div>
      <div class="chat-bubble text-sm">
        {extract_text_content(@message["content"])}
      </div>
    </div>
    """
  end

  # Render tool calls grouped with their responses (matching conversation detail page style)
  defp render_tool_calls_grouped(assigns, tool_calls, tool_responses)
       when is_list(tool_calls) do
    assigns =
      assigns
      |> assign(:tool_calls, tool_calls)
      |> assign(:tool_responses, tool_responses)

    ~H"""
    <div class="space-y-3">
      <div
        :for={tool_call <- @tool_calls}
        class="rounded-lg overflow-hidden border border-base-300"
      >
        <%!-- Tool name header --%>
        <div class="bg-base-300 px-3 py-2 flex items-center gap-2">
          <.icon name="hero-wrench-screwdriver" class="w-4 h-4 text-warning" />
          <span class="font-mono font-semibold text-sm">{tool_call["name"]}</span>
        </div>

        <%!-- Params and Response sections --%>
        <div class="divide-y divide-base-300">
          <%!-- Params section --%>
          <div class="p-3 text-sm">
            <div class="flex items-center gap-2 mb-2 text-base-content/60">
              <.icon name="hero-arrow-right-circle" class="w-4 h-4" />
              <span class="text-xs font-medium uppercase tracking-wide">
                Params
              </span>
            </div>
            <div class="bg-base-300/50 rounded p-2">
              <.json_tree content={tool_args_to_json(tool_call["arguments"])} />
            </div>
          </div>

          <%!-- Response section (if available) --%>
          <%= if response = find_tool_response(@tool_responses, tool_call) do %>
            <div class="p-3 text-sm">
              <div class="flex items-center gap-2 mb-2 text-base-content/60">
                <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
                <span class="text-xs font-medium uppercase tracking-wide">
                  Response
                </span>
              </div>
              <div class="bg-base-300/50 rounded p-2">
                <.json_tree content={extract_tool_response_content(response)} />
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp render_tool_calls_grouped(assigns, _, _), do: ~H""

  # Extract content from a tool response message
  defp extract_tool_response_content(%{"content" => content}) when is_binary(content), do: content

  defp extract_tool_response_content(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{"content" => c} when is_binary(c) -> c
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end

  defp extract_tool_response_content(_), do: ""

  # Render token usage stats
  defp render_token_usage(assigns, usage) when is_map(usage) do
    input_tokens = usage["input"] || 0
    output_tokens = usage["output"] || 0
    total_tokens = input_tokens + output_tokens

    assigns =
      assigns
      |> assign(:input_tokens, input_tokens)
      |> assign(:output_tokens, output_tokens)
      |> assign(:total_tokens, total_tokens)

    ~H"""
    <div class="flex flex-wrap gap-2 text-xs">
      <span class="badge badge-xs badge-ghost">
        <.icon name="hero-arrow-down-tray" class="w-2 h-2 mr-1" />
        {@input_tokens} in
      </span>
      <span class="badge badge-xs badge-ghost">
        <.icon name="hero-arrow-up-tray" class="w-2 h-2 mr-1" />
        {@output_tokens} out
      </span>
      <span class="badge badge-xs badge-info">
        Σ {@total_tokens}
      </span>
    </div>
    """
  end

  defp render_token_usage(assigns, _), do: ~H""

  # ============================================================================
  # JSON Tree Component
  # ============================================================================

  # JSON tree component for displaying structured data
  attr :content, :string, required: true

  defp json_tree(assigns) do
    parsed = try_parse_json(assigns.content)
    assigns = assign(assigns, :parsed, parsed)

    ~H"""
    <%= case @parsed do %>
      <% {:ok, data} when is_map(data) or is_list(data) -> %>
        <div class="font-mono text-xs">
          <.json_node value={data} root={true} />
        </div>
      <% _ -> %>
        <div class="prose prose-sm max-w-none">
          <p class="whitespace-pre-wrap text-sm">{@content}</p>
        </div>
    <% end %>
    """
  end

  attr :value, :any, required: true
  attr :key, :string, default: nil
  attr :root, :boolean, default: false

  defp json_node(%{value: value} = assigns) when is_map(value) do
    entries = Map.to_list(value)
    assigns = assign(assigns, :entries, entries)
    assigns = assign(assigns, :brace_open, "{")
    assigns = assign(assigns, :brace_close, "}")

    ~H"""
    <details class={["ml-2", @root && "-ml-0"]} open={@root}>
      <summary class="cursor-pointer hover:bg-base-200 rounded px-1 -ml-1 select-none">
        <span :if={@key} class="text-info">{@key}:</span>
        <span class="text-base-content/50">{@brace_open}...{@brace_close}</span>
        <span class="text-base-content/40 text-xs ml-1">({map_size(@value)} keys)</span>
      </summary>
      <div class="border-l border-base-300 pl-2 ml-1">
        <div :for={{k, v} <- @entries}>
          <.json_node key={to_string(k)} value={v} />
        </div>
      </div>
    </details>
    """
  end

  defp json_node(%{value: value} = assigns) when is_list(value) do
    items = Enum.with_index(value)
    assigns = assign(assigns, :items, items)
    assigns = assign(assigns, :bracket_open, "[")
    assigns = assign(assigns, :bracket_close, "]")

    ~H"""
    <details class={["ml-2", @root && "-ml-0"]} open={@root}>
      <summary class="cursor-pointer hover:bg-base-200 rounded px-1 -ml-1 select-none">
        <span :if={@key} class="text-info">{@key}:</span>
        <span class="text-base-content/50">{@bracket_open}...{@bracket_close}</span>
        <span class="text-base-content/40 text-xs ml-1">({length(@value)} items)</span>
      </summary>
      <div class="border-l border-base-300 pl-2 ml-1">
        <div :for={{item, idx} <- @items}>
          <.json_node key={to_string(idx)} value={item} />
        </div>
      </div>
    </details>
    """
  end

  defp json_node(%{value: value} = assigns) when is_binary(value) do
    ~H"""
    <div class="ml-2 py-0.5">
      <span :if={@key} class="text-info">{@key}: </span>
      <span class="text-success">"{@value}"</span>
    </div>
    """
  end

  defp json_node(%{value: value} = assigns) when is_number(value) do
    ~H"""
    <div class="ml-2 py-0.5">
      <span :if={@key} class="text-info">{@key}: </span>
      <span class="text-warning">{@value}</span>
    </div>
    """
  end

  defp json_node(%{value: value} = assigns) when is_boolean(value) do
    ~H"""
    <div class="ml-2 py-0.5">
      <span :if={@key} class="text-info">{@key}: </span>
      <span class="text-accent">{to_string(@value)}</span>
    </div>
    """
  end

  defp json_node(%{value: nil} = assigns) do
    ~H"""
    <div class="ml-2 py-0.5">
      <span :if={@key} class="text-info">{@key}: </span>
      <span class="text-base-content/50 italic">null</span>
    </div>
    """
  end

  defp json_node(assigns) do
    ~H"""
    <div class="ml-2 py-0.5">
      <span :if={@key} class="text-info">{@key}: </span>
      <span class="text-base-content">{inspect(@value)}</span>
    </div>
    """
  end

  defp try_parse_json(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> :error
    end
  end

  defp try_parse_json(_), do: :error

  # Convert tool arguments to JSON string for json_tree component
  defp tool_args_to_json(nil), do: "{}"
  defp tool_args_to_json(args) when is_binary(args), do: args
  defp tool_args_to_json(args) when is_map(args), do: Jason.encode!(args)
  defp tool_args_to_json(args), do: inspect(args)

  # ============================================================================
  # Tool Message Grouping
  # ============================================================================

  # Check if a message has tool calls (works with serialized format - string keys)
  defp has_tool_calls?(%{"tool_calls" => tool_calls})
       when is_list(tool_calls) and tool_calls != [],
       do: true

  defp has_tool_calls?(_), do: false

  # Group assistant messages with tool_calls together with following tool response messages
  # Works with serialized message format (string keys)
  defp group_tool_messages(messages) when is_list(messages) do
    messages
    |> Enum.with_index()
    |> Enum.reduce({[], nil}, fn {msg, idx}, {acc, pending_group} ->
      cond do
        # Assistant message with tool calls - start a new group
        has_tool_calls?(msg) ->
          # Flush any existing pending group first
          acc = if pending_group, do: acc ++ [pending_group], else: acc
          {acc, %{message: msg, index: idx, tool_responses: []}}

        # Tool response message - add to pending group if exists
        msg["role"] == "tool" and pending_group != nil ->
          updated_group = %{
            pending_group
            | tool_responses: pending_group.tool_responses ++ [{msg, idx}]
          }

          {acc, updated_group}

        # Regular message - flush pending group and add this message
        true ->
          acc = if pending_group, do: acc ++ [pending_group], else: acc
          {acc ++ [%{message: msg, index: idx, tool_responses: []}], nil}
      end
    end)
    |> then(fn {acc, pending_group} ->
      # Flush any remaining pending group
      if pending_group, do: acc ++ [pending_group], else: acc
    end)
  end

  defp group_tool_messages(_), do: []

  # Find the tool response that matches a tool call by call_id or name
  # Works with serialized format (string keys)
  defp find_tool_response(tool_responses, tool_call) do
    Enum.find_value(tool_responses, fn {response_msg, _idx} ->
      # Check if this tool response matches the tool call
      tool_call_id = tool_call["call_id"] || tool_call["id"]
      tool_name = tool_call["name"]

      response_call_id = response_msg["tool_call_id"]
      response_name = response_msg["name"]

      if (tool_call_id && response_call_id == tool_call_id) ||
           (tool_name && response_name == tool_name) do
        response_msg
      else
        # Fallback: if there's only one tool response and one tool call, match them
        if length(tool_responses) == 1 do
          response_msg
        end
      end
    end)
  end

  # Extract text content from serialized message content
  # Content can be a string, a list of ContentPart maps, or nil
  defp extract_text_content(nil), do: ""
  defp extract_text_content(content) when is_binary(content), do: content

  defp extract_text_content(content) when is_list(content) do
    content
    |> Enum.filter(fn
      %{"type" => "text"} -> true
      _ -> false
    end)
    |> Enum.map(fn part -> part["content"] || "" end)
    |> Enum.join("\n\n")
  end

  defp extract_text_content(content), do: inspect(content)

  # Extract image parts from message content
  defp extract_image_parts(nil), do: []
  defp extract_image_parts(content) when is_binary(content), do: []

  defp extract_image_parts(content) when is_list(content) do
    content
    |> Enum.filter(fn
      %{"type" => type} when type in ["image", "image_url"] -> true
      _ -> false
    end)
    |> Enum.map(fn part ->
      %{
        type: part["type"],
        content: part["content"],
        # For image_url type, content might be the URL or a struct with url field
        url: get_image_url(part)
      }
    end)
  end

  defp extract_image_parts(_), do: []

  # Get the actual URL/data from an image part
  defp get_image_url(%{
         "type" => "image",
         "content" => content,
         "options" => %{"media_type" => media_type}
       })
       when is_binary(content) do
    "data:#{media_type};base64,#{content}"
  end

  defp get_image_url(%{"type" => "image", "content" => content}) when is_binary(content) do
    # Base64 encoded image - create a data URL, default to png
    "data:image/png;base64,#{content}"
  end

  defp get_image_url(%{"type" => "image_url", "content" => content}) when is_binary(content) do
    content
  end

  defp get_image_url(%{"type" => "image_url", "content" => %{"url" => url}}) do
    url
  end

  defp get_image_url(_), do: nil

  # ============================================================================
  # Event Handlers
  # ============================================================================

  # Hook is ready - register all node types and load saved agent or add sample nodes
  @impl true
  def handle_event("hook_ready", _params, socket) do
    Logger.info("Hook ready, registering #{length(socket.assigns.node_types)} node types")

    # Inject dynamic conversation options into node types
    node_types =
      inject_conversation_options(socket.assigns.node_types, socket.assigns.current_scope.profile)

    socket = push_event(socket, "register_node_types", %{types: node_types})

    # If we have a saved agent, load it; otherwise create sample nodes
    socket =
      if socket.assigns.agent_state do
        node_count = length(socket.assigns.agent_state["nodes"] || [])
        Logger.info("Loading saved workflow with #{node_count} nodes")
        push_event(socket, "load_graph", %{graph_data: socket.assigns.agent_state})
      else
        Logger.info("No saved workflow found")
        socket
      end

    {:noreply, socket}
  end

  # Handle full agent state changes - save to database
  @impl true
  def handle_event("graph_state_changed", %{"trigger" => trigger, "graph" => agent_data}, socket) do
    Logger.debug("Agent state changed: #{trigger}")

    node_count = length(agent_data["nodes"] || [])
    link_count = length(agent_data["links"] || [])
    message_input_nodes = extract_message_input_nodes(agent_data)
    image_input_nodes = extract_image_input_nodes(agent_data)
    conversation_display_nodes = extract_conversation_display_nodes(agent_data)

    # Skip the initial empty agent state if we have a saved agent to load
    # This prevents the JS initialization from overwriting our saved state
    if trigger == "graph_initialized" and socket.assigns.agent_state != nil do
      Logger.debug("Skipping graph_initialized - will load saved agent")
      {:noreply, socket}
    else
      # Save the agent state to database
      agent = socket.assigns.agent

      # Clean up conversation_data for removed conversation display nodes
      valid_conv_node_ids = MapSet.new(conversation_display_nodes, & &1.id)

      cleaned_conversation_data =
        socket.assigns.conversation_data
        |> Enum.filter(fn {node_id, _} -> MapSet.member?(valid_conv_node_ids, node_id) end)
        |> Map.new()

      # Clean up image_inputs for removed image input nodes
      valid_image_node_ids = MapSet.new(image_input_nodes, & &1.id)

      cleaned_image_inputs =
        socket.assigns.image_inputs
        |> Enum.filter(fn {node_id, _} -> MapSet.member?(valid_image_node_ids, node_id) end)
        |> Map.new()

      socket =
        case Agents.update_agent(agent, %{data: agent_data}) do
          {:ok, updated_agent} ->
            socket
            |> assign(:agent, updated_agent)
            |> assign(:agent_state, agent_data)
            |> assign(:node_count, node_count)
            |> assign(:link_count, link_count)
            |> assign(:message_input_nodes, message_input_nodes)
            |> assign(:image_input_nodes, image_input_nodes)
            |> assign(:image_inputs, cleaned_image_inputs)
            |> assign(:conversation_display_nodes, conversation_display_nodes)
            |> assign(:conversation_data, cleaned_conversation_data)

          {:error, _changeset} ->
            Logger.error("Failed to save agent to database")

            socket
            |> assign(:agent_state, agent_data)
            |> assign(:node_count, node_count)
            |> assign(:link_count, link_count)
            |> assign(:message_input_nodes, message_input_nodes)
            |> assign(:image_input_nodes, image_input_nodes)
            |> assign(:image_inputs, cleaned_image_inputs)
            |> assign(:conversation_display_nodes, conversation_display_nodes)
            |> assign(:conversation_data, cleaned_conversation_data)
        end

      # Trigger preview on structural agent changes only
      # Skip: node_moved (visual only), node_properties_updated (from execution results)
      socket =
        if trigger not in ["node_moved", "node_properties_updated"] do
          schedule_preview(socket)
        else
          socket
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
    agent = socket.assigns.agent

    case Agents.update_agent(agent, %{name: name}) do
      {:ok, updated_agent} ->
        socket =
          socket
          |> assign(:agent, updated_agent)
          |> assign(:editing_name, false)
          |> assign(:page_title, updated_agent.name)

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update agent name")}
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
    Logger.debug(
      "Property changed on node #{params["node_id"]}: #{params["property"]} = #{inspect(params["value"])}"
    )

    # Preview is triggered via graph_state_changed which follows property changes
    {:noreply, socket}
  end

  # Handle agent loaded
  @impl true
  def handle_event("graph_loaded", params, socket) do
    Logger.info("Agent loaded with #{params["node_count"]} nodes")
    # Trigger preview execution to display any loaded conversations
    {:noreply, schedule_preview(socket)}
  end

  # Handle run workflow button click
  @impl true
  def handle_event("run_workflow", _params, socket) do
    if socket.assigns.execution_status == :running do
      {:noreply, socket}
    else
      # Request the current agent from JS for execution
      # Keep conversation_data visible, only clear streaming content for fresh stream
      # Mark as non-preview execution so inputs are cleared on completion
      socket =
        socket
        |> assign(:execution_status, :running)
        |> assign(:is_preview_execution, false)
        |> assign(:streaming_content, %{})
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

  # Handle image upload validation - tracks which node is being uploaded to
  @impl true
  def handle_event("validate_image", %{"node-id" => node_id_str}, socket) do
    node_id = String.to_integer(node_id_str)
    # Store the target node for the pending upload
    {:noreply, assign(socket, :pending_upload_node_id, node_id)}
  end

  def handle_event("validate_image", _params, socket) do
    {:noreply, socket}
  end

  # Handle image removal
  def handle_event("remove_image", %{"node-id" => node_id_str}, socket) do
    node_id = String.to_integer(node_id_str)
    image_inputs = Map.delete(socket.assigns.image_inputs, node_id)
    {:noreply, assign(socket, :image_inputs, image_inputs)}
  end

  # Handle image upload progress - auto-uploads when complete
  defp handle_image_progress(:image, entry, socket) do
    if entry.done? do
      # Get the target node_id from the pending upload tracking
      node_id = socket.assigns[:pending_upload_node_id]

      if node_id do
        # Consume the completed entry
        uploaded =
          consume_uploaded_entry(socket, entry, fn %{path: path} ->
            {:ok, binary} = File.read(path)
            base64_data = Base.encode64(binary)

            {:ok,
             %{
               data: base64_data,
               media_type: entry.client_type,
               filename: entry.client_name
             }}
          end)

        # Store the uploaded image and clear the pending tracking
        image_inputs = Map.put(socket.assigns.image_inputs, node_id, uploaded)

        socket
        |> assign(:image_inputs, image_inputs)
        |> assign(:pending_upload_node_id, nil)
        |> then(&{:noreply, &1})
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle send messages button click
  @impl true
  def handle_event("send_messages", _params, socket) do
    if socket.assigns.execution_status == :running do
      {:noreply, socket}
    else
      # Request the current agent from JS for execution with message inputs
      # Keep conversation_data visible, only clear streaming content for fresh stream
      # Mark as non-preview execution so inputs are cleared on completion
      socket =
        socket
        |> assign(:execution_status, :running)
        |> assign(:is_preview_execution, false)
        |> assign(:streaming_content, %{})
        |> push_event("request_execution", %{})

      {:noreply, socket}
    end
  end

  # Handle execution request with agent data from JS
  @impl true
  def handle_event("execute_workflow", %{"graph" => agent_data}, socket) do
    Logger.info("Starting workflow execution with #{length(agent_data["nodes"] || [])} nodes")

    # Start async execution with message inputs, image inputs, and user profile
    message_inputs = socket.assigns.message_inputs
    image_inputs = socket.assigns.image_inputs
    user_profile = socket.assigns.current_scope.profile

    WorkflowExecutor.execute_async(agent_data, self(),
      message_inputs: message_inputs,
      image_inputs: image_inputs,
      user_profile: user_profile
    )

    {:noreply, socket}
  end

  # Handle preview execution request with agent data from JS
  @impl true
  def handle_event("execute_preview", %{"graph" => agent_data}, socket) do
    Logger.info("Starting preview execution with #{length(agent_data["nodes"] || [])} nodes")

    # Start async preview execution (no LLM calls)
    user_profile = socket.assigns.current_scope.profile

    WorkflowExecutor.execute_async(agent_data, self(),
      message_inputs: %{},
      user_profile: user_profile,
      preview: true
    )

    {:noreply, socket}
  end

  # Handle manual save conversation button click
  @impl true
  def handle_event("save_conversation_manual", params, socket) do
    %{
      "node_id" => node_id,
      "conversation_id" => conversation_id_from_params,
      "new_name" => new_name,
      "mode" => mode
    } = params

    user_profile = socket.assigns.current_scope.profile

    # Get the current agent to find connected messages
    agent = socket.assigns.agent
    execution_outputs = socket.assigns.execution_outputs

    # Check if conversation input (slot 1) is connected and has a value from execution
    conversation_id_from_input = get_connected_conversation_id(agent, node_id, execution_outputs)
    conversation_id = conversation_id_from_input || conversation_id_from_params

    Logger.info(
      "Manual save conversation: node=#{node_id}, conv=#{conversation_id}, mode=#{mode}"
    )

    # Find the save node and its input connection (use stored execution outputs)
    messages = get_connected_messages(agent, node_id, execution_outputs)

    if messages == [] do
      Logger.warning("No messages found for save conversation node #{node_id}")

      socket =
        put_flash(socket, :error, "No messages to save. Connect a messages source to the node.")

      {:noreply, socket}
    else
      # Serialize and save
      serialized = Play.LangChain.MessageSerializer.serialize_messages(messages)

      result =
        if conversation_id == "__new__" do
          Play.Conversations.create_conversation(user_profile, %{
            name: new_name,
            messages: serialized
          })
        else
          case Play.Conversations.get_conversation(user_profile, conversation_id) do
            nil ->
              {:error, :not_found}

            conversation ->
              final_messages =
                case mode do
                  "append" ->
                    existing =
                      Play.LangChain.MessageSerializer.deserialize_messages(conversation.messages)

                    existing ++ messages

                  _ ->
                    messages
                end

              serialized = Play.LangChain.MessageSerializer.serialize_messages(final_messages)
              Play.Conversations.update_conversation(conversation, %{messages: serialized})
          end
        end

      case result do
        {:ok, conversation} ->
          Logger.info(
            "Saved conversation '#{conversation.name}' with #{length(messages)} messages"
          )

          socket =
            socket
            |> put_flash(:info, "Conversation saved!")
            |> push_conversation_options_update()

          {:noreply, socket}

        {:error, :not_found} ->
          socket = put_flash(socket, :error, "Conversation not found")
          {:noreply, socket}

        {:error, changeset} ->
          Logger.error("Failed to save conversation: #{inspect(changeset.errors)}")
          socket = put_flash(socket, :error, "Failed to save conversation")
          {:noreply, socket}
      end
    end
  end

  # Push updated conversation options to the JS hook
  defp push_conversation_options_update(socket) do
    conversations = Play.Conversations.list_conversations(socket.assigns.current_scope.profile)

    load_values =
      [%{value: "__none__", label: "No conversation"}] ++
        Enum.map(conversations, fn conv ->
          %{value: conv.id, label: conv.name}
        end)

    save_values =
      [%{value: "__new__", label: "Create new..."}] ++
        Enum.map(conversations, fn conv ->
          %{value: conv.id, label: conv.name}
        end)

    push_event(socket, "update_conversation_options", %{
      load_values: load_values,
      save_values: save_values
    })
  end

  # Get messages from the node connected to a save conversation node's input (slot 0)
  # Uses stored execution outputs first, falls back to node properties
  defp get_connected_messages(agent, save_node_id, execution_outputs) do
    agent_data = if is_struct(agent, Play.Agent), do: agent.data, else: agent
    nodes = agent_data["nodes"] || []
    links = agent_data["links"] || []

    # Find the link connected to the save node's input (slot 0)
    connected_link =
      Enum.find(links, fn link ->
        [_link_id, _from_node, _from_slot, to_node, to_slot | _rest] = link
        to_node == save_node_id and to_slot == 0
      end)

    case connected_link do
      nil ->
        []

      [_link_id, from_node_id, from_slot | _rest] ->
        # First, try to get messages from stored execution outputs
        case Map.get(execution_outputs, from_node_id) do
          %{^from_slot => messages} when is_list(messages) ->
            messages

          _ ->
            # Fall back to node properties
            source_node = Enum.find(nodes, fn node -> node["id"] == from_node_id end)

            case source_node do
              nil ->
                []

              %{"properties" => props} ->
                # Try to get messages from various property names
                messages =
                  props["_messages"] ||
                    props["conversation_history"] ||
                    props["messages_out"] ||
                    []

                if is_list(messages) do
                  Play.LangChain.MessageSerializer.deserialize_messages(messages)
                else
                  []
                end

              _ ->
                []
            end
        end
    end
  end

  # Get conversation ID from the node connected to a save conversation node's input (slot 1)
  # Returns nil if not connected or no value available
  defp get_connected_conversation_id(agent, save_node_id, execution_outputs) do
    agent_data = if is_struct(agent, Play.Agent), do: agent.data, else: agent
    links = agent_data["links"] || []

    # Find the link connected to the save node's conversation input (slot 1)
    connected_link =
      Enum.find(links, fn link ->
        [_link_id, _from_node, _from_slot, to_node, to_slot | _rest] = link
        to_node == save_node_id and to_slot == 1
      end)

    case connected_link do
      nil ->
        nil

      [_link_id, from_node_id, from_slot | _rest] ->
        # Try to get conversation ID from stored execution outputs
        case Map.get(execution_outputs, from_node_id) do
          %{^from_slot => conversation_id} when is_binary(conversation_id) ->
            conversation_id

          _ ->
            nil
        end
    end
  end

  # Inject conversation options into node types that have dynamic_source: "conversations"
  defp inject_conversation_options(node_types, user_profile) do
    conversations = Play.Conversations.list_conversations(user_profile)

    # Build options for both load and save nodes
    load_values =
      [%{value: "__none__", label: "No conversation"}] ++
        Enum.map(conversations, fn conv ->
          %{value: conv.id, label: conv.name}
        end)

    save_values =
      [%{value: "__new__", label: "Create new..."}] ++
        Enum.map(conversations, fn conv ->
          %{value: conv.id, label: conv.name}
        end)

    Enum.map(node_types, fn node_type ->
      case node_type do
        %{type: "load_conversation", widgets: widgets} ->
          updated_widgets =
            Enum.map(widgets, fn widget ->
              case widget do
                %{type: "combo", options: %{dynamic_source: "conversations"}} ->
                  %{widget | options: Map.put(widget.options, :values, load_values)}

                _ ->
                  widget
              end
            end)

          %{node_type | widgets: updated_widgets}

        %{type: "save_conversation", widgets: widgets} ->
          updated_widgets =
            Enum.map(widgets, fn widget ->
              case widget do
                %{type: "combo", options: %{dynamic_source: "conversations"}} ->
                  %{widget | options: Map.put(widget.options, :values, save_values)}

                _ ->
                  widget
              end
            end)

          %{node_type | widgets: updated_widgets}

        _ ->
          node_type
      end
    end)
  end

  # ============================================================================
  # Execution Progress Handlers (handle_info)
  # ============================================================================

  # Handle preview trigger (debounced)
  @impl true
  def handle_info(:trigger_preview, socket) do
    Logger.info("Triggering preview execution")

    # Clear the timer reference
    socket = assign(socket, :preview_timer, nil)

    # Don't run preview if a full execution is already running
    if socket.assigns.execution_status == :running do
      Logger.debug("Skipping preview - full execution already running")
      {:noreply, socket}
    else
      # Request the current agent from JS for preview execution
      # Mark this as a preview execution so we don't clear inputs on completion
      socket =
        socket
        |> assign(:is_preview_execution, true)
        |> push_event("request_preview", %{})

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:node_executing, node_id}, socket) do
    Logger.debug("Node #{node_id} is executing")
    socket = push_event(socket, "node_executing", %{node_id: node_id})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:node_completed, node_id, result}, socket) do
    Logger.debug("Node #{node_id} completed with result: #{inspect(result, limit: 50)}")

    # Store execution outputs for later use (e.g., manual save)
    execution_outputs = Map.put(socket.assigns.execution_outputs, node_id, result)

    # Clear streaming content for the completed node
    streaming_content = Map.delete(socket.assigns.streaming_content, node_id)

    # Extract the primary output value (slot 0) for display nodes
    output_value =
      case result do
        %{0 => value} when is_binary(value) -> value
        %{0 => value} -> inspect(value, limit: 200)
        _ -> nil
      end

    socket =
      socket
      |> assign(:execution_outputs, execution_outputs)
      |> assign(:streaming_content, streaming_content)
      |> push_event("node_completed", %{node_id: node_id, output: output_value})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:stream_delta, node_id, content}, socket) do
    # Accumulate streaming content for markdown rendering
    streaming_content =
      Map.update(socket.assigns.streaming_content, node_id, content, &(&1 <> content))

    # Also push to JS for display nodes
    socket =
      socket
      |> assign(:streaming_content, streaming_content)
      |> push_event("stream_delta", %{node_id: node_id, content: content})

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

    # Only clear message/image inputs and trigger clear_message_inputs for full executions
    # Preview executions should not clear user inputs
    is_preview = socket.assigns[:is_preview_execution] || false

    socket =
      if is_preview do
        socket
        |> assign(:execution_status, :idle)
        |> push_event("execution_complete", %{})
      else
        socket
        |> assign(:execution_status, :complete)
        |> assign(:message_inputs, %{})
        |> assign(:image_inputs, %{})
        |> push_event("execution_complete", %{})
        |> push_event("clear_message_inputs", %{})
      end

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
  Add a node to the agent.
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
  Clear the entire agent.
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

  # ============================================================================
  # Preview Execution
  # ============================================================================

  # Debounce interval for preview execution (in milliseconds)
  @preview_debounce_ms 300

  # Schedule a preview execution with debouncing
  # If a preview is already scheduled, cancels it and schedules a new one
  defp schedule_preview(socket) do
    # Cancel any pending preview
    if socket.assigns[:preview_timer] do
      Process.cancel_timer(socket.assigns.preview_timer)
    end

    # Schedule new preview after debounce interval
    timer_ref = Process.send_after(self(), :trigger_preview, @preview_debounce_ms)

    assign(socket, :preview_timer, timer_ref)
  end
end
