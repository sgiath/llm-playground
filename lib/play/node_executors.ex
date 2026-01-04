defmodule Play.NodeExecutors do
  @moduledoc """
  Executes individual nodes in the workflow graph using LangChain.

  Each node type has a corresponding execute function that creates
  the appropriate LangChain structs or performs the required operation.
  """

  require Logger

  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.ChatModels.ChatGoogleAI
  alias LangChain.ChatModels.ChatGrok
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Function
  alias LangChain.FunctionParam
  alias Play.Conversations
  alias Play.LangChain.MessageSerializer

  @doc """
  Execute a node based on its type.

  Returns `{:ok, outputs}` where outputs is a map of `slot => value`,
  or `{:error, reason}` on failure.

  ## Node Types

  ### LLM Config Nodes
  - `llm/openai` - Creates a ChatOpenAI struct
  - `llm/anthropic` - Creates a ChatAnthropic struct
  - `llm/google_ai` - Creates a ChatGoogleAI struct
  - `llm/xai` - Creates a ChatGrok struct

  ### Message Nodes
  - `utility/message_builder` - Creates a LangChain Message
  - `utility/messages_combiner` - Combines messages into a list
  - `utility/prompt_template` - String interpolation with {{var}} syntax

  ### Tool Nodes
  - `tool/web_search_tool` - Creates a web search Function
  - `tool/tools_combiner` - Combines tools into a list

  ### Agent Node
  - `agent/agent` - Runs LLMChain with streaming callbacks

  ### Input Nodes
  - `input/text_input` - Returns text value
  - `input/number_input` - Returns numeric value
  - `input/variable` - Returns variable value

  ### Output Nodes
  - `output/display` - Returns input for display
  - `output/console` - Logs to console

  ### Utility Nodes
  - `utility/json_parse` - Parses JSON string
  - `utility/condition` - Routes based on condition
  """
  def execute(node_type, node, inputs, properties, context)

  # ============================================================================
  # LLM Config Nodes
  # ============================================================================

  # OpenAI LLM configuration node
  def execute("llm/openai", _node, inputs, properties, _context) do
    model = Map.get(properties, "model", "gpt-5.2")
    reasoning_effort = Map.get(properties, "reasoning_effort", "medium")

    llm =
      ChatOpenAI.new!(%{
        model: model,
        reasoning_effort: reasoning_effort,
        stream: true
      })

    {:ok, %{0 => llm}}
  end

  # Anthropic LLM configuration node
  def execute("llm/anthropic", _node, inputs, properties, _context) do
    model = Map.get(properties, "model", "claude-sonnet-4-20250514")
    reasoning_effort = Map.get(properties, "reasoning_effort", "medium")

    llm =
      ChatAnthropic.new!(%{
        model: model,
        reasoning_effort: reasoning_effort,
        stream: true
      })

    {:ok, %{0 => llm}}
  end

  # Google AI LLM configuration node
  def execute("llm/google_ai", _node, inputs, properties, _context) do
    model = Map.get(properties, "model", "gemini-2.5-pro")
    reasoning_effort = Map.get(properties, "reasoning_effort", "medium")

    llm =
      ChatGoogleAI.new!(%{
        model: model,
        reasoning_effort: reasoning_effort,
        stream: true
      })

    {:ok, %{0 => llm}}
  end

  # xAI Grok LLM configuration node
  def execute("llm/xai", _node, inputs, properties, _context) do
    model = Map.get(properties, "model", "grok-3")
    reasoning_effort = Map.get(properties, "reasoning_effort", "medium")

    llm =
      ChatGrok.new!(%{
        model: model,
        reasoning_effort: reasoning_effort,
        stream: true
      })

    {:ok, %{0 => llm}}
  end

  # ============================================================================
  # Message Nodes
  # ============================================================================

  # Message builder node - creates a LangChain Message
  def execute("utility/message_builder", _node, inputs, properties, _context) do
    content = get_input_or_property(inputs, 0, properties, "content", "")
    role = Map.get(properties, "role", "user")

    message =
      case role do
        "user" -> Message.new_user!(content)
        "assistant" -> Message.new_assistant!(content)
        "system" -> Message.new_system!(content)
        _ -> Message.new_user!(content)
      end

    {:ok, %{0 => message}}
  end

  # Messages combiner node - combines multiple messages into a list
  # Slot 0: messages array to append to (optional, defaults to empty list)
  # Slots 1+: individual messages to append
  def execute("utility/messages_combiner", _node, inputs, _properties, _context) do
    # Get base messages from slot 0, default to empty list if not connected
    base_messages =
      case Map.get(inputs, 0) do
        nil -> []
        messages when is_list(messages) -> messages
        _ -> []
      end

    # Get individual messages from slots 1+, sorted by slot number
    individual_messages =
      inputs
      |> Enum.filter(fn {slot, _} -> slot > 0 end)
      |> Enum.sort_by(fn {slot, _} -> slot end)
      |> Enum.map(fn {_slot, value} -> value end)
      |> Enum.reject(&is_nil/1)
      |> List.flatten()

    # Combine base messages with individual messages
    {:ok, %{0 => base_messages ++ individual_messages}}
  end

  # Prompt template node - string interpolation with {{variable}} syntax
  def execute("utility/prompt_template", _node, inputs, properties, _context) do
    template = Map.get(properties, "template", "")
    var1_name = Map.get(properties, "var1_name", "var1")
    var2_name = Map.get(properties, "var2_name", "var2")
    var3_name = Map.get(properties, "var3_name", "var3")

    var1 = Map.get(inputs, 0, "")
    var2 = Map.get(inputs, 1, "")
    var3 = Map.get(inputs, 2, "")

    result =
      template
      |> String.replace("{{#{var1_name}}}", to_string(var1 || ""))
      |> String.replace("{{#{var2_name}}}", to_string(var2 || ""))
      |> String.replace("{{#{var3_name}}}", to_string(var3 || ""))

    {:ok, %{0 => result}}
  end

  # ============================================================================
  # Tool Nodes
  # ============================================================================

  # Web search tool node - creates a LangChain Function for web search using SearxNG
  def execute("tool/web_search_tool", _node, _inputs, properties, _context) do
    max_results = Map.get(properties, "max_results", 5)

    function =
      Function.new!(%{
        name: "web_search",
        description:
          "Search the web for current information. Use this when you need to find up-to-date information about any topic.",
        parameters: [
          FunctionParam.new!(%{name: "query", type: :string, required: true})
        ],
        function: fn %{"query" => query}, _context ->
          execute_searxng_search(query, max_results)
        end
      })

    {:ok, %{0 => function}}
  end

  # Tools combiner node - combines multiple tools into a list
  def execute("tool/tools_combiner", _node, inputs, _properties, _context) do
    tools =
      inputs
      |> Enum.sort_by(fn {slot, _} -> slot end)
      |> Enum.map(fn {_slot, value} -> value end)
      |> Enum.reject(&is_nil/1)
      |> List.flatten()

    {:ok, %{0 => tools}}
  end

  # ============================================================================
  # Agent Nodes
  # ============================================================================

  # Stateless Agent node - runs LLMChain with streaming callbacks, no conversation history
  def execute("agent/stateless_agent", node, inputs, properties, context) do
    llm_config = Map.get(inputs, 0)
    system_override = Map.get(inputs, 1)
    messages = Map.get(inputs, 2, [])
    tools = Map.get(inputs, 3, [])

    base_system_prompt =
      system_override || Map.get(properties, "system_prompt", "You are a helpful assistant.")

    # Enhance system prompt with tool descriptions when tools are connected
    system_prompt = build_system_prompt_with_tools(base_system_prompt, tools)

    stream = Map.get(properties, "stream", true)

    if is_nil(llm_config) do
      {:error, "No LLM configuration provided to Agent node"}
    else
      # Update the LLM to use the stream setting from the agent
      llm_config = %{llm_config | stream: stream}

      # Get caller_pid and node_id from context for streaming callbacks
      caller_pid = Map.get(context, :caller_pid)
      node_id = node["id"]

      # Create streaming callback handler
      handler =
        if caller_pid do
          %{
            on_message_delta: fn _chain, delta ->
              if delta.content && delta.content != "" do
                send(caller_pid, {:stream_delta, node_id, delta.content})
              end
            end
          }
        else
          %{}
        end

      # Filter out system messages from input - agent defines its own system prompt
      filtered_messages =
        messages
        |> List.wrap()
        |> Enum.reject(fn msg -> msg.role == :system end)

      # Build the chain
      chain =
        %{llm: llm_config}
        |> LLMChain.new!()
        |> LLMChain.add_message(Message.new_system!(system_prompt))
        |> LLMChain.add_messages(filtered_messages)

      # Add tools if present
      chain =
        if tools != [] and tools != nil do
          LLMChain.add_tools(chain, tools)
        else
          chain
        end

      # Add callback handler
      chain = LLMChain.add_callback(chain, handler)

      # Run the chain
      case LLMChain.run(chain, mode: :while_needs_response) do
        {:ok, updated_chain} ->
          # Get the last assistant message
          last_message = updated_chain.last_message
          response_text = extract_message_content(last_message)

          # Get all messages for output
          messages_out = updated_chain.messages

          # Get tool calls if any
          tool_calls =
            if last_message && last_message.tool_calls do
              last_message.tool_calls
            else
              []
            end

          {:ok,
           %{
             0 => response_text,
             1 => messages_out,
             2 => tool_calls
           }}

        {:error, _chain, %LangChain.LangChainError{message: message}} ->
          {:error, "Agent execution failed: #{message}"}

        {:error, _chain, error} ->
          {:error, "Agent execution failed: #{inspect(error)}"}

        {:error, reason} ->
          {:error, "Agent execution failed: #{inspect(reason)}"}
      end
    end
  end

  # ============================================================================
  # Input Nodes
  # ============================================================================

  # Text input node - returns the configured text value
  def execute("input/text_input", _node, _inputs, properties, _context) do
    value = Map.get(properties, "value", "")
    {:ok, %{0 => value}}
  end

  # Number input node - returns the configured numeric value
  def execute("input/number_input", _node, _inputs, properties, _context) do
    value = Map.get(properties, "value", 0)
    {:ok, %{0 => value}}
  end

  # Variable node - returns the default value
  def execute("input/variable", _node, _inputs, properties, _context) do
    value = Map.get(properties, "default_value", "")
    {:ok, %{0 => value}}
  end

  # Message input node - returns a user message from runtime input
  # The message content is injected via context[:message_inputs][node_id] at execution time
  def execute("input/message_input", node, _inputs, _properties, context) do
    node_id = node["id"]
    message_inputs = Map.get(context, :message_inputs, %{})
    content = Map.get(message_inputs, node_id, "")

    # Use dummy message if content is empty to allow workflow to continue
    actual_content = if content == "" or content == nil, do: "No user message", else: content
    message = Message.new_user!(actual_content)
    {:ok, %{0 => message}}
  end

  # ============================================================================
  # Output Nodes
  # ============================================================================

  # Display node - returns the input value for frontend display
  def execute("output/display", _node, inputs, _properties, _context) do
    value = Map.get(inputs, 0, "")
    {:ok, %{0 => value}}
  end

  # Console node - logs the input value
  def execute("output/console", _node, inputs, properties, _context) do
    prefix = Map.get(properties, "prefix", "")
    value = Map.get(inputs, 0, "")

    if prefix != "" do
      Logger.info("#{prefix}: #{inspect(value)}")
    else
      Logger.info("Console output: #{inspect(value)}")
    end

    {:ok, %{}}
  end

  # Conversation display node - serializes messages for sidebar display
  def execute("output/conversation_display", _node, inputs, _properties, _context) do
    messages = Map.get(inputs, 0, [])
    serialized_messages = MessageSerializer.serialize_messages(messages)

    # Return empty outputs but send property update with conversation data
    {:ok, %{}, %{"conversation_messages" => serialized_messages}}
  end

  # ============================================================================
  # Utility Nodes
  # ============================================================================

  # JSON parse node - parses JSON string to Elixir map
  def execute("utility/json_parse", _node, inputs, _properties, _context) do
    text = Map.get(inputs, 0, "{}")

    case Jason.decode(text) do
      {:ok, parsed} -> {:ok, %{0 => parsed}}
      {:error, _} -> {:ok, %{0 => %{"error" => "Invalid JSON"}}}
    end
  end

  # Condition node - routes value based on condition
  def execute("utility/condition", _node, inputs, properties, _context) do
    value = Map.get(inputs, 0)
    condition = Map.get(inputs, 1)
    check_truthy = Map.get(properties, "check_truthy", false)

    cond_result =
      if check_truthy do
        !!value
      else
        !!condition
      end

    if cond_result do
      {:ok, %{0 => value, 1 => nil}}
    else
      {:ok, %{0 => nil, 1 => value}}
    end
  end

  # ============================================================================
  # Storage Nodes
  # ============================================================================

  # Load Conversation node - loads messages from the database
  def execute("storage/load_conversation", _node, _inputs, properties, context) do
    conversation_id = Map.get(properties, "conversation_id")
    user_profile = Map.get(context, :user_profile)

    cond do
      is_nil(conversation_id) or conversation_id == "" ->
        Logger.info("[Load Conversation] No conversation selected, returning empty messages")
        {:ok, %{0 => []}}

      is_nil(user_profile) ->
        Logger.warning("[Load Conversation] No user profile in context")
        {:error, "User profile not available"}

      true ->
        case Conversations.get_conversation(user_profile, conversation_id) do
          nil ->
            Logger.warning("[Load Conversation] Conversation #{conversation_id} not found")
            {:ok, %{0 => []}}

          conversation ->
            messages = MessageSerializer.deserialize_messages(conversation.messages)

            Logger.info(
              "[Load Conversation] Loaded #{length(messages)} messages from '#{conversation.name}'"
            )

            {:ok, %{0 => messages}}
        end
    end
  end

  # Save Conversation node - saves messages to the database
  def execute("storage/save_conversation", _node, inputs, properties, context) do
    messages = Map.get(inputs, 0, [])
    conversation_id = Map.get(properties, "conversation_id")
    new_name = Map.get(properties, "new_name", "New Conversation")
    mode = Map.get(properties, "mode", "override")
    auto_save = Map.get(properties, "auto_save", false)
    user_profile = Map.get(context, :user_profile)

    # Only save if auto_save is enabled
    if auto_save do
      do_save_conversation(user_profile, conversation_id, new_name, mode, messages)
    else
      Logger.info("[Save Conversation] Auto-save disabled, skipping save")
      {:ok, %{}}
    end
  end

  defp do_save_conversation(nil, _conversation_id, _new_name, _mode, _messages) do
    Logger.warning("[Save Conversation] No user profile in context")
    {:error, "User profile not available"}
  end

  defp do_save_conversation(user_profile, "__new__", new_name, _mode, messages) do
    # Create a new conversation
    serialized = MessageSerializer.serialize_messages(messages)

    case Conversations.create_conversation(user_profile, %{name: new_name, messages: serialized}) do
      {:ok, conversation} ->
        Logger.info(
          "[Save Conversation] Created new conversation '#{conversation.name}' with #{length(messages)} messages"
        )

        {:ok, %{}, %{"conversation_id" => conversation.id}}

      {:error, changeset} ->
        Logger.error(
          "[Save Conversation] Failed to create conversation: #{inspect(changeset.errors)}"
        )

        {:error, "Failed to create conversation"}
    end
  end

  defp do_save_conversation(user_profile, conversation_id, _new_name, mode, messages) do
    case Conversations.get_conversation(user_profile, conversation_id) do
      nil ->
        Logger.warning("[Save Conversation] Conversation #{conversation_id} not found")
        {:error, "Conversation not found"}

      conversation ->
        final_messages =
          case mode do
            "append" ->
              existing = MessageSerializer.deserialize_messages(conversation.messages)
              existing ++ messages

            _ ->
              messages
          end

        serialized = MessageSerializer.serialize_messages(final_messages)

        case Conversations.update_conversation(conversation, %{messages: serialized}) do
          {:ok, _updated} ->
            Logger.info(
              "[Save Conversation] Updated '#{conversation.name}' with #{length(final_messages)} messages (mode: #{mode})"
            )

            {:ok, %{}}

          {:error, changeset} ->
            Logger.error(
              "[Save Conversation] Failed to update conversation: #{inspect(changeset.errors)}"
            )

            {:error, "Failed to update conversation"}
        end
    end
  end

  # ============================================================================
  # Fallback for Unknown Node Types
  # ============================================================================

  def execute(node_type, _node, _inputs, _properties, _context) do
    Logger.warning("Unknown node type: #{node_type}")
    {:ok, %{0 => nil}}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp get_input_or_property(inputs, slot, properties, prop_name, default) do
    case Map.get(inputs, slot) do
      nil -> Map.get(properties, prop_name, default)
      value -> value
    end
  end

  # Build system prompt with tool descriptions when tools are available
  defp build_system_prompt_with_tools(base_prompt, nil), do: base_prompt
  defp build_system_prompt_with_tools(base_prompt, []), do: base_prompt

  defp build_system_prompt_with_tools(base_prompt, tools) when is_list(tools) do
    tool_descriptions =
      tools
      |> Enum.map(fn
        %LangChain.Function{name: name, description: description} ->
          "- #{name}: #{description}"

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    if tool_descriptions == "" do
      base_prompt
    else
      """
      #{base_prompt}

      You have access to the following tools that you can use to help answer questions:

      #{tool_descriptions}

      Use these tools when appropriate to provide accurate and up-to-date information.
      """
    end
  end

  # Extract text content from a LangChain Message
  # Content can be a string, a list of ContentParts, or nil
  defp extract_message_content(nil), do: ""

  defp extract_message_content(%{content: content}) when is_binary(content), do: content

  defp extract_message_content(%{content: content}) when is_list(content) do
    content
    |> Enum.filter(fn
      %{type: :text} -> true
      _ -> false
    end)
    |> Enum.map(fn %{content: text} -> text end)
    |> Enum.join("")
  end

  defp extract_message_content(_), do: ""

  defp execute_searxng_search(query, max_results) do
    Logger.info("Executing web search via SearxNG: #{query}")

    url = "https://search.sgiath.dev/search"

    case Req.get(url, params: [q: query, format: "json"]) do
      {:ok, %{status: 200, body: body}} ->
        # Pass the raw JSON results to the LLM, limited to max_results
        results =
          body
          |> Map.update("results", [], &Enum.take(&1, max_results))
          |> Jason.encode!()

        {:ok, results}

      {:ok, %{status: status, body: body}} ->
        {:error, "SearxNG API error (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, "SearxNG request failed: #{inspect(reason)}"}
    end
  end
end
