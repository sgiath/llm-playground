defmodule PlayWeb.ConversationLive do
  use PlayWeb, :live_view

  alias Play.Conversations
  alias Play.LangChain.MessageSerializer

  @impl true
  def mount(%{"conv_id" => conv_id}, _session, socket) do
    profile = socket.assigns.current_scope.profile

    case Conversations.get_conversation(profile, conv_id) do
      nil ->
        socket =
          socket
          |> put_flash(:error, "Conversation not found")
          |> push_navigate(to: ~p"/conv")

        {:ok, socket}

      conversation ->
        items = build_message_items(conversation.messages)

        socket =
          socket
          |> assign(:conversation, conversation)
          |> assign(:page_title, conversation.name)
          |> assign(:editing_index, nil)
          |> assign(:edit_content, "")
          |> assign(:editing_name, false)
          |> assign(:name_form, to_form(%{"name" => conversation.name}))
          |> stream(:messages, items)

        {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/conv"} class="btn btn-ghost btn-sm btn-circle">
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
            <%= if @editing_name do %>
              <.form for={@name_form} phx-submit="save_name" class="flex items-center gap-2">
                <.input
                  field={@name_form[:name]}
                  type="text"
                  class="input input-bordered text-2xl font-bold py-1 px-2"
                  phx-mounted={JS.focus()}
                />
                <button type="submit" class="btn btn-primary btn-sm">
                  <.icon name="hero-check" class="w-4 h-4" />
                </button>
                <button type="button" phx-click="cancel_name_edit" class="btn btn-ghost btn-sm">
                  <.icon name="hero-x-mark" class="w-4 h-4" />
                </button>
              </.form>
            <% else %>
              <button
                phx-click="edit_name"
                class="text-2xl font-bold hover:bg-base-200 px-2 py-1 rounded-lg transition-colors group flex items-center gap-2"
              >
                {@conversation.name}
                <.icon name="hero-pencil" class="w-4 h-4 opacity-0 group-hover:opacity-50" />
              </button>
            <% end %>
          </div>
        </div>

        <div :if={@conversation.messages == []} class="text-center py-16">
          <.icon
            name="hero-chat-bubble-left-ellipsis"
            class="w-16 h-16 mx-auto text-base-content/30 mb-4"
          />
          <h2 class="text-xl font-semibold text-base-content/70 mb-2">No messages yet</h2>
          <p class="text-base-content/50">This conversation is empty.</p>
        </div>

        <div
          :if={@conversation.messages != []}
          id="messages-container"
          phx-hook="SortableHook"
          phx-update="stream"
          class="space-y-4"
        >
          <div
            :for={{dom_id, item} <- @streams.messages}
            id={dom_id}
            data-index={item.stream_index}
            class="card bg-base-200 group"
          >
            <div class="card-body p-4">
              <div class="flex items-start gap-3">
                <div class="drag-handle cursor-move opacity-0 group-hover:opacity-100 transition-opacity pt-1">
                  <.icon name="hero-bars-3" class="w-5 h-5 text-base-content/40" />
                </div>

                <div class="flex-1 min-w-0">
                  <div class="flex items-center gap-2 mb-2">
                    <span class={[
                      "badge badge-sm",
                      role_badge_class(item.message.role)
                    ]}>
                      {item.message.role}
                    </span>
                    <span :if={item.message.name} class="text-sm text-base-content/60">
                      {item.message.name}
                    </span>
                  </div>

                  <%= if @editing_index == item.index do %>
                    <form phx-submit="save_edit" class="space-y-2">
                      <textarea
                        name="content"
                        class="textarea textarea-bordered w-full min-h-32"
                        phx-mounted={JS.focus()}
                      >{@edit_content}</textarea>
                      <div class="flex gap-2">
                        <button type="submit" class="btn btn-primary btn-sm">
                          <.icon name="hero-check" class="w-4 h-4" /> Save
                        </button>
                        <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
                          Cancel
                        </button>
                      </div>
                    </form>
                  <% else %>
                    <div class="prose prose-sm max-w-none">
                      <p :if={extract_text_content(item.message) != ""} class="whitespace-pre-wrap">
                        {extract_text_content(item.message)}
                      </p>
                      <div
                        :if={extract_image_parts(item.message) != []}
                        class="flex flex-wrap gap-2 mt-2 not-prose"
                      >
                        <img
                          :for={image_part <- extract_image_parts(item.message)}
                          src={get_image_url(image_part)}
                          class="max-w-48 max-h-48 object-contain rounded-lg border border-base-300"
                          alt="User uploaded image"
                        />
                      </div>
                    </div>

                    <%!-- Tool calls with grouped responses --%>
                    <%= if has_tool_calls?(item.message) do %>
                      <div class="mt-3 space-y-3">
                        <div
                          :for={tool_call <- item.message.tool_calls}
                          class="rounded-lg overflow-hidden border border-base-300"
                        >
                          <%!-- Tool name header --%>
                          <div class="bg-base-300 px-3 py-2 flex items-center gap-2">
                            <.icon name="hero-wrench-screwdriver" class="w-4 h-4 text-warning" />
                            <span class="font-mono font-semibold text-sm">{tool_call.name}</span>
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
                                <.json_tree content={tool_args_to_json(tool_call.arguments)} />
                              </div>
                            </div>

                            <%!-- Response section (if available) --%>
                            <%= if response = find_tool_response(item.tool_responses, tool_call) do %>
                              <div class="p-3 text-sm">
                                <div class="flex items-center gap-2 mb-2 text-base-content/60">
                                  <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
                                  <span class="text-xs font-medium uppercase tracking-wide">
                                    Response
                                  </span>
                                </div>
                                <div class="bg-base-300/50 rounded p-2">
                                  <.json_tree content={extract_content(response)} />
                                </div>
                              </div>
                            <% end %>
                          </div>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>

                <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    :if={@editing_index != item.index}
                    phx-click="edit_message"
                    phx-value-index={item.index}
                    phx-value-id={item.id}
                    class="btn btn-ghost btn-xs btn-square"
                    title="Edit message"
                  >
                    <.icon name="hero-pencil" class="w-4 h-4" />
                  </button>
                  <button
                    phx-click="delete_message"
                    phx-value-index={item.index}
                    phx-value-id={item.id}
                    class="btn btn-ghost btn-xs btn-square text-error"
                    title="Delete message"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

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
    case JSON.decode(content) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> :error
    end
  end

  defp try_parse_json(_), do: :error

  @impl true
  def handle_event("edit_name", _params, socket) do
    {:noreply, assign(socket, :editing_name, true)}
  end

  @impl true
  def handle_event("cancel_name_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing_name, false)
      |> assign(:name_form, to_form(%{"name" => socket.assigns.conversation.name}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_name", %{"name" => new_name}, socket) do
    conversation = socket.assigns.conversation

    case Conversations.update_conversation(conversation, %{name: new_name}) do
      {:ok, updated_conversation} ->
        socket =
          socket
          |> assign(:conversation, updated_conversation)
          |> assign(:page_title, updated_conversation.name)
          |> assign(:editing_name, false)
          |> assign(:name_form, to_form(%{"name" => updated_conversation.name}))
          |> put_flash(:info, "Conversation renamed")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to rename conversation")}
    end
  end

  @impl true
  def handle_event("edit_message", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    messages = MessageSerializer.deserialize_messages(socket.assigns.conversation.messages)
    message = Enum.at(messages, index)
    content = extract_content(message)

    socket =
      socket
      |> assign(:editing_index, index)
      |> assign(:edit_content, content)

    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    socket =
      socket
      |> assign(:editing_index, nil)
      |> assign(:edit_content, "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("save_edit", %{"content" => new_content}, socket) do
    index = socket.assigns.editing_index
    conversation = socket.assigns.conversation
    messages = MessageSerializer.deserialize_messages(conversation.messages)
    message = Enum.at(messages, index)

    # Update the message content
    updated_message = %{message | content: new_content}
    updated_messages = List.replace_at(messages, index, updated_message)
    serialized = MessageSerializer.serialize_messages(updated_messages)

    case Conversations.update_conversation(conversation, %{messages: serialized}) do
      {:ok, updated_conversation} ->
        # Rebuild all items since grouping may have changed
        items = build_message_items(updated_conversation.messages)

        socket =
          socket
          |> assign(:conversation, updated_conversation)
          |> assign(:editing_index, nil)
          |> assign(:edit_content, "")
          |> stream(:messages, items, reset: true)
          |> put_flash(:info, "Message updated")

        {:noreply, socket}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update message")}
    end
  end

  @impl true
  def handle_event("delete_message", %{"index" => index_str} = _params, socket) do
    index = String.to_integer(index_str)
    conversation = socket.assigns.conversation
    messages = MessageSerializer.deserialize_messages(conversation.messages)

    if index >= 0 and index < length(messages) do
      updated_messages = List.delete_at(messages, index)
      serialized = MessageSerializer.serialize_messages(updated_messages)

      case Conversations.update_conversation(conversation, %{messages: serialized}) do
        {:ok, updated_conversation} ->
          items = build_message_items(updated_conversation.messages)

          socket =
            socket
            |> assign(:conversation, updated_conversation)
            |> stream(:messages, items, reset: true)

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to delete message")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid message index")}
    end
  end

  @impl true
  def handle_event("reorder_messages", %{"order" => new_order}, socket) do
    conversation = socket.assigns.conversation
    messages = MessageSerializer.deserialize_messages(conversation.messages)
    grouped_items = group_tool_messages(messages)

    # Validate against grouped items count (DOM elements), not raw messages
    if length(new_order) == length(grouped_items) do
      # Reorder the grouped items
      reordered_items = Enum.map(new_order, fn idx -> Enum.at(grouped_items, idx) end)
      # Flatten back to messages: main message + tool responses
      reordered_messages =
        Enum.flat_map(reordered_items, fn item ->
          tool_response_messages = Enum.map(item.tool_responses, fn {msg, _idx} -> msg end)
          [item.message | tool_response_messages]
        end)

      serialized = MessageSerializer.serialize_messages(reordered_messages)

      case Conversations.update_conversation(conversation, %{messages: serialized}) do
        {:ok, updated_conversation} ->
          items = build_message_items(updated_conversation.messages)

          socket =
            socket
            |> assign(:conversation, updated_conversation)
            |> stream(:messages, items, reset: true)

          {:noreply, socket}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to reorder messages")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid reorder operation")}
    end
  end

  # Build message items, grouping tool calls with their responses
  defp build_message_items(raw_messages) do
    raw_messages
    |> MessageSerializer.deserialize_messages()
    |> group_tool_messages()
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      item
      |> Map.put(:id, "msg-#{idx}")
      |> Map.put(:stream_index, idx)
    end)
  end

  # Group assistant messages with tool_calls together with following tool response messages
  defp group_tool_messages(messages) do
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
        msg.role == :tool and pending_group != nil ->
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

  defp role_badge_class(:system), do: "badge-info"
  defp role_badge_class(:user), do: "badge-primary"
  defp role_badge_class(:assistant), do: "badge-secondary"
  defp role_badge_class(:tool), do: "badge-warning"
  defp role_badge_class(_), do: "badge-ghost"

  defp extract_content(%{content: content}) when is_binary(content), do: content

  defp extract_content(%{content: content}) when is_list(content) do
    content
    |> Enum.map(fn
      %{content: c} when is_binary(c) -> c
      %{"content" => c} when is_binary(c) -> c
      other -> inspect(other)
    end)
    |> Enum.join("\n")
  end

  defp extract_content(%{content: nil}), do: ""
  defp extract_content(_), do: ""

  # Extract only text content from message (filtering out images)
  defp extract_text_content(%{content: content}) when is_binary(content), do: content

  defp extract_text_content(%{content: content}) when is_list(content) do
    content
    |> Enum.filter(fn
      %{type: :text} -> true
      %{type: "text"} -> true
      %{"type" => "text"} -> true
      _ -> false
    end)
    |> Enum.map(fn
      %{content: c} when is_binary(c) -> c
      %{"content" => c} when is_binary(c) -> c
      _ -> ""
    end)
    |> Enum.join("\n")
  end

  defp extract_text_content(%{content: nil}), do: ""
  defp extract_text_content(_), do: ""

  # Extract image parts from message content
  defp extract_image_parts(%{content: content}) when is_list(content) do
    Enum.filter(content, fn
      %{type: :image} -> true
      %{type: :image_url} -> true
      %{type: "image"} -> true
      %{type: "image_url"} -> true
      %{"type" => "image"} -> true
      %{"type" => "image_url"} -> true
      _ -> false
    end)
  end

  defp extract_image_parts(_), do: []

  # Get displayable URL for an image content part
  # ContentPart struct with keyword list options (from deserialization)
  defp get_image_url(%{type: :image, content: base64_data, options: options})
       when is_list(options) do
    media_type = Keyword.get(options, :media_type, "image/png")
    "data:#{media_type};base64,#{base64_data}"
  end

  # ContentPart struct with map options
  defp get_image_url(%{type: :image, content: base64_data, options: %{media_type: media_type}}) do
    "data:#{media_type};base64,#{base64_data}"
  end

  defp get_image_url(%{type: :image, content: base64_data, options: options})
       when is_map(options) do
    media_type = Map.get(options, :media_type) || Map.get(options, "media_type", "image/png")
    "data:#{media_type};base64,#{base64_data}"
  end

  # Fallback for image without options
  defp get_image_url(%{type: :image, content: base64_data}) do
    "data:image/png;base64,#{base64_data}"
  end

  defp get_image_url(%{type: :image_url, content: url}), do: url

  # Map-based (string keys) for raw JSON data
  defp get_image_url(%{
         "type" => "image",
         "content" => base64_data,
         "options" => %{"media_type" => media_type}
       }) do
    "data:#{media_type};base64,#{base64_data}"
  end

  defp get_image_url(%{"type" => "image", "content" => base64_data}) do
    "data:image/png;base64,#{base64_data}"
  end

  defp get_image_url(%{"type" => "image_url", "content" => url}), do: url
  defp get_image_url(_), do: nil

  defp has_tool_calls?(%{tool_calls: tool_calls}) when is_list(tool_calls) and tool_calls != [],
    do: true

  defp has_tool_calls?(_), do: false

  # Convert tool arguments to JSON string for json_tree component
  defp tool_args_to_json(nil), do: "{}"
  defp tool_args_to_json(args) when is_binary(args), do: args
  defp tool_args_to_json(args) when is_map(args), do: JSON.encode!(args)
  defp tool_args_to_json(args), do: inspect(args)

  # Find the tool response that matches a tool call by call_id or name
  defp find_tool_response(tool_responses, tool_call) do
    Enum.find_value(tool_responses, fn {response_msg, _idx} ->
      tool_results = response_msg.tool_results || []

      matching_result =
        Enum.find(tool_results, fn result ->
          result.tool_call_id == tool_call.call_id or result.name == tool_call.name
        end)

      if matching_result do
        response_msg
      else
        # Fallback: if there's only one tool response and one tool call, match them
        if length(tool_responses) == 1 do
          response_msg
        end
      end
    end)
  end
end
