defmodule Play.LangChain.MessageSerializer do
  @moduledoc """
  Complete serialization/deserialization of LangChain.Message structs.

  Preserves all fields including nested structs for lossless DB storage.
  Uses a `_struct` key to identify struct types during deserialization.
  """

  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias LangChain.Message.ToolCall
  alias LangChain.Message.ToolResult
  alias LangChain.TokenUsage

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Serialize a list of LangChain.Message structs to a JSON-compatible list of maps.
  """
  @spec serialize_messages([Message.t()]) :: [map()]
  def serialize_messages(messages) when is_list(messages) do
    Enum.map(messages, &serialize_message/1)
  end

  def serialize_messages(_), do: []

  @doc """
  Deserialize a list of maps back to LangChain.Message structs.
  """
  @spec deserialize_messages([map()]) :: [Message.t()]
  def deserialize_messages(data) when is_list(data) do
    Enum.map(data, &deserialize_message/1)
  end

  def deserialize_messages(_), do: []

  @doc """
  Serialize a single LangChain.Message struct to a JSON-compatible map.
  """
  @spec serialize_message(Message.t() | map()) :: map() | nil
  def serialize_message(%Message{} = message) do
    # For tool messages, ensure content is populated from tool_results if needed
    # Fresh messages from LangChain may have content as nil/ContentParts while
    # the actual result is in tool_results[0].content
    content = normalize_tool_message_content(message)

    %{
      "_struct" => "Message",
      "role" => atom_to_string(message.role),
      "content" => serialize_content(content),
      "processed_content" => serialize_any(message.processed_content),
      "index" => message.index,
      "status" => atom_to_string(message.status),
      "name" => message.name,
      "tool_calls" => serialize_tool_calls(message.tool_calls),
      "tool_results" => serialize_tool_results(message.tool_results),
      "metadata" => serialize_metadata(message.metadata)
    }
  end

  # Already a map (possibly from JSON), return as-is
  def serialize_message(%{"_struct" => "Message"} = data), do: data

  def serialize_message(_), do: nil

  @doc """
  Deserialize a map back to a LangChain.Message struct.
  """
  @spec deserialize_message(map()) :: Message.t()
  def deserialize_message(%{"_struct" => "Message"} = data) do
    role = string_to_atom(data["role"], [:system, :user, :assistant, :tool])
    status = string_to_atom(data["status"], [:complete, :cancelled, :length])

    base_attrs = %{
      role: role,
      content: deserialize_content(data["content"]),
      index: data["index"],
      status: status,
      name: data["name"]
    }

    # Build the message based on role
    message =
      case role do
        :system -> Message.new_system!(base_attrs.content || "")
        :user -> Message.new_user!(base_attrs.content || "")
        :assistant -> Message.new_assistant!(base_attrs.content || "")
        :tool -> build_tool_message(data)
        _ -> Message.new_user!(base_attrs.content || "")
      end

    # Update fields that may have been set differently by the constructors
    message = %{message | status: status}
    message = if data["index"], do: %{message | index: data["index"]}, else: message
    message = if data["name"], do: %{message | name: data["name"]}, else: message

    # Add processed_content if present
    message =
      if data["processed_content"] do
        %{message | processed_content: deserialize_any(data["processed_content"])}
      else
        message
      end

    # Add tool_calls if present (for assistant messages)
    message =
      if data["tool_calls"] && data["tool_calls"] != [] do
        %{message | tool_calls: deserialize_tool_calls(data["tool_calls"])}
      else
        message
      end

    # Add tool_results if present (for tool messages)
    message =
      if data["tool_results"] && data["tool_results"] != [] do
        %{message | tool_results: deserialize_tool_results(data["tool_results"])}
      else
        message
      end

    # Add metadata if present
    message =
      if data["metadata"] do
        %{message | metadata: deserialize_metadata(data["metadata"])}
      else
        message
      end

    message
  end

  # Handle legacy format without _struct key
  def deserialize_message(%{"role" => role, "content" => content} = data) do
    # Convert to new format and deserialize
    new_data =
      Map.merge(data, %{
        "_struct" => "Message",
        "role" => role,
        "content" => content
      })

    deserialize_message(new_data)
  end

  # Already a Message struct
  def deserialize_message(%Message{} = message), do: message

  def deserialize_message(_), do: Message.new_user!("")

  # ===========================================================================
  # ToolCall Serialization
  # ===========================================================================

  defp serialize_tool_calls(nil), do: nil
  defp serialize_tool_calls([]), do: []

  defp serialize_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &serialize_tool_call/1)
  end

  defp serialize_tool_call(%ToolCall{} = tc) do
    %{
      "_struct" => "ToolCall",
      "status" => atom_to_string(tc.status),
      "type" => atom_to_string(tc.type),
      "call_id" => tc.call_id,
      "name" => tc.name,
      "arguments" => tc.arguments,
      "index" => tc.index
    }
  end

  defp serialize_tool_call(%{} = tc) do
    # Handle map-based tool calls
    %{
      "_struct" => "ToolCall",
      "status" => atom_to_string(tc[:status] || tc["status"]),
      "type" => atom_to_string(tc[:type] || tc["type"] || :function),
      "call_id" => tc[:call_id] || tc["call_id"] || tc[:id] || tc["id"],
      "name" => tc[:name] || tc["name"],
      "arguments" => tc[:arguments] || tc["arguments"],
      "index" => tc[:index] || tc["index"]
    }
  end

  defp deserialize_tool_calls(nil), do: nil
  defp deserialize_tool_calls([]), do: []

  defp deserialize_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &deserialize_tool_call/1)
  end

  defp deserialize_tool_call(%{"_struct" => "ToolCall"} = data) do
    ToolCall.new!(%{
      status: string_to_atom(data["status"], [:incomplete, :complete]),
      type: string_to_atom(data["type"], [:function]),
      call_id: data["call_id"],
      name: data["name"],
      arguments: data["arguments"],
      index: data["index"]
    })
  end

  defp deserialize_tool_call(%{} = data) do
    # Handle legacy format
    ToolCall.new!(%{
      status: string_to_atom(data["status"], [:incomplete, :complete]) || :complete,
      type: string_to_atom(data["type"], [:function]) || :function,
      call_id: data["call_id"] || data["id"],
      name: data["name"],
      arguments: data["arguments"],
      index: data["index"]
    })
  end

  # ===========================================================================
  # ToolResult Serialization
  # ===========================================================================

  defp serialize_tool_results(nil), do: nil
  defp serialize_tool_results([]), do: []

  defp serialize_tool_results(tool_results) when is_list(tool_results) do
    Enum.map(tool_results, &serialize_tool_result/1)
  end

  defp serialize_tool_result(%ToolResult{} = tr) do
    %{
      "_struct" => "ToolResult",
      "type" => atom_to_string(tr.type),
      "tool_call_id" => tr.tool_call_id,
      "name" => tr.name,
      "content" => serialize_content(tr.content),
      "processed_content" => serialize_any(tr.processed_content),
      "display_text" => tr.display_text,
      "is_error" => tr.is_error,
      "options" => serialize_options(tr.options)
    }
  end

  defp serialize_tool_result(%{} = tr) do
    %{
      "_struct" => "ToolResult",
      "type" => atom_to_string(tr[:type] || tr["type"] || :function),
      "tool_call_id" => tr[:tool_call_id] || tr["tool_call_id"],
      "name" => tr[:name] || tr["name"],
      "content" => serialize_content(tr[:content] || tr["content"]),
      "processed_content" => serialize_any(tr[:processed_content] || tr["processed_content"]),
      "display_text" => tr[:display_text] || tr["display_text"],
      "is_error" => tr[:is_error] || tr["is_error"] || false,
      "options" => serialize_options(tr[:options] || tr["options"])
    }
  end

  defp deserialize_tool_results(nil), do: nil
  defp deserialize_tool_results([]), do: []

  defp deserialize_tool_results(tool_results) when is_list(tool_results) do
    Enum.map(tool_results, &deserialize_tool_result/1)
  end

  defp deserialize_tool_result(%{"_struct" => "ToolResult"} = data) do
    ToolResult.new!(%{
      type: string_to_atom(data["type"], [:function]),
      tool_call_id: data["tool_call_id"],
      name: data["name"],
      content: force_string_content(data["content"]),
      processed_content: deserialize_any(data["processed_content"]),
      display_text: data["display_text"],
      is_error: data["is_error"] || false,
      options: deserialize_options(data["options"])
    })
  end

  defp deserialize_tool_result(%{} = data) do
    # Handle legacy format
    ToolResult.new!(%{
      type: :function,
      tool_call_id: data["tool_call_id"] || data["tool_use_id"],
      name: data["name"],
      content: force_string_content(data["content"]),
      is_error: data["is_error"] || false
    })
  end

  # ===========================================================================
  # ContentPart Serialization
  # ===========================================================================

  defp serialize_content(nil), do: nil
  defp serialize_content(content) when is_binary(content), do: content

  defp serialize_content(content) when is_list(content) do
    Enum.map(content, &serialize_content_part/1)
  end

  defp serialize_content(content), do: serialize_any(content)

  defp serialize_content_part(%ContentPart{} = cp) do
    %{
      "_struct" => "ContentPart",
      "type" => atom_to_string(cp.type),
      "content" => cp.content,
      "options" => serialize_options(cp.options)
    }
  end

  defp serialize_content_part(other), do: serialize_any(other)

  defp deserialize_content(nil), do: nil
  defp deserialize_content(content) when is_binary(content), do: content

  defp deserialize_content(content) when is_list(content) do
    Enum.map(content, &deserialize_content_part/1)
  end

  defp deserialize_content(content), do: deserialize_any(content)

  defp deserialize_content_part(%{"_struct" => "ContentPart"} = data) do
    ContentPart.new!(%{
      type:
        string_to_atom(data["type"], [
          :text,
          :image_url,
          :image,
          :file,
          :file_url,
          :thinking,
          :unsupported
        ]),
      content: data["content"],
      options: deserialize_options(data["options"])
    })
  end

  defp deserialize_content_part(%{"type" => type, "content" => content} = data) do
    # Handle legacy format
    ContentPart.new!(%{
      type:
        string_to_atom(type, [
          :text,
          :image_url,
          :image,
          :file,
          :file_url,
          :thinking,
          :unsupported
        ]),
      content: content,
      options: deserialize_options(data["options"])
    })
  end

  defp deserialize_content_part(other), do: deserialize_any(other)

  # ===========================================================================
  # TokenUsage Serialization
  # ===========================================================================

  defp serialize_token_usage(nil), do: nil

  defp serialize_token_usage(%TokenUsage{} = usage) do
    %{
      "_struct" => "TokenUsage",
      "input" => usage.input,
      "output" => usage.output,
      "raw" => usage.raw,
      "cumulative" => usage.cumulative
    }
  end

  defp serialize_token_usage(%{} = usage) do
    %{
      "_struct" => "TokenUsage",
      "input" => usage[:input] || usage["input"],
      "output" => usage[:output] || usage["output"],
      "raw" => usage[:raw] || usage["raw"] || %{},
      "cumulative" => usage[:cumulative] || usage["cumulative"] || false
    }
  end

  defp deserialize_token_usage(nil), do: nil

  defp deserialize_token_usage(%{"_struct" => "TokenUsage"} = data) do
    TokenUsage.new!(%{
      input: data["input"],
      output: data["output"],
      raw: data["raw"] || %{},
      cumulative: data["cumulative"] || false
    })
  end

  defp deserialize_token_usage(%{"input" => _, "output" => _} = data) do
    # Handle legacy format
    TokenUsage.new!(%{
      input: data["input"],
      output: data["output"],
      raw: data["raw"] || %{},
      cumulative: data["cumulative"] || false
    })
  end

  defp deserialize_token_usage(_), do: nil

  # ===========================================================================
  # Metadata Serialization
  # ===========================================================================

  defp serialize_metadata(nil), do: nil

  defp serialize_metadata(%{usage: usage} = metadata) do
    metadata
    |> from_struct_if_struct()
    |> Map.put("usage", serialize_token_usage(usage))
    |> convert_keys_to_strings()
  end

  defp serialize_metadata(%{} = metadata) do
    metadata
    |> from_struct_if_struct()
    |> convert_keys_to_strings()
  end

  defp deserialize_metadata(nil), do: nil

  defp deserialize_metadata(%{"usage" => usage} = _metadata) when not is_nil(usage) do
    %{usage: deserialize_token_usage(usage)}
  end

  defp deserialize_metadata(%{} = metadata) do
    # Convert string keys back to atoms for common keys
    metadata
    |> Enum.map(fn
      {"usage", v} -> {:usage, deserialize_token_usage(v)}
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
    |> Map.new()
  end

  # ===========================================================================
  # Options Serialization (for keyword lists)
  # ===========================================================================

  defp serialize_options(nil), do: nil
  defp serialize_options([]), do: []

  defp serialize_options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      # Convert keyword list to map with string keys
      opts
      |> Enum.map(fn {k, v} -> {atom_to_string(k), serialize_option_value(v)} end)
      |> Map.new()
      |> Map.put("_is_keyword_list", true)
    else
      Enum.map(opts, &serialize_any/1)
    end
  end

  defp serialize_options(opts), do: opts

  defp serialize_option_value(v) when is_atom(v), do: %{"_atom" => atom_to_string(v)}
  defp serialize_option_value(v), do: v

  defp deserialize_options(nil), do: nil
  defp deserialize_options([]), do: []

  defp deserialize_options(%{"_is_keyword_list" => true} = opts) do
    opts
    |> Map.delete("_is_keyword_list")
    |> Enum.map(fn {k, v} -> {String.to_atom(k), deserialize_option_value(v)} end)
    |> Keyword.new()
  end

  defp deserialize_options(%{} = opts) do
    # If it's a map without the keyword marker, return as keyword list anyway
    # (for backwards compatibility)
    Enum.map(opts, fn {k, v} ->
      key = if is_binary(k), do: String.to_atom(k), else: k
      {key, deserialize_option_value(v)}
    end)
    |> Keyword.new()
  end

  defp deserialize_options(opts) when is_list(opts), do: opts

  defp deserialize_option_value(%{"_atom" => atom_str}), do: String.to_atom(atom_str)
  defp deserialize_option_value(v), do: v

  # ===========================================================================
  # Helpers
  # ===========================================================================

  # For tool messages, extract content from tool_results if the message content is nil/empty
  # Fresh LangChain tool messages may have content as nil while the actual result is in tool_results
  defp normalize_tool_message_content(%Message{role: :tool, tool_results: [first | _]} = message) do
    case message.content do
      nil -> force_string_content(first.content)
      "" -> force_string_content(first.content)
      [] -> force_string_content(first.content)
      content -> content
    end
  end

  defp normalize_tool_message_content(%Message{} = message), do: message.content

  defp build_tool_message(data) do
    # For tool messages, we need tool_results
    tool_results = deserialize_tool_results(data["tool_results"]) || []

    if tool_results != [] do
      # Use the first tool result to build the message
      first_result = List.first(tool_results)

      # ToolResult may store content as ContentPart list internally (due to migrate_to_content_parts),
      # so we need to extract the string content
      content = force_string_content(first_result.content)

      # NOTE: We cannot use Message.new_tool_result!/1 here because it internally calls
      # migrate_to_content_parts() which converts our string to ContentParts, and then
      # the validator rejects ContentParts for role :tool. This is a limitation in LangChain.
      # We construct the struct directly with validated string content.
      %Message{
        role: :tool,
        content: content,
        status: :complete,
        tool_results: tool_results
      }
    else
      # Fallback: create a basic tool message from raw data
      content = force_string_content(data["content"])

      # Same limitation applies here
      %Message{
        role: :tool,
        content: content || "",
        status: :complete
      }
    end
  end

  # Aggressively extract string content from any format
  # This is a last-resort function that handles ALL possible input formats
  defp force_string_content(nil), do: ""
  defp force_string_content(content) when is_binary(content), do: content

  defp force_string_content(content) when is_list(content) do
    mapped = Enum.map(content, &force_string_from_part/1)
    filtered = Enum.reject(mapped, &(&1 == "" or is_nil(&1)))
    result = Enum.join(filtered, "\n")

    case result do
      "" -> inspect(content)
      _ -> result
    end
  end

  # Handle maps with atom key :content
  defp force_string_content(%{content: content}), do: force_string_content(content)
  # Handle serialized maps with string key "content" (from JSON/DB)
  defp force_string_content(%{"content" => content}), do: force_string_content(content)
  defp force_string_content(other), do: inspect(other)

  # Extract string from any content part format
  defp force_string_from_part(nil), do: ""
  defp force_string_from_part(text) when is_binary(text), do: text

  defp force_string_from_part(%{__struct__: _, content: content}) do
    force_string_content(content)
  end

  defp force_string_from_part(%{content: content}) when is_binary(content), do: content
  defp force_string_from_part(%{content: content}), do: force_string_content(content)
  defp force_string_from_part(%{"content" => content}) when is_binary(content), do: content
  defp force_string_from_part(%{"content" => content}), do: force_string_content(content)
  defp force_string_from_part(other), do: inspect(other)

  defp atom_to_string(nil), do: nil
  defp atom_to_string(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp atom_to_string(str) when is_binary(str), do: str

  defp string_to_atom(nil, _allowed), do: nil
  defp string_to_atom(atom, _allowed) when is_atom(atom), do: atom

  defp string_to_atom(str, allowed) when is_binary(str) do
    atom = String.to_atom(str)
    if atom in allowed, do: atom, else: nil
  end

  defp serialize_any(nil), do: nil
  defp serialize_any(value) when is_binary(value), do: value
  defp serialize_any(value) when is_number(value), do: value
  defp serialize_any(value) when is_boolean(value), do: value
  defp serialize_any(value) when is_atom(value), do: %{"_atom" => atom_to_string(value)}

  defp serialize_any(value) when is_list(value) do
    Enum.map(value, &serialize_any/1)
  end

  defp serialize_any(value) when is_map(value) do
    value
    |> from_struct_if_struct()
    |> Enum.map(fn {k, v} -> {to_string_key(k), serialize_any(v)} end)
    |> Map.new()
  end

  defp serialize_any(value), do: inspect(value)

  defp deserialize_any(nil), do: nil
  defp deserialize_any(%{"_atom" => atom_str}), do: String.to_atom(atom_str)
  defp deserialize_any(value) when is_binary(value), do: value
  defp deserialize_any(value) when is_number(value), do: value
  defp deserialize_any(value) when is_boolean(value), do: value

  defp deserialize_any(value) when is_list(value) do
    Enum.map(value, &deserialize_any/1)
  end

  defp deserialize_any(value) when is_map(value) do
    Enum.map(value, fn {k, v} -> {k, deserialize_any(v)} end)
    |> Map.new()
  end

  defp deserialize_any(value), do: value

  defp to_string_key(key) when is_atom(key), do: Atom.to_string(key)
  defp to_string_key(key) when is_binary(key), do: key
  defp to_string_key(key), do: inspect(key)

  defp convert_keys_to_strings(map) when is_map(map) do
    Enum.map(map, fn {k, v} -> {to_string_key(k), v} end)
    |> Map.new()
  end

  # Helper to convert struct to map if needed
  defp from_struct_if_struct(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp from_struct_if_struct(map) when is_map(map), do: map
end
