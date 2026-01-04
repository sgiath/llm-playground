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
  def execute("utility/messages_combiner", _node, inputs, _properties, _context) do
    messages =
      inputs
      |> Enum.sort_by(fn {slot, _} -> slot end)
      |> Enum.map(fn {_slot, value} -> value end)
      |> Enum.reject(&is_nil/1)
      |> List.flatten()

    {:ok, %{0 => messages}}
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

  # Web search tool node - creates a LangChain Function for web search
  def execute("tool/web_search_tool", _node, _inputs, properties, _context) do
    provider = Map.get(properties, "provider", "tavily")
    max_results = Map.get(properties, "max_results", 5)
    search_depth = Map.get(properties, "search_depth", "basic")

    function =
      Function.new!(%{
        name: "web_search",
        description:
          "Search the web for current information. Use this when you need to find up-to-date information about any topic.",
        parameters: [
          FunctionParam.new!(%{name: "query", type: :string, required: true})
        ],
        function: fn %{"query" => query}, _context ->
          execute_web_search(query, provider, max_results, search_depth)
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

    system_prompt =
      system_override || Map.get(properties, "system_prompt", "You are a helpful assistant.")

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

      # Build the chain
      chain =
        %{llm: llm_config}
        |> LLMChain.new!()
        |> LLMChain.add_message(Message.new_system!(system_prompt))
        |> LLMChain.add_messages(List.wrap(messages))

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

  # Stateful Agent node - maintains conversation history across runs
  def execute("agent/stateful_agent", node, inputs, properties, context) do
    llm_config = Map.get(inputs, 0)
    system_override = Map.get(inputs, 1)
    user_message_input = Map.get(inputs, 2)
    tools = Map.get(inputs, 3, [])

    # Extract content from message struct or use as-is if string
    {user_message, user_message_content} =
      case user_message_input do
        %Message{} = msg ->
          {msg, extract_message_content(msg)}

        content when is_binary(content) ->
          {nil, content}

        _ ->
          {nil, ""}
      end

    system_prompt =
      system_override || Map.get(properties, "system_prompt", "You are a helpful assistant.")

    stream = Map.get(properties, "stream", true)

    # Load existing conversation history from properties (full serialized messages)
    conversation_history = Map.get(properties, "conversation_history", [])

    if is_nil(llm_config) do
      {:error, "No LLM configuration provided to Stateful Agent node"}
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

      # Build the chain
      chain = LLMChain.new!(%{llm: llm_config})

      # Add existing conversation history or start fresh with system prompt
      chain =
        if conversation_history == [] do
          # Fresh conversation - add system prompt
          LLMChain.add_message(chain, Message.new_system!(system_prompt))
        else
          # Restore from history - deserialize all messages
          Enum.reduce(conversation_history, chain, fn msg, acc ->
            LLMChain.add_message(acc, deserialize_message(msg))
          end)
        end

      # Add the new user message if provided (either as Message struct or created from content)
      chain =
        cond do
          user_message != nil ->
            # Use the Message struct directly
            LLMChain.add_message(chain, user_message)

          user_message_content != "" ->
            # Create a new message from the string content
            LLMChain.add_message(chain, Message.new_user!(user_message_content))

          true ->
            chain
        end

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

          # Get all messages from the chain (includes full metadata, usage, etc.)
          messages_out = updated_chain.messages

          # Serialize the full message history for storage
          serialized_history = serialize_messages(messages_out)

          # Get tool calls if any
          tool_calls =
            if last_message && last_message.tool_calls do
              last_message.tool_calls
            else
              []
            end

          # Return outputs AND property updates for stateful agent
          # Both slot 1 and conversation_history contain full message data
          {:ok,
           %{
             0 => response_text,
             1 => messages_out,
             2 => tool_calls
           }, %{"conversation_history" => serialized_history}}

        {:error, _chain, %LangChain.LangChainError{message: message}} ->
          {:error, "Stateful Agent execution failed: #{message}"}

        {:error, _chain, error} ->
          {:error, "Stateful Agent execution failed: #{inspect(error)}"}

        {:error, reason} ->
          {:error, "Stateful Agent execution failed: #{inspect(reason)}"}
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
    serialized_messages = serialize_messages(messages)

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

  # Serialize a list of LangChain.Message structs to maps for JSON transport
  defp serialize_messages(messages) when is_list(messages) do
    Enum.map(messages, &serialize_message/1)
  end

  defp serialize_messages(_), do: []

  defp serialize_message(%{role: role, content: _content} = message) do
    base = %{
      "role" => to_string(role),
      "content" => extract_message_content(message)
    }

    # Add tool_calls if present
    base =
      case Map.get(message, :tool_calls) do
        nil -> base
        [] -> base
        tool_calls -> Map.put(base, "tool_calls", serialize_tool_calls(tool_calls))
      end

    # Add tool_results if present
    base =
      case Map.get(message, :tool_results) do
        nil -> base
        results -> Map.put(base, "tool_results", serialize_tool_results(results))
      end

    # Add usage from metadata if present
    # Access struct fields directly since LangChain.Message doesn't implement Access
    usage =
      case message do
        %{metadata: %{usage: usage}} -> usage
        _ -> nil
      end

    case usage do
      %{input: input, output: output} = u ->
        raw = Map.get(u, :raw, %{})
        total = Map.get(raw, "total_tokens", input + output)

        Map.put(base, "usage", %{
          "input" => input,
          "output" => output,
          "total" => total
        })

      _ ->
        base
    end
  end

  defp serialize_message(%{"role" => _} = message) do
    # Already a map, just return it
    message
  end

  defp serialize_message(_), do: nil

  # Deserialize a map back to a LangChain.Message struct
  defp deserialize_message(%{"role" => role, "content" => content} = msg) do
    base_msg =
      case role do
        "system" -> Message.new_system!(content)
        "user" -> Message.new_user!(content)
        "assistant" -> Message.new_assistant!(content)
        "tool" -> Message.new_tool_result!(%{tool_use_id: msg["tool_use_id"], content: content})
        _ -> Message.new_user!(content)
      end

    # Add tool_calls if present (for assistant messages)
    base_msg =
      case msg["tool_calls"] do
        nil ->
          base_msg

        [] ->
          base_msg

        tool_calls when is_list(tool_calls) ->
          deserialized_calls =
            Enum.map(tool_calls, fn tc ->
              %LangChain.Message.ToolCall{
                call_id: tc["call_id"],
                name: tc["name"],
                arguments: tc["arguments"] || %{},
                type: :function,
                status: :complete
              }
            end)

          %{base_msg | tool_calls: deserialized_calls}
      end

    # Add usage metadata if present
    base_msg =
      case msg["usage"] do
        %{"input" => input, "output" => output} = usage ->
          total = usage["total"] || input + output

          token_usage = %LangChain.TokenUsage{
            input: input,
            output: output,
            raw: %{"total_tokens" => total}
          }

          %{base_msg | metadata: %{usage: token_usage}}

        _ ->
          base_msg
      end

    base_msg
  end

  defp deserialize_message(%Message{} = msg), do: msg
  defp deserialize_message(_), do: Message.new_user!("")

  defp serialize_tool_calls(tool_calls) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(fn
      %{name: name, arguments: args} = tc ->
        %{
          "name" => name,
          "arguments" => args,
          "call_id" => Map.get(tc, :call_id) || Map.get(tc, :id)
        }

      %{"name" => name, "arguments" => args} = tc ->
        %{
          "name" => name,
          "arguments" => args,
          "call_id" => Map.get(tc, "call_id") || Map.get(tc, "id")
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp serialize_tool_calls(_), do: []

  defp serialize_tool_results(results) when is_list(results) do
    Enum.map(results, fn
      %{content: content, tool_use_id: id} ->
        %{"content" => content, "tool_use_id" => id}

      %{"content" => content, "tool_use_id" => id} ->
        %{"content" => content, "tool_use_id" => id}

      other ->
        %{"content" => inspect(other)}
    end)
  end

  defp serialize_tool_results(result) when is_binary(result), do: [%{"content" => result}]
  defp serialize_tool_results(_), do: []

  defp execute_web_search(query, provider, max_results, _search_depth) do
    Logger.info("Executing web search: #{query} via #{provider}")

    case provider do
      "tavily" ->
        execute_tavily_search(query, max_results)

      _ ->
        {:ok,
         "Web search for '#{query}' would be performed via #{provider}. " <>
           "Configure API keys for actual results."}
    end
  end

  defp execute_tavily_search(query, max_results) do
    api_key = System.get_env("TAVILY_API_KEY")

    if api_key do
      case Req.post("https://api.tavily.com/search",
             json: %{
               api_key: api_key,
               query: query,
               max_results: max_results,
               include_answer: true
             }
           ) do
        {:ok, %{status: 200, body: body}} ->
          answer = body["answer"] || ""

          results =
            (body["results"] || [])
            |> Enum.map(fn r -> "- #{r["title"]}: #{r["content"]}" end)
            |> Enum.join("\n")

          {:ok, "#{answer}\n\nSources:\n#{results}"}

        {:ok, %{status: status, body: body}} ->
          {:error, "Tavily API error (#{status}): #{inspect(body)}"}

        {:error, reason} ->
          {:error, "Tavily request failed: #{inspect(reason)}"}
      end
    else
      {:ok,
       "Web search for '#{query}' - TAVILY_API_KEY not configured. " <>
         "Set the environment variable to enable web search."}
    end
  end
end
