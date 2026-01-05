defmodule Play.Web.Live.Nodes do
  # ============================================================================
  # Node Type Definitions
  # ============================================================================

  # Define all available node types for LLM agent workflows.
  # Each node type is a map with the following keys:
  # - type: unique identifier (required)
  # - title: display name
  # - description: help text
  # - category: category path (e.g., "llm", "agent", "input", "output", "utility")
  # - inputs: list of %{name: string, type: string | nil}
  # - outputs: list of %{name: string, type: string | nil}
  # - properties: list of %{name: string, default: any}
  # - widgets: list of widget definitions
  # - size: [width, height]
  # - color: node header color
  # - bgcolor: node body color
  # - execute_code: JavaScript code for onExecute (receives inputs array and properties)
  # - display_value: %{property: string, font: string, color: string} for displaying value
  def node_types do
    [
      # LLM Provider nodes
      openai_node(),
      anthropic_node(),
      google_ai_node(),
      xai_node(),

      # Agent nodes
      stateless_agent_node(),

      # Input nodes
      text_input_node(),
      number_input_node(),
      variable_node(),
      message_input_node(),

      # Output nodes
      display_node(),
      console_node(),
      conversation_display_node(),

      # Utility nodes
      message_builder_node(),
      messages_combiner_node(),
      prompt_template_node(),
      json_parse_node(),
      condition_node(),

      # Tool nodes
      web_search_tool_node(),
      tools_combiner_node(),

      # Storage nodes
      load_conversation_node(),
      save_conversation_node()
    ]
  end

  # ============================================================================
  # LLM Provider Nodes
  # ============================================================================

  defp openai_node do
    %{
      type: "openai",
      title: "OpenAI",
      description: "OpenAI LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "gpt-5.2"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "gpt-5.2",
          options: %{
            values: ["gpt-5.2", "gpt-5.2-pro", "gpt-5-mini", "gpt-5-nano"]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [200, 170],
      color: "#10a37f",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'openai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp anthropic_node do
    %{
      type: "anthropic",
      title: "Anthropic",
      description: "Anthropic Claude LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "claude-sonnet-4-5"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "claude-sonnet-4-5",
          options: %{
            values: [
              "claude-sonnet-4-5",
              "claude-opus-4-5",
              "claude-haiku-4-5"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [220, 170],
      color: "#cc785c",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'anthropic',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp google_ai_node do
    %{
      type: "google_ai",
      title: "Google AI",
      description: "Google Gemini LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "gemini-3-pro-preview"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "gemini-3-pro-preview",
          options: %{
            values: [
              "gemini-3-pro-preview",
              "gemini-3-flash-preview"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [200, 170],
      color: "#4285f4",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'google_ai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  defp xai_node do
    %{
      type: "xai",
      title: "xAI Grok",
      description: "xAI Grok LLM configuration",
      category: "llm",
      inputs: [],
      outputs: [%{name: "llm_config", type: "llm_config"}],
      properties: [
        %{name: "model", default: "grok-4-1-fast"},
        %{name: "reasoning_effort", default: "medium"}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Model",
          property: "model",
          default: "grok-4-1-fast",
          options: %{
            values: [
              "grok-4-1-fast",
              "grok-4-1-fast-non-reasoning",
              "grok-code-fast-1",
              "grok-4-fast",
              "grok-4-fast-non-reasoning",
              "grok-4",
              "grok-3-mini",
              "grok-3"
            ]
          }
        },
        %{
          type: "combo",
          name: "Reasoning",
          property: "reasoning_effort",
          default: "medium",
          options: %{
            values: ["none", "minimal", "low", "medium", "high", "xhigh"]
          }
        }
      ],
      size: [220, 170],
      color: "#ffffff",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        provider: 'xai',
        model: properties.model,
        reasoning_effort: properties.reasoning_effort
      };
      """
    }
  end

  # ============================================================================
  # Agent Nodes
  # ============================================================================

  defp stateless_agent_node do
    %{
      type: "stateless_agent",
      title: "Agent",
      description:
        "LLM Agent that processes messages with a system prompt and optional tools. Does not retain conversation history between runs.",
      category: "agent",
      inputs: [
        %{name: "llm_config", type: "llm_config"},
        %{name: "system", type: "text"},
        %{name: "messages", type: "messages"},
        %{name: "tools", type: "tools"}
      ],
      outputs: [
        %{name: "response", type: "text"},
        %{name: "messages_out", type: "messages"},
        %{name: "tool_calls", type: "tool_calls"}
      ],
      properties: [
        %{name: "system_prompt", default: "You are a helpful assistant."},
        %{name: "stream", default: false}
      ],
      widgets: [
        %{
          type: "text",
          name: "System Prompt",
          property: "system_prompt",
          default: "You are a helpful assistant.",
          options: %{multiline: true}
        },
        %{
          type: "toggle",
          name: "Stream",
          property: "stream",
          default: false
        }
      ],
      # Hide "System Prompt" widget when "system" input is connected
      hide_widget_on_input: %{"system" => "System Prompt"},
      size: [280, 200],
      color: "#9333ea",
      bgcolor: "#1e1e2f",
      execute_code: """
      const llm_config = inputs[0];
      const system_override = inputs[1];
      const messages = inputs[2] || [];
      const tools = inputs[3] || [];
      const system_prompt = system_override || properties.system_prompt;

      // Store config for server-side execution
      this.properties._pending_execution = {
        llm_config: llm_config,
        messages: messages,
        tools: tools,
        system_prompt: system_prompt,
        stream: properties.stream
      };

      // Return current stored response (will be updated by server)
      return { 
        0: this.properties._last_response || '',
        1: this.properties._messages_out || messages,
        2: this.properties._tool_calls || []
      };
      """
    }
  end

  # ============================================================================
  # Input Nodes
  # ============================================================================

  defp text_input_node do
    %{
      type: "text_input",
      title: "Text Input",
      description: "Enter text input for the workflow",
      category: "input",
      outputs: [%{name: "text", type: "text"}],
      properties: [%{name: "value", default: ""}],
      widgets: [
        %{
          type: "text",
          name: "Text",
          property: "value",
          default: "",
          options: %{multiline: true}
        }
      ],
      size: [220, 100],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.value;"
    }
  end

  defp number_input_node do
    %{
      type: "number_input",
      title: "Number Input",
      description: "Enter a numeric value for the workflow",
      category: "input",
      outputs: [%{name: "number", type: "number"}],
      properties: [
        %{name: "value", default: 0},
        %{name: "min", default: nil},
        %{name: "max", default: nil},
        %{name: "step", default: 1}
      ],
      widgets: [
        %{
          type: "number",
          name: "Value",
          property: "value",
          default: 0,
          options: %{step: 1}
        }
      ],
      size: [180, 80],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.value;"
    }
  end

  defp variable_node do
    %{
      type: "variable",
      title: "Variable",
      description: "Named variable with a default value",
      category: "input",
      outputs: [%{name: "value", type: nil}],
      properties: [
        %{name: "name", default: "my_var"},
        %{name: "default_value", default: ""}
      ],
      widgets: [
        %{
          type: "text",
          name: "Name",
          property: "name",
          default: "my_var"
        },
        %{
          type: "text",
          name: "Default",
          property: "default_value",
          default: ""
        }
      ],
      size: [180, 120],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: "return properties.default_value;"
    }
  end

  defp message_input_node do
    %{
      type: "message_input",
      title: "Message Input",
      description:
        "User message input that appears in the sidebar. When present, a textarea will be shown for user input.",
      category: "input",
      outputs: [%{name: "message", type: "message"}],
      properties: [
        %{name: "label", default: "User Message"}
      ],
      widgets: [
        %{
          type: "text",
          name: "Label",
          property: "label",
          default: "User Message"
        }
      ],
      size: [200, 80],
      color: "#22c55e",
      bgcolor: "#1a1a2e",
      execute_code: """
      // Runtime value is injected by the server during execution
      // This returns a placeholder that will be replaced by actual user input
      return { role: 'user', content: properties._runtime_value || '' };
      """
    }
  end

  # ============================================================================
  # Output Nodes
  # ============================================================================

  defp display_node do
    %{
      type: "display",
      title: "Display",
      description: "Displays the input value on the node",
      category: "output",
      inputs: [%{name: "value", type: nil}],
      properties: [%{name: "value", default: ""}],
      size: [300, 100],
      color: "#f59e0b",
      bgcolor: "#1a1a2e",
      resizable: true,
      execute_code: """
      const val = inputs[0];
      this.properties.value = typeof val === 'object' ? JSON.stringify(val, null, 2) : String(val ?? '');
      """,
      display_value: %{property: "value", font: "14px monospace", color: "#fff"}
    }
  end

  defp console_node do
    %{
      type: "console",
      title: "Console",
      description: "Logs the input value to console",
      category: "output",
      inputs: [%{name: "value", type: nil}],
      properties: [%{name: "prefix", default: ""}],
      widgets: [
        %{
          type: "text",
          name: "Prefix",
          property: "prefix",
          default: ""
        }
      ],
      size: [180, 80],
      color: "#f59e0b",
      bgcolor: "#1a1a2e",
      execute_code: """
      const prefix = properties.prefix ? properties.prefix + ': ' : '';
      console.log(prefix, inputs[0]);
      """
    }
  end

  defp conversation_display_node do
    %{
      type: "conversation_display",
      title: "Conversation Display",
      description:
        "Displays conversation messages in the sidebar. Connect to an Agent's messages_out output to view the full conversation with system prompts, tool calls, and token usage.",
      category: "output",
      inputs: [%{name: "messages", type: "messages"}],
      properties: [%{name: "label", default: "Conversation"}],
      widgets: [
        %{
          type: "text",
          name: "Label",
          property: "label",
          default: "Conversation"
        }
      ],
      size: [200, 80],
      color: "#f59e0b",
      bgcolor: "#1a1a2e",
      execute_code: """
      // Store the messages for server-side processing and sidebar display
      this.properties._messages = inputs[0] || [];
      """
    }
  end

  # ============================================================================
  # Utility Nodes
  # ============================================================================

  defp message_builder_node do
    %{
      type: "message_builder",
      title: "Message Builder",
      description: "Builds a message with role and content",
      category: "utility",
      inputs: [%{name: "content", type: "text"}],
      outputs: [%{name: "message", type: "message"}],
      properties: [
        %{name: "role", default: "user"},
        %{name: "content", default: ""}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Role",
          property: "role",
          default: "user",
          options: %{values: ["user", "assistant"]}
        },
        %{
          type: "text",
          name: "Content",
          property: "content",
          default: "",
          options: %{multiline: true}
        }
      ],
      # Hide "Content" widget when "content" input is connected
      hide_widget_on_input: %{"content" => "Content"},
      size: [200, 120],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      const content = inputs[0] || properties.content;
      return { role: properties.role, content: content };
      """
    }
  end

  defp messages_combiner_node do
    %{
      type: "messages_combiner",
      title: "Messages",
      description:
        "Combines messages into an array. First input accepts an existing messages array to append to. Right-click to add/remove message inputs.",
      category: "utility",
      inputs: [
        %{name: "messages", type: "messages"},
        %{name: "msg1", type: "message"}
      ],
      outputs: [%{name: "messages", type: "messages"}],
      properties: [%{name: "input_count", default: 1}],
      size: [160, 100],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      # Enable dynamic inputs - the JS hook will add menu options to add/remove
      # Starting from slot 1 (slot 0 is reserved for messages input)
      dynamic_inputs: %{
        type: "message",
        name_prefix: "msg",
        min: 1,
        max: 20,
        start_slot: 1,
        # Automatically add a new input when the last one is connected
        auto_add: true
      },
      execute_code: """
      // First input (slot 0) is the messages array to append to
      const baseMessages = Array.isArray(inputs[0]) ? inputs[0] : [];
      const result = [...baseMessages];

      // Remaining inputs are individual messages
      for (let i = 1; i < inputs.length; i++) {
        if (inputs[i] && typeof inputs[i] === 'object' && inputs[i].role && inputs[i].content) {
          result.push(inputs[i]);
        }
      }
      return result;
      """
    }
  end

  defp prompt_template_node do
    %{
      type: "prompt_template",
      title: "Prompt Template",
      description: "String interpolation with {{variable}} syntax",
      category: "utility",
      inputs: [
        %{name: "var1", type: "text"},
        %{name: "var2", type: "text"},
        %{name: "var3", type: "text"}
      ],
      outputs: [%{name: "text", type: "text"}],
      properties: [
        %{name: "template", default: "Hello {{var1}}!"},
        %{name: "var1_name", default: "var1"},
        %{name: "var2_name", default: "var2"},
        %{name: "var3_name", default: "var3"}
      ],
      widgets: [
        %{
          type: "text",
          name: "Template",
          property: "template",
          default: "Hello {{var1}}!"
        },
        %{
          type: "text",
          name: "Var1 Name",
          property: "var1_name",
          default: "var1"
        },
        %{
          type: "text",
          name: "Var2 Name",
          property: "var2_name",
          default: "var2"
        },
        %{
          type: "text",
          name: "Var3 Name",
          property: "var3_name",
          default: "var3"
        }
      ],
      size: [240, 210],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      let result = properties.template;
      const vars = {
        [properties.var1_name]: inputs[0] || '',
        [properties.var2_name]: inputs[1] || '',
        [properties.var3_name]: inputs[2] || ''
      };
      for (const [key, value] of Object.entries(vars)) {
        result = result.replace(new RegExp('\\\\{\\\\{' + key + '\\\\}\\\\}', 'g'), value);
      }
      return result;
      """
    }
  end

  defp json_parse_node do
    %{
      type: "json_parse",
      title: "JSON Parse",
      description: "Parses a JSON string into an object",
      category: "utility",
      inputs: [%{name: "text", type: "text"}],
      outputs: [%{name: "object", type: nil}],
      size: [160, 60],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      try {
        return JSON.parse(inputs[0] || '{}');
      } catch (e) {
        return { error: e.message };
      }
      """
    }
  end

  defp condition_node do
    %{
      type: "condition",
      title: "Condition",
      description: "Routes value based on condition",
      category: "utility",
      inputs: [
        %{name: "value", type: nil},
        %{name: "condition", type: "boolean"}
      ],
      outputs: [
        %{name: "true", type: nil},
        %{name: "false", type: nil}
      ],
      properties: [%{name: "check_truthy", default: false}],
      widgets: [
        %{
          type: "toggle",
          name: "Check Truthy",
          property: "check_truthy",
          default: false
        }
      ],
      size: [160, 100],
      color: "#6366f1",
      bgcolor: "#1a1a2e",
      execute_code: """
      const value = inputs[0];
      let cond = inputs[1];
      if (properties.check_truthy) {
        cond = !!value;
      }
      return cond ? { 0: value, 1: null } : { 0: null, 1: value };
      """
    }
  end

  # ============================================================================
  # Tool Nodes
  # ============================================================================

  defp web_search_tool_node do
    %{
      type: "web_search_tool",
      title: "Web Search",
      description: "Web search tool using SearxNG. The LLM decides when to call it.",
      category: "tool",
      outputs: [%{name: "tool", type: "tool"}],
      properties: [
        %{name: "max_results", default: 5}
      ],
      widgets: [
        %{
          type: "number",
          name: "Max Results",
          property: "max_results",
          default: 10,
          options: %{min: 1, max: 20, step: 1, precision: 0}
        }
      ],
      size: [200, 90],
      color: "#ec4899",
      bgcolor: "#1a1a2e",
      execute_code: """
      return {
        type: 'function',
        function: {
          name: 'web_search',
          description: 'Search the web for current information. Use this when you need to find up-to-date information about any topic.',
          parameters: {
            type: 'object',
            properties: {
              query: {
                type: 'string',
                description: 'The search query'
              }
            },
            required: ['query']
          }
        },
        _config: {
          max_results: properties.max_results
        }
      };
      """
    }
  end

  defp tools_combiner_node do
    %{
      type: "tools_combiner",
      title: "Tools",
      description:
        "Combines multiple tools into an array. Right-click to add/remove tool inputs.",
      category: "tool",
      inputs: [
        %{name: "tool1", type: "tool"}
      ],
      outputs: [%{name: "tools", type: "tools"}],
      properties: [%{name: "input_count", default: 1}],
      size: [160, 70],
      color: "#ec4899",
      bgcolor: "#1a1a2e",
      # Enable dynamic inputs - the JS hook will add menu options to add/remove
      # Starting from slot 0 (no reserved slots)
      dynamic_inputs: %{
        type: "tool",
        name_prefix: "tool",
        min: 1,
        max: 10,
        start_slot: 0,
        # Automatically add a new input when the last one is connected
        auto_add: true
      },
      execute_code: """
      const tools = [];
      for (let i = 0; i < inputs.length; i++) {
        if (inputs[i] && typeof inputs[i] === 'object' && inputs[i].type === 'function') {
          tools.push(inputs[i]);
        }
      }
      return tools;
      """
    }
  end

  # ============================================================================
  # Storage Nodes
  # ============================================================================

  defp load_conversation_node do
    %{
      type: "load_conversation",
      title: "Load Conversation",
      description:
        "Load conversation history from the database. Select a saved conversation to restore its messages.",
      category: "storage",
      inputs: [],
      outputs: [%{name: "messages", type: "messages"}],
      properties: [
        %{name: "conversation_id", default: nil}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Conversation",
          property: "conversation_id",
          default: nil,
          options: %{
            values: [],
            # Dynamic values will be populated from DB
            dynamic: true,
            dynamic_source: "conversations"
          }
        },
        %{
          type: "button",
          name: "Edit Conversation",
          callback: "editConversation"
        }
      ],
      size: [240, 140],
      color: "#06b6d4",
      bgcolor: "#1a1a2e",
      execute_code: """
      // Server-side execution will fetch from database
      return this.properties._loaded_messages || [];
      """
    }
  end

  defp save_conversation_node do
    %{
      type: "save_conversation",
      title: "Save Conversation",
      description:
        "Save conversation history to the database. Choose to create a new conversation or update an existing one.",
      category: "storage",
      inputs: [%{name: "messages", type: "messages"}],
      outputs: [],
      properties: [
        %{name: "conversation_id", default: "__new__"},
        %{name: "new_name", default: "New Conversation"},
        %{name: "mode", default: "override"},
        %{name: "auto_save", default: false}
      ],
      widgets: [
        %{
          type: "combo",
          name: "Conversation",
          property: "conversation_id",
          default: "__new__",
          options: %{
            values: ["__new__"],
            # Dynamic values will be populated from DB
            dynamic: true,
            dynamic_source: "conversations",
            include_new_option: true
          }
        },
        %{
          type: "text",
          name: "Name",
          property: "new_name",
          default: "New Conversation"
        },
        %{
          type: "combo",
          name: "Mode",
          property: "mode",
          default: "override",
          options: %{
            values: ["override", "append"]
          }
        },
        %{
          type: "toggle",
          name: "Save automatically",
          property: "auto_save",
          default: false
        },
        %{
          type: "button",
          name: "Save",
          callback: "saveConversation"
        }
      ],
      # Hide "Name" widget when not creating new conversation
      hide_widget_on_property: %{"conversation_id" => %{widget: "Name", hide_when_not: "__new__"}},
      # Hide "Save" button when auto_save is enabled
      hide_widget_on_property_true: %{"auto_save" => "Save"},
      size: [260, 240],
      color: "#06b6d4",
      bgcolor: "#1a1a2e",
      execute_code: """
      const messages = inputs[0] || [];
      // Store for server-side processing
      this.properties._pending_save = {
        messages: messages,
        conversation_id: properties.conversation_id,
        new_name: properties.new_name,
        mode: properties.mode,
        auto_save: properties.auto_save
      };
      """
    }
  end
end
